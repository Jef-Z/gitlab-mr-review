# Hook 安装：免除每条 curl 的审批

## 背景

Claude Code 的权限白名单无法覆盖含有 shell 变量展开（`$GITLAB_TOKEN` / `$env:GITLAB_TOKEN`）的命令——即使前缀匹配 `Bash(curl -sfk -H "PRIVATE-TOKEN: *)` 规则，每条请求仍会弹审批。

本 hook 用 `PreToolUse` 精确放行一类命令：访问预设 GitLab host、不含命令拼接的 `curl` 或 `Invoke-RestMethod` 请求。其他一切命令都不受影响，继续走正常审批。

本仓库提供两份脚本，按你的 Claude Code 运行环境任选其一：

| 脚本 | 适用环境 |
| ---- | -------- |
| [`allow-gitlab-curl.sh`](./allow-gitlab-curl.sh) | macOS / Linux / WSL / Git Bash |
| [`allow-gitlab-curl.ps1`](./allow-gitlab-curl.ps1) | Windows 原生 PowerShell（PowerShell 7+） |

---

## macOS / Linux / WSL / Git Bash

### 1. 检查是否已安装

```bash
ls ~/.claude/hooks/allow-gitlab-curl.sh 2>/dev/null && echo "已安装，跳到第 3 步" || echo "未安装，继续第 2 步"
```

> ⚠ **如果已存在，请勿覆盖**——你之前改过的 `ALLOWED_HOST` 会被仓库默认值覆盖掉。直接跳到第 3 步确认 settings.json 里有注册项即可。

### 2. 首次安装：复制脚本并修改 host

```bash
mkdir -p ~/.claude/hooks
cp hooks/allow-gitlab-curl.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/allow-gitlab-curl.sh
```

然后编辑 `~/.claude/hooks/allow-gitlab-curl.sh`，把 `ALLOWED_HOST` 改成你公司的 GitLab host：

```bash
ALLOWED_HOST="gitlab.example.com"
```

### 3. 在 `~/.claude/settings.json` 注册 hook

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/allow-gitlab-curl.sh" }
        ]
      },
      {
        "matcher": "Read",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/allow-gitlab-curl.sh" }
        ]
      }
    ]
  }
}
```

若已存在 `hooks.PreToolUse` 配置，合并到数组中即可；注册过则跳过。

重启 Claude Code 会话后生效。

---

## Windows（原生 PowerShell，不需要 WSL）

需要 **PowerShell 7+**（`Invoke-RestMethod -SkipCertificateCheck` 需要）。确认版本：

```powershell
$PSVersionTable.PSVersion
```

若低于 7，从 https://github.com/PowerShell/PowerShell/releases 安装 PowerShell 7。

### 1. 检查是否已安装

```powershell
if (Test-Path $HOME\.claude\hooks\allow-gitlab-curl.ps1) {
  'already installed, skip to step 3'
} else {
  'not installed, continue to step 2'
}
```

> ⚠ 同样规则：**已存在请勿覆盖**，你之前改过的 `$AllowedHost` 会丢失。

### 2. 首次安装：复制脚本并修改 host

```powershell
New-Item -ItemType Directory -Force -Path $HOME\.claude\hooks | Out-Null
Copy-Item hooks\allow-gitlab-curl.ps1 $HOME\.claude\hooks\
```

然后用任意编辑器打开 `%USERPROFILE%\.claude\hooks\allow-gitlab-curl.ps1`，把 `$AllowedHost` 改成你公司的 GitLab host：

```powershell
$AllowedHost = 'gitlab.example.com'
```

> PowerShell 脚本不需要 `chmod +x`，但默认执行策略（`ExecutionPolicy`）可能禁止脚本运行。Claude Code 通过 `pwsh -File` 启动 hook，通常能绕过策略限制；若仍报错，针对当前用户放宽一次即可：
>
> ```powershell
> Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
> ```

### 3. 在 `%USERPROFILE%\.claude\settings.json` 注册 hook

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "pwsh -NoProfile -File %USERPROFILE%\\.claude\\hooks\\allow-gitlab-curl.ps1" }
        ]
      },
      {
        "matcher": "Read",
        "hooks": [
          { "type": "command", "command": "pwsh -NoProfile -File %USERPROFILE%\\.claude\\hooks\\allow-gitlab-curl.ps1" }
        ]
      }
    ]
  }
}
```

