---
name: gitlab-mr-review
description: Fetch, review, and post inline comments on a GitLab Merge Request. Use when user asks to review a GitLab MR/PR, audit code changes, or comment on a merge request.
---

> **⚠ 严禁调用 MR Approve 接口（`/merge_requests/:iid/approve`）。**

# gitlab-mr-review

---

## Step 0 — 前置必要步骤：PreToolUse hook（必须完成）

由于 Claude Code 对任何含 `$GITLAB_TOKEN` / `$env:GITLAB_TOKEN` 变量展开的命令都会弹审批，**不配 hook 会让一次 MR review 触发几十次审批**。本 skill 把 hook 作为必需前置，未配置完成时**中止流程**，不进入后续任何步骤。

**本 skill 要求的 hook 版本：`REQUIRED_HOOK_VERSION = 1.2.0`**（每次模板更新会 bump）。

### 0.1 用 Read 工具读取 hook 文件，提取版本号

**不要**使用 Bash / PowerShell 读文件——那会走命令审批，反而触发本 skill 最想规避的弹窗。用 Claude Code 的 `Read` 工具直接读：

- **bash / macOS / Linux / WSL / Git Bash 用户**：`Read` 文件 `~/.claude/hooks/allow-gitlab-curl.sh`
- **Windows 原生 PowerShell 用户**：`Read` 文件 `%USERPROFILE%\.claude\hooks\allow-gitlab-curl.ps1`（若不确定路径是否被展开，先询问用户 `$HOME` 的值）

读到文件后：
- 在 `.sh` 正文中查找形如 `HOOK_VERSION="x.y.z"` 的行，提取 `x.y.z` 作为 `LOCAL`
- 在 `.ps1` 正文中查找形如 `$HookVersion = 'x.y.z'` 的行，提取 `x.y.z` 作为 `LOCAL`
- 如果 `Read` 报错"文件不存在"，把 `LOCAL` 视为 `MISSING`

### 0.2 根据本地版本决定行动

| `local` 值 | 状态 | 行动 |
|-----------|------|------|
| `MISSING` | 未安装 | 进入下方「A. 未安装时：代用户配置」流程 |
| 等于 `1.2.0` | 已是最新 | 视为已配置完成，继续 Step 1 |
| 小于 `1.2.0` | 过期 | 进入下方「B. 版本过期时：代用户升级」流程 |

> 配置完成后必须让用户**重启 Claude Code 会话**并重新执行 `/gitlab-mr-review <MR URL>`——新 hook 只在下次会话启动时被加载。

### A. 未安装时：代用户配置

不要只抛引导让用户自己读 HOOK-SETUP.md——直接**按步骤帮用户完成配置**：

1. **用 `Read` 工具读取仓库内的 `hooks/HOOK-SETUP.md`**，以它为权威步骤来源（路径形如 `~/.claude/skills/gitlab-mr-review/hooks/HOOK-SETUP.md`，具体看 skill 安装位置）。同时 `Read` 对应的模板脚本（`hooks/allow-gitlab-curl.sh` 或 `.ps1`）拿到最新内容。
2. **询问用户公司的 GitLab host**（例如 `gitlab.corp.example.com`）——这是脚本里 `ALLOWED_HOST` / `$AllowedHost` 唯一需要用户输入的变量。从正在评审的 MR URL 里能推断出主机名，先**猜测**并请用户确认，不要瞎猜后直接写入。
3. **用 `Write` 工具**把模板内容写到用户目录：
   - bash：`~/.claude/hooks/allow-gitlab-curl.sh`
   - PowerShell：`$HOME\.claude\hooks\allow-gitlab-curl.ps1`

   写入时把 `ALLOWED_HOST="gitlab.example.com"` / `$AllowedHost = 'gitlab.example.com'` 替换为用户确认的 host。写入目录不存在时用 Bash `mkdir -p ~/.claude/hooks`（这条命令不含 token / URL / `$(...)`，走正常审批即可）。bash 版写完后记得 `chmod +x`。
