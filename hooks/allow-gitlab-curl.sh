#!/usr/bin/env bash
# PreToolUse hook：仅自动放行针对指定 GitLab host 的只读/评论 curl 命令。
# 其他一切情况不干预，交还给正常权限流程。
#
# 安装方式见同级目录的 HOOK-SETUP.md。
set -euo pipefail

# 版本号——模板每次改动必须 bump，SKILL.md 会据此引导用户升级
HOOK_VERSION="1.3.0"

# 只信任这个 host，换成你自己的（多个 host 改为数组循环匹配）
ALLOWED_HOST="gitlab.example.com"

input=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$input")
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")

# 允许 Read 工具读取 hook 文件本身（gitlab-mr-review skill Step 0 需要）
if [[ "$tool" == "Read" ]]; then
  file_path=$(jq -r '.tool_input.file_path // empty' <<<"$input")
  if [[ "$file_path" == *"/.claude/hooks/allow-gitlab-curl.sh" ]] || \
     [[ "$file_path" == *"/.claude/hooks/allow-gitlab-curl.ps1" ]]; then
    jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", permissionDecisionReason: "Reading GitLab MR review hook file"}}'
  fi
  exit 0
fi

# 只处理 Bash 工具
[[ "$tool" == "Bash" ]] || exit 0

# 必须以 `curl -sfk -H "PRIVATE-TOKEN: $GITLAB_TOKEN"` 开头（可选 -X POST）
[[ "$cmd" =~ ^curl\ -sfk(\ -X\ POST)?\ -H\ \"PRIVATE-TOKEN:\ \$GITLAB_TOKEN\" ]] || exit 0

# URL 必须指向受信 host
[[ "$cmd" == *"$ALLOWED_HOST"* ]] || exit 0

# 剥掉引号内内容后再扫链接符 / 子 shell 展开。
# 原因：awk/jq 脚本常有 `NR>=1 && NR<=10`、`$0`、`` `...` `` 等
# 在引号内的合法用法，不能误判为 shell 级别的命令拼接。
stripped=$(printf '%s' "$cmd" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")

if [[ "$stripped" == *";"* ]] \
   || [[ "$stripped" == *"&&"* ]] \
   || [[ "$stripped" == *"||"* ]] \
   || [[ "$stripped" == *'$('* ]] \
   || [[ "$stripped" == *'`'* ]] \
   || [[ "$stripped" == *">"* ]] \
   || [[ "$stripped" == *"<"* ]]; then
  exit 0
fi

jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", permissionDecisionReason: "Matched GitLab MR review curl allowlist"}}'
exit 0