> `matcher: "Bash"` 放行 GitLab API 的 curl / Invoke-RestMethod 请求；`matcher: "Read"` 放行 skill Step 0 读取 hook 文件本身。脚本内部会同时兼容 `curl.exe` 与 `Invoke-RestMethod` 两种命令形态。

若已存在 `hooks.PreToolUse` 配置，合并到数组中即可；注册过则跳过。

重启 Claude Code 会话后生效。

---

## 升级到新版本

脚本头部的 `HOOK_VERSION` / `$HookVersion` 随模板演进会 bump。SKILL.md 的 Step 0 会比对你本地安装的版本与 skill 要求的版本，过期时会引导到这一节。

升级的要点：**覆盖脚本 → 改回你的 `ALLOWED_HOST` → 重启**。`settings.json` 的 hook 注册项不需要改。

### 查看本地版本

**bash：**

```bash
grep -E '^HOOK_VERSION=' ~/.claude/hooks/allow-gitlab-curl.sh
```

**PowerShell：**

```powershell
Select-String -Path $HOME\.claude\hooks\allow-gitlab-curl.ps1 -Pattern '^\$HookVersion'
```

### 升级步骤（bash）

```bash
# 1. 先记下你当前的 ALLOWED_HOST
grep ALLOWED_HOST ~/.claude/hooks/allow-gitlab-curl.sh

# 2. 覆盖为新版本（从本仓库拉最新代码后执行）
cp hooks/allow-gitlab-curl.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/allow-gitlab-curl.sh

# 3. 把 ALLOWED_HOST 改回步骤 1 记下的值
$EDITOR ~/.claude/hooks/allow-gitlab-curl.sh
```

### 升级步骤（PowerShell）

```powershell
# 1. 记下当前 $AllowedHost
Select-String -Path $HOME\.claude\hooks\allow-gitlab-curl.ps1 -Pattern '^\$AllowedHost'

# 2. 覆盖
Copy-Item hooks\allow-gitlab-curl.ps1 $HOME\.claude\hooks\ -Force

# 3. 打开新脚本，把 $AllowedHost 改回步骤 1 记下的值
notepad $HOME\.claude\hooks\allow-gitlab-curl.ps1
```

升级完必须**重启 Claude Code 会话**。

---

## 脚本做了哪些加固

| 检查项 | 作用 |
| ------ | ---- |
| 仅处理 `Bash` / `PowerShell` 工具 | 其他工具完全不受影响 |
| 命令必须严格匹配 `curl -sfk -H "PRIVATE-TOKEN: $GITLAB_TOKEN"` 或 `Invoke-RestMethod ... PRIVATE-TOKEN ... $env:GITLAB_TOKEN ... -SkipCertificateCheck` | 前缀锁死，仅允许只读 / `-X POST` |
| URL 必须包含 `ALLOWED_HOST` / `$AllowedHost` | 防止被引导访问其他服务器 |
| 剥掉单/双引号内容后再扫 `;` / `&&` / `\|\|` / `$(...)` / `` `...` ``（Windows 版还禁 `Invoke-Expression` / `iex` / `>` / `Out-File`） | 杜绝 shell 层的命令拼接 / 子 shell 绕过，同时不误伤 `awk 'NR>=1 && NR<=10'` 这类合法内联脚本 |
| 未匹配则退出码 0 且无输出 | 不发表意见，交还给正常权限流程，不会误放行 |

## 风险与边界

- 放行的命令**完全不再询问**，正则必须守严。任何修改脚本前，先本地验证一次。
- `$GITLAB_TOKEN` / `$env:GITLAB_TOKEN` 本身仍由系统 env 提供，hook 不改变 token 的存储方式。
- 如果需要支持多个 host，将 `ALLOWED_HOST` 改为数组，循环匹配即可。
- 本 hook 不影响 `--dangerously-skip-permissions` 等全局模式，也不会绕过 deny 规则。