4. **处理 `~/.claude/settings.json`**：先 `Read` 现有内容（不存在则视为 `{}`），把 `hooks.PreToolUse` 数组里追加本 skill 需要的 matcher 条目（参考 HOOK-SETUP.md 的 JSON 片段），再用 `Write` 覆盖写回。**关键约束**：
   - 保留用户已有的其他字段（`env` / `theme` / `permissions` / 其他 hook 条目），不要整个覆盖
   - 如果已存在同 `command` 的条目，跳过不重复添加
   - 写回前把最终 JSON 给用户**预览并获得明确确认**后再写入
5. 全部完成后，输出一行提示：

   > hook 已安装（版本 1.2.0），host = `<USER_HOST>`。**请重启 Claude Code 会话**后重新执行 `/gitlab-mr-review <MR URL>`，新 hook 才会生效。

**边界**：
- 不要替用户修改或设置 `GITLAB_TOKEN` / `$env:GITLAB_TOKEN` 环境变量——token 必须由用户自己在 shell profile 里配置。
- 不要尝试"降级"绕过 hook（如让用户一次性批准、把 token 内联成字面值）。

### B. 版本过期时：代用户升级

和 A 段流程一致，但跳过"询问 host"——先 `Read` 用户本地旧脚本，**保留其 `ALLOWED_HOST` 值**，再用新模板覆盖。`settings.json` 通常不需改动（除非 HOOK-SETUP.md 的 JSON 片段也变了）。升级完同样提醒用户**重启会话**。

---

## 参数

调用时可附带 MR 完整 URL 作为参数，例如：
`/gitlab-mr-review https://gitlab.example.com/group/repo/-/merge_requests/42`

若未提供，则在 Step 2 中询问用户。

---

## Step 1 — 依赖工具

本 skill 与 hook 用到：

- **bash 分支**：`curl`, `jq`, `base64`, `sed`, `grep`（主流 Unix 系统默认齐全）
- **Windows 原生 PowerShell 分支**：仅需 PowerShell 7+ 的内建 cmdlet，无外部依赖

**不要主动预检**——预检本身是复杂 bash 语句，会弹审批，反而触发本 skill 最想规避的行为。直接进入后续步骤；如果某条命令后来报 `command not found`，那时再提示用户安装对应工具（Debian/Ubuntu 用 `sudo apt install jq coreutils sed grep curl`，macOS 用 `brew install jq coreutils gnu-sed grep curl`，Windows 升 `winget install Microsoft.PowerShell` 到 7+）。

---

## Step 2 — 解析 MR URL

从调用参数或用户输入中提取以下变量：
`https://gitlab.example.com/group/repo/-/merge_requests/42`

- `$GITLAB_HOST` = `https://gitlab.example.com`
- `$PROJECT_PATH` = `group/repo`
- `$PROJECT_PATH_ENCODED` = `group%2Frepo`（`/` → `%2F`）
- `$MR_IID` = `42`

若无法从参数解析，询问用户提供完整 MR URL。

---

## Step 3 — 检测运行环境

执行以下命令判断当前 shell 类型，**后续所有步骤根据结果选择对应示例**：

```bash
uname -s 2>/dev/null || echo "Windows"
```

- 输出 `Linux` / `Darwin`：使用 **bash** 示例
- 命令不存在或输出 `Windows`：使用 **PowerShell** 示例

> PowerShell 特别注意：
>
> - 用 `Invoke-RestMethod` 替代 `curl`（原生解析 JSON，无需 jq）
> - 环境变量写法为 `$env:GITLAB_TOKEN`
> - 所有请求均加 `-SkipCertificateCheck`（需 PowerShell 7+）

---

## 执行约定（bash，重要）

下方 bash 示例中的 `$GITLAB_HOST` / `$PROJECT_PATH_ENCODED` / `$MR_IID` / `$BASE_SHA` / `$START_SHA` / `$HEAD_SHA` 都是**占位符**。执行时必须遵守：

