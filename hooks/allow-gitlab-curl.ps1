# PreToolUse hook（Windows / PowerShell 版）
# 仅自动放行针对指定 GitLab host 的只读 / 评论 curl（或 Invoke-RestMethod）命令。
# 其他一切情况不干预，交还给正常权限流程。
#
# 安装方式见同级目录的 HOOK-SETUP.md。

$ErrorActionPreference = 'Stop'

# 版本号——模板每次改动必须 bump，SKILL.md 会据此引导用户升级
$HookVersion = '1.3.0'

# 只信任这个 host，换成你自己的（多个 host 改为数组循环匹配）
$AllowedHost = 'gitlab.example.com'

$raw = [Console]::In.ReadToEnd()
if (-not $raw) { exit 0 }

try {
    $input = $raw | ConvertFrom-Json
} catch {
    exit 0
}

$tool = $input.tool_name
$cmd  = $input.tool_input.command

# 允许 Read 工具读取 hook 文件本身（gitlab-mr-review skill Step 0 需要）
if ($tool -eq 'Read') {
    $filePath = $input.tool_input.file_path
    if ($filePath -match '[\\/]\.claude[\\/]hooks[\\/]allow-gitlab-curl\.(sh|ps1)$') {
        @{
            hookSpecificOutput = @{
                hookEventName            = 'PreToolUse'
                permissionDecision       = 'allow'
                permissionDecisionReason = 'Reading GitLab MR review hook file'
            }
        } | ConvertTo-Json -Depth 5 -Compress
    }
    exit 0
}

if ($tool -ne 'Bash' -and $tool -ne 'PowerShell') { exit 0 }
if (-not $cmd) { exit 0 }

# URL 必须包含预设的 GitLab host
if (-not $cmd.Contains($AllowedHost)) { exit 0 }

# 剥掉单/双引号内内容后再扫危险符号，避免 awk/jq 等内联脚本误伤
# （如 `awk 'NR>=1 && NR<=10'` 里的 `&&` 不应触发拼接检测）
$stripped = [regex]::Replace($cmd, "'[^']*'", '')
$stripped = [regex]::Replace($stripped, '"[^"]*"', '')

$forbidden = @(';', '&&', '||', '$(', '`', '>', '<', '| Out-File', 'Invoke-Expression', 'iex ')
foreach ($p in $forbidden) {
    if ($stripped.Contains($p)) { exit 0 }
}

# 允许两种形态：
#   1) Git Bash / curl:            curl -sfk -H "PRIVATE-TOKEN: $GITLAB_TOKEN" ...
#   2) PowerShell Invoke-RestMethod: Invoke-RestMethod ... $env:GITLAB_TOKEN ... -SkipCertificateCheck
$curlPattern = '^\s*curl(\.exe)?\s+-sfk(\s+-X\s+POST)?\s+-H\s+"PRIVATE-TOKEN:\s+\$GITLAB_TOKEN"'
$irmPattern  = '^\s*(\$\w+\s*=\s*)?Invoke-RestMethod\b'

$matched = $false
if ($cmd -match $curlPattern) { $matched = $true }
elseif ($cmd -match $irmPattern) {
    # Invoke-RestMethod 必须明确带 PRIVATE-TOKEN + $env:GITLAB_TOKEN，且加 -SkipCertificateCheck
    if ($cmd -match 'PRIVATE-TOKEN' -and
        $cmd -match '\$env:GITLAB_TOKEN' -and
        $cmd -match '-SkipCertificateCheck') {
        $matched = $true
    }
}

if (-not $matched) { exit 0 }

@{
    hookSpecificOutput = @{
        hookEventName            = 'PreToolUse'
        permissionDecision       = 'allow'
        permissionDecisionReason = 'Matched GitLab MR review allowlist (Windows)'
    }
} | ConvertTo-Json -Depth 5 -Compress

exit 0
