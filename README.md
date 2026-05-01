# gitlab-mr-review

A Claude Code skill that fetches, reviews, and posts inline comments on GitLab Merge Requests.

## Prerequisites

### `jq`

```bash
# Linux
sudo apt install jq -y

# macOS
brew install jq
```

Windows（PowerShell，任选其一）：
```powershell
winget install jqlang.jq   # Windows 10 1709+ 内置
choco install jq           # 或 Chocolatey
```

### `curl`

| 平台 | 工具 | 说明 |
|------|------|------|
| macOS / Linux | `curl` | 系统内置 |
| Windows（推荐） | Git Bash 中的 `curl` | 命令与 macOS/Linux 完全相同 |
| Windows（备选） | PowerShell 7+ 中的 `curl.exe` | [下载 PowerShell 7+](https://github.com/PowerShell/PowerShell/releases)；Win 10 1803+ 内置 `curl.exe`，**不能**用 `curl`（是 `Invoke-WebRequest` 的别名） |

### `GITLAB_TOKEN`

1. 打开 `<your-gitlab-host>/-/user_settings/personal_access_tokens`
2. 创建 token，Scopes 勾选 **api**，复制

设置环境变量：

```bash
# bash（Linux）
echo 'export GITLAB_TOKEN=glpat-xxxxxxxxxxxxxxxxxxxx' >> ~/.bashrc

# zsh（macOS）
echo 'export GITLAB_TOKEN=glpat-xxxxxxxxxxxxxxxxxxxx' >> ~/.zshrc
```

```powershell
# PowerShell（Windows，永久）
[Environment]::SetEnvironmentVariable('GITLAB_TOKEN','glpat-xxxxxxxxxxxxxxxxxxxx','User')
```

重开终端后生效。

| 变量 | 必填 | 说明 |
|------|------|------|
| `GITLAB_TOKEN` | 是 | 需要 `api` scope |
| `GITLAB_HOST` | 否 | 自动从 MR URL 推断 |

## Install

```bash
npx skills add Jef-Z/gitlab-mr-review
```

## Usage

In any project, tell Claude Code:

```
review https://gitlab.example.com/group/repo/-/merge_requests/42
/gitlab-mr-review https://gitlab.example.com/group/repo/-/merge_requests/42
```

Claude will:

1. Fetch the MR diff from GitLab
2. Analyze changed lines for bugs, logic errors, security issues, and code quality
3. Post inline comments directly to the MR, one comment per issue

Comments are written in Chinese and attached to the exact line in the diff.

## Required setup: install the PreToolUse hook

Claude Code prompts for confirmation on every Bash command containing a shell variable expansion (e.g. `$GITLAB_TOKEN`), even when an allowlist prefix matches. Without a hook, a single MR review triggers dozens of approval prompts. **The skill treats hook installation as mandatory** — it will abort if the hook is missing.

Two versions are shipped; pick the one that matches your environment:

| Script | Environment |
| ------ | ----------- |
| [`hooks/allow-gitlab-curl.sh`](hooks/allow-gitlab-curl.sh) | macOS / Linux / WSL / Git Bash |
| [`hooks/allow-gitlab-curl.ps1`](hooks/allow-gitlab-curl.ps1) | Native Windows PowerShell 7+ (no WSL needed) |

Full installation steps, safeguards, and risk notes: [`hooks/HOOK-SETUP.md`](hooks/HOOK-SETUP.md).

Quick summary:

1. Check whether the hook is already installed — **don't overwrite**, your customized host would be lost:
   - bash: `ls ~/.claude/hooks/allow-gitlab-curl.sh`
   - PowerShell: `Test-Path $HOME\.claude\hooks\allow-gitlab-curl.ps1`
2. If missing, copy the matching script into `~/.claude/hooks/` and set the `ALLOWED_HOST` / `$AllowedHost` value to your GitLab host.
3. Register the hook in `settings.json` under `hooks.PreToolUse` with `matcher: "Bash"`.
4. **Restart your Claude Code session** — hooks only load at startup.

### Fallback: allowlist entry (limited effect)

If you truly can't install the hook, you can add a prefix rule to `~/.claude/settings.json` under `permissions.allow`:

```json
{
  "permissions": {
    "allow": [
      "Bash(curl -sfk -H \"PRIVATE-TOKEN: *)"
    ]
  }
}
```

Caveats:
- Claude Code still prompts for any command containing a shell variable expansion (e.g. `$GITLAB_TOKEN`). The rule mostly helps if you inline the token as a literal, which is not recommended.
- Posting inline comments uses `curl -sfk -X POST ...` — intentionally not covered by the prefix above, so write actions always prompt. Comments leave a trace on the MR, so confirming them is a feature.
- **Do not** use `export GITLAB_HOST=...` or `VAR=value curl ...` to shorten commands; the leading assignment breaks the `curl` prefix match. The skill inlines all non-token values directly into each curl.

Do **not** add the following to the allowlist (side effects, or equivalent to arbitrary code execution): `curl -X POST/PUT/DELETE`, `git add/commit/push/reset`, `glab mr note`, `npx`/`python`/`node`/`bash *`, etc.

## Troubleshooting

| Error | Fix |
|-------|-----|
| 401 Unauthorized | Token invalid or missing `api` scope |
| 404 Not Found | Wrong project path or MR IID |
| 422 Unprocessable | Line not in diff, skipped automatically |
| SSL error | Add `-k` to curl / `curl.exe` |
| Exit code 49 (Windows) | IPv6 binding or proxy interface conflict — add `--ipv4`; if still failing, also add `--noproxy '*'` |