- **不要使用 `export`** 设置它们，也不要使用 `VAR=value curl ...` 这种前置赋值写法——会让命令不以 `curl` 开头，PreToolUse hook 无法识别放行。
- 每条 `curl` 命令里把这些占位符**直接替换为字面值**，使命令以 `curl -sfk -H "PRIVATE-TOKEN: ...` 开头。
- `$GITLAB_TOKEN` 例外：保留原样，由用户的系统环境变量提供（hook 会放行）。

### 严禁落盘（硬性规则，任何步骤都适用）

本 skill 的所有数据（diff、文件内容、MR 元数据、SHA、中间分析结果）**只在本次会话的上下文中内存保留**，禁止以任何方式写入磁盘。具体禁止：

- **禁止 shell 重定向**：`curl ... > /tmp/foo.json`、`curl ... | tee file`、`curl ... >> file` 等都不允许；hook 已拦截含 `>` / `<` 的命令，会走审批弹窗。
- **禁止调用 `Write` 工具**创建任何 `.json` / `.md` / `.diff` / `.txt` 缓存——即使放在 `/tmp`、`.cache/`、`.claude/` 下也不行。唯一例外是 Step 0 代用户安装 hook 脚本那一次（写入 `~/.claude/hooks/` 和 `settings.json`），那是明确的一次性配置动作。
- **禁止 `tee`、`mkfifo`、`jq > out`** 等隐式落盘手段。

正确做法：一条 `curl | jq` 管道处理完就在上下文中形成分析结果，要再次引用就重跑请求。MR 数据量通常不足以让多拉几次 API 成为性能问题。

---

示例（Step 4 检查 token，用字面值替换后）：

```bash
curl -sfk -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "https://gitlab.example.com/api/v4/user" | jq '.name'
```

---

## Step 4 — 检查环境变量

**bash（macOS / Linux）：**

```bash
curl -sfk -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "$GITLAB_HOST/api/v4/user" | jq '.name'
```

**PowerShell（Windows）：**

```powershell
(Invoke-RestMethod -Uri "$GITLAB_HOST/api/v4/user" `
  -Headers @{"PRIVATE-TOKEN" = $env:GITLAB_TOKEN} `
  -SkipCertificateCheck).name
```

返回用户名则就绪，继续 Step 5。否则引导用户配置（**不要替用户执行这些命令**）：

> 1. 打开 `$GITLAB_HOST/-/user_settings/personal_access_tokens`
> 2. 创建 token，Scopes 勾选 **api**，复制
> 3. 根据系统设置环境变量：
>    - bash（Linux）：`echo 'export GITLAB_TOKEN=glpat-xxx' >> ~/.bashrc`
>    - zsh（macOS）：`echo 'export GITLAB_TOKEN=glpat-xxx' >> ~/.zshrc`
>    - PowerShell（Windows，永久）：`[Environment]::SetEnvironmentVariable('GITLAB_TOKEN','glpat-xxx','User')`
> 4. **关闭当前终端，重新打开一个新的会话**，然后用以下命令继续本次 review：
>
>    ```
>    /gitlab-mr-review $MR_URL
>    ```

---

## Step 5 — 获取 diff_refs（行级评论必需）

**bash（macOS / Linux）：**

```bash
curl -sfk -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "$GITLAB_HOST/api/v4/projects/$PROJECT_PATH_ENCODED/merge_requests/$MR_IID" \
  | jq '{title, state, diff_refs}'
```

**PowerShell（Windows）：**

```powershell
$mr = Invoke-RestMethod `
  -Uri "$GITLAB_HOST/api/v4/projects/$PROJECT_PATH_ENCODED/merge_requests/$MR_IID" `
  -Headers @{"PRIVATE-TOKEN" = $env:GITLAB_TOKEN} `
  -SkipCertificateCheck
$mr | Select-Object title, state, diff_refs
```

保存以下三个值，发行级评论时必须全部提供：

- `$BASE_SHA` ← `diff_refs.base_sha`
- `$START_SHA` ← `diff_refs.start_sha`
- `$HEAD_SHA` ← `diff_refs.head_sha`

---

## Step 6 — 获取 diff 并计算行号

每次取 100 条（GitLab 上限），从 page=1 开始逐页请求，直到返回空数组为止。

**⚠ 执行约束（必须遵守）：**
- 逐页获取后**先累积所有页结果**，待全部获取完毕后再统一分析，保证跨文件上下文完整
- 只使用本文档定义的命令，不得自行增加文件搜索、索引查找等额外操作
- 若某文件 `diff` 字段为空且 `too_large: true`，使用文件内容 API 获取 HEAD 版本全量内容进行审查（见下方"处理 too_large 文件"）

**bash（macOS / Linux）：**

```bash
curl -sfk -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "$GITLAB_HOST/api/v4/projects/$PROJECT_PATH_ENCODED/merge_requests/$MR_IID/diffs?per_page=100&page=PAGE"
```

**PowerShell（Windows）：**

```powershell
Invoke-RestMethod `
  -Uri "$GITLAB_HOST/api/v4/projects/$PROJECT_PATH_ENCODED/merge_requests/$MR_IID/diffs?per_page=100&page=PAGE" `
  -Headers @{"PRIVATE-TOKEN" = $env:GITLAB_TOKEN} `
  -SkipCertificateCheck
```

将 `PAGE` 从 1 开始递增，直到返回空数组为止，**先收集所有页的结果**，提取每个文件的 `new_path`、`old_path`、`diff`、`too_large` 字段，然后在 Step 7 中整体分析，避免因上下文不足造成理解偏差。

### 读取全量文件（分析时按需使用）

分析 diff 时，若某文件的改动难以理解（缺少上下文、依赖其他文件等），可拉取该文件在 HEAD 的完整内容辅助理解：

**bash（macOS / Linux）：**

```bash
# FILE_PATH_ENCODED：将路径中的 / 替换为 %2F，如 src/foo.ts → src%2Ffoo.ts
curl -sfk -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "$GITLAB_HOST/api/v4/projects/$PROJECT_PATH_ENCODED/repository/files/FILE_PATH_ENCODED?ref=$HEAD_SHA" \
  | jq -r '.content' | base64 -d
```

**PowerShell（Windows）：**

```powershell
$filePath = "src%2Ffoo.ts"   # / → %2F
$file = Invoke-RestMethod `
  -Uri "$GITLAB_HOST/api/v4/projects/$PROJECT_PATH_ENCODED/repository/files/$filePath?ref=$HEAD_SHA" `
  -Headers @{"PRIVATE-TOKEN" = $env:GITLAB_TOKEN} `
  -SkipCertificateCheck
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($file.content))
```

### 处理 too_large 文件

当某文件 `diff: ""` 且 `too_large: true` 时，使用上方"读取全量文件"的命令拉取 HEAD 版本进行全量审查，并在分析结论中注明该文件为全量审查（非 diff）。行级评论的 `new_line` 直接使用文件中的实际行号。

### 计算每行的绝对行号

`@@` 头：`@@ -old_start,old_count +new_start,new_count @@`

初始化：`old_num = old_start`，`new_num = new_start`

| 行前缀         | position 用字段      | old_num | new_num |
| -------------- | -------------------- | ------- | ------- |
| ` `（context） | `new_line = new_num` | +1      | +1      |
| `+`（新增）    | `new_line = new_num` | 不变    | +1      |
| `-`（删除）    | `old_line = old_num` | +1      | 不变    |

---

## Step 7 — 分析 diff

**先判断文件类型**：路径匹配 `*.test.ts` / `*.test.tsx` / `*.spec.ts` / `*.spec.tsx` / `__tests__/**` 的视为测试文件，按 [RULES.md 的"测试文件例外"](RULES.md) 执行，放宽生产代码规则（如不要评论 `as` 类型断言、重复 setup、魔法值等），只针对测试独有的反模式（`test.only`、条件断言、缺 `expect`、未 `await`）提问题。其余文件按生产代码标准评审。

检查变更行，关注：

- **功能完整性**：需求是否完整实现，是否存在遗漏的分支或场景
- **逻辑正确性**：条件判断、循环、状态流转是否正确，有无逻辑漏洞或反转
- **边界与异常**：空值、空集合、越界、并发、超时等边界情况是否处理（测试文件不适用——测试本身就是在喂边界）
- **可简化性**：是否有冗余逻辑、重复代码（DRY）、过度抽象或可用语言内置替代的实现（测试文件倾向 DAMP，重复可接受）
- **代码质量**：命名不清、多余复杂度、缺少错误处理、死代码
- **安全**：注入、越权、硬编码密钥
- **性能**：N+1 查询、热路径阻塞（测试文件不适用）
- **代码规范**：见 [RULES.md](RULES.md)

每个问题记录：

```
file:     src/foo.ts
new_line: 42        # 新增/context 行；纯删除行改用 old_line
severity: CRITICAL | WARNING | SUGGESTION
body:     中文描述 + 建议修复
```

只关注变更行，评论内容必须用中文。

---

## Step 7.5 — 汇总问题清单给用户

分析完所有 diff 后，**不要立即发任何评论**。先向用户展示全部发现问题的**汇总**，**每条都要带 diff 上下文**（这是硬性要求——用户需要靠上下文判断问题是否成立，不能只给文件名和行号）。格式如下：

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. [CRITICAL] src/foo.ts:42
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
问题：SQL 字符串拼接导致注入

diff 上下文（±3 行，`>` 标出目标行，保留 +/- 前缀）：
   39 |     const xs = input.map(x => x.id);
   40 |     if (!xs.length) return [];
   41 |
 +>42 |     return db.query(`SELECT * FROM t WHERE id IN (${xs.join(',')})`);
   43 |   }
   44 |
   45 |   export default handler;

建议：改用参数化查询，如 db.query('SELECT * FROM t WHERE id = ANY($1)', [xs])

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
2. [WARNING] src/bar.ts:77
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
...
```

上下文来源：
- 若 Step 5/6 已抓取文件内容，从内存中切 `目标行 ±3 行`
- 否则按需再调一次 `GET /files/FILE?ref=$HEAD_SHA` 取内容后切片
- 保留每行的 `+` / `-` 前缀以区分变更状态；context 行不加前缀

然后明确问用户：**"以上 N 条是否准备开始逐条发送？是则进入 Step 8，会在每条发送前再预览一次完整 body 和 position，等待你批准。"**

用户可以在这里：
- 直接批准 → 进入 Step 8 逐条走
- 要求删改某几条 → 调整清单后再次汇总
- 改变某条严重度 → 调整后再汇总
- 全部取消 → 结束流程

---

## Step 8 — 逐条预览 → 等待批准 → 发送

**绝对规则**：每条评论发送前必须先向用户展示"预览 + 上下文代码"，并等待用户明确批准（"可以"/"发"/"ok"），才能调用 `curl` / `Invoke-RestMethod` 发送。用户可以在每条上选择：批准、跳过、修改 body 后再批准。

### 8.1 单条预览格式

对第 N 条问题，向用户输出如下结构（纯文本，不要立刻调用 API）：

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[N/Total] [CRITICAL] src/foo.ts:42
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
上下文代码（±3 行，`>` 标出目标行）：
   39 |   const xs = input.map(x => x.id);
   40 |   if (!xs.length) return [];
   41 |
 > 42 |   return db.query(`SELECT * FROM t WHERE id IN (${xs.join(',')})`);
   43 | }
   44 |
   45 | export default handler;

评论内容（将作为 body 发送）：
**[CRITICAL]** 直接拼 SQL 字符串会导致注入，改用参数化查询…

position 字段：
  new_path = src/foo.ts
  new_line = 42
  (或 old_path/old_line 若是纯删除行)

是否发送？[y = 发送 / n = 跳过 / e = 修改内容]
```

**上下文代码来源**：若在 Step 6 已抓取文件全量内容可直接切片；否则按需再拉一次 `files/FILE?ref=$HEAD_SHA`，截取 `new_line ± 3` 行。

### 8.2 用户批准后再构造并发送请求

用户回复 `y` 后，才执行下方 `curl` / `Invoke-RestMethod` 命令。发送完把 GitLab 返回的 `discussion id` 或错误码回报给用户，再进入第 N+1 条。

- 返回 422 → 告知用户行号不在 diff 中，标记为"跳过"，不自动重试
- 返回非 2xx → 展示错误，让用户决定重试 / 跳过

**bash（macOS / Linux）：**

```bash
# 新增行 / context 行 → 用 new_line
curl -sfk -X POST \
  -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  -H "Content-Type: application/json" \
  "$GITLAB_HOST/api/v4/projects/$PROJECT_PATH_ENCODED/merge_requests/$MR_IID/discussions" \
  -d '{
    "body": "**[严重程度]** 问题描述",
    "position": {
      "base_sha":      "'"$BASE_SHA"'",
      "start_sha":     "'"$START_SHA"'",
      "head_sha":      "'"$HEAD_SHA"'",
      "position_type": "text",
      "new_path":      "path/to/file.ts",
      "new_line":      42
    }
  }'

# 纯删除行 → 用 old_line
curl -sfk -X POST \
  -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  -H "Content-Type: application/json" \
  "$GITLAB_HOST/api/v4/projects/$PROJECT_PATH_ENCODED/merge_requests/$MR_IID/discussions" \
  -d '{
    "body": "**[严重程度]** 问题描述",
    "position": {
      "base_sha":      "'"$BASE_SHA"'",
      "start_sha":     "'"$START_SHA"'",
      "head_sha":      "'"$HEAD_SHA"'",
      "position_type": "text",
      "old_path":      "path/to/file.ts",
      "old_line":      11
    }
  }'
```

**PowerShell（Windows）：**

```powershell
# 新增行 / context 行 → 用 new_line
$body = @{
  body = "**[严重程度]** 问题描述"
  position = @{
    base_sha      = "ACTUAL_BASE_SHA"
    start_sha     = "ACTUAL_START_SHA"
    head_sha      = "ACTUAL_HEAD_SHA"
    position_type = "text"
    new_path      = "path/to/file.ts"
    new_line      = 42
  }
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Method Post `
  -Uri "$GITLAB_HOST/api/v4/projects/$PROJECT_PATH_ENCODED/merge_requests/$MR_IID/discussions" `
  -Headers @{"PRIVATE-TOKEN" = $env:GITLAB_TOKEN} `
  -ContentType "application/json" `
  -SkipCertificateCheck `
  -Body $body

# 纯删除行 → 将 new_line/new_path 替换为 old_line/old_path
```

> PowerShell 要点：用 `ConvertTo-Json` 构造 body 避免引号转义；SHA 值填入实际值；`Invoke-RestMethod` 会自动解析响应 JSON。

**绝对禁止**：
- 未经用户批准批量连发所有评论（即使 Step 7.5 已汇总过也不行——那一步只是粗筛，Step 8 必须逐条再确认）
- 跳过预览直接执行 `curl -X POST`

---

## Troubleshooting

| Error                        | Fix                                                               |
| ---------------------------- | ----------------------------------------------------------------- |
| 401                          | Token 无效或缺少 `api` scope                                      |
| 404                          | 路径错误，检查 `%2F` 编码                                         |
| 422                          | 行号不在 diff 中，跳过                                            |
| Exit code 49（Windows bash） | IPv6 绑定或代理冲突，curl 加 `--ipv4`；若仍失败加 `--noproxy '*'` |
