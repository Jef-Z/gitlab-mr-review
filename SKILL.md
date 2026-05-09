---
name: gitlab-mr-review
description: Fetch, review, and post inline comments on a GitLab Merge Request. Use when user asks to review a GitLab MR/PR, audit code changes, or comment on a merge request.
---

> **⚠ Do NOT call the MR Approve endpoint (`/merge_requests/:iid/approve`) under any circumstance.**

# gitlab-mr-review

---

## Language conventions

- **All dialog with the user is in Chinese (Simplified).** Every message this skill prints — progress updates, prompts, summaries, previews, error reports, confirmation questions — must be in Chinese. Treat the English text in this document as implementation spec, not as copy to reproduce verbatim.
- **All review comments posted to GitLab are in Chinese (Simplified).** This applies to both the NEW discussion `body` and the REPLY `body`.
- Field names, API paths, code identifiers, and command syntax stay in their original form (English / ASCII).

---

## Step 0 — Mandatory prerequisite: PreToolUse hook

Claude Code prompts for approval on any command that expands `$GITLAB_TOKEN` / `$env:GITLAB_TOKEN`. **Without the hook, a single MR review can trigger dozens of approval prompts.** This skill treats the hook as a hard prerequisite — if it is not in place, **abort immediately** and do not proceed to any later step.

**Required hook version for this skill: `REQUIRED_HOOK_VERSION = 1.2.0`** (bumped whenever the template changes).

### 0.1 Read the hook file with the Read tool and extract its version

**Do NOT** read the hook file via Bash / PowerShell — that itself triggers a command-approval prompt, which is exactly what this skill is trying to avoid. Use Claude Code's `Read` tool directly:

- **bash / macOS / Linux / WSL / Git Bash users**: `Read` the file `~/.claude/hooks/allow-gitlab-curl.sh`
- **Native Windows PowerShell users**: `Read` the file `%USERPROFILE%\.claude\hooks\allow-gitlab-curl.ps1` (if you are unsure whether that path expands, ask the user what `$HOME` resolves to)

Once read:
- In `.sh`, find a line like `HOOK_VERSION="x.y.z"` and take `x.y.z` as `LOCAL`.
- In `.ps1`, find a line like `$HookVersion = 'x.y.z'` and take `x.y.z` as `LOCAL`.
- If `Read` reports "file not found", treat `LOCAL` as `MISSING`.

### 0.2 Decide what to do based on the local version

| `local` value | Status | Action |
|---------------|--------|--------|
| `MISSING`     | Not installed | Go to **A. Not installed — install on the user's behalf** |
| equal to `1.2.0` | Up to date | Treat as configured; continue to Step 1 |
| less than `1.2.0` | Outdated | Go to **B. Outdated — upgrade on the user's behalf** |

> After any configuration change the user **must restart their Claude Code session** and re-run `/gitlab-mr-review <MR URL>` — new hooks are only loaded on session startup.

### A. Not installed — install on the user's behalf

Do not just point the user at HOOK-SETUP.md and walk away; **guide them through the install step by step**:

1. **Use `Read` to open `hooks/HOOK-SETUP.md` in this repo** as the authoritative source (path is typically `~/.claude/skills/gitlab-mr-review/hooks/HOOK-SETUP.md`, depending on where the skill is installed). Also `Read` the matching template script (`hooks/allow-gitlab-curl.sh` or `.ps1`) to get the latest contents.
2. **Ask the user for their company's GitLab host** (e.g. `gitlab.corp.example.com`) — this is the single variable `ALLOWED_HOST` / `$AllowedHost` in the script that the user must provide. You can **infer** the hostname from the MR URL being reviewed and ask the user to confirm; do not silently guess and write it in.
3. **Use the `Write` tool** to write the template to the user's home directory:
   - bash: `~/.claude/hooks/allow-gitlab-curl.sh`
   - PowerShell: `$HOME\.claude\hooks\allow-gitlab-curl.ps1`

   When writing, substitute `ALLOWED_HOST="gitlab.example.com"` / `$AllowedHost = 'gitlab.example.com'` with the confirmed host. If the target directory does not exist, run `mkdir -p ~/.claude/hooks` via Bash (this command contains no token / URL / `$(...)`, so the normal approval prompt is fine). For the bash version, remember to `chmod +x` afterwards.
4. **Handle `~/.claude/settings.json`**: first `Read` the current contents (treat as `{}` if absent), append this skill's required matcher entries to the `hooks.PreToolUse` array (see the JSON snippet in HOOK-SETUP.md), then `Write` it back. **Key constraints**:
   - Preserve the user's other fields (`env` / `theme` / `permissions` / other hook entries) — do not overwrite the whole file.
   - If an entry with the same `command` already exists, skip it — do not add a duplicate.
   - Before writing back, **preview the final JSON to the user and get explicit confirmation**.
5. Once everything is in place, print this line:

   > Hook installed (version 1.2.0), host = `<USER_HOST>`. **Please restart your Claude Code session**, then re-run `/gitlab-mr-review <MR URL>` so the new hook is loaded.

**Boundaries**:
- Do not set or modify the user's `GITLAB_TOKEN` / `$env:GITLAB_TOKEN` — the token must be configured by the user in their own shell profile.
- Do not try to "work around" the hook (e.g. by asking the user to approve once-for-all, or by inlining the token as a literal string).

### B. Outdated — upgrade on the user's behalf

Same flow as A, but skip the "ask for host" step — first `Read` the user's existing local script and **preserve its `ALLOWED_HOST` value**, then overwrite with the new template. `settings.json` usually needs no change (unless HOOK-SETUP.md's JSON snippet also changed). After the upgrade, remind the user to **restart the session**.

---

## Parameters

The skill accepts the full MR URL as an argument, e.g.:
`/gitlab-mr-review https://gitlab.example.com/group/repo/-/merge_requests/42`

If omitted, ask the user for it in Step 2.

---

## Step 1 — Required tools

This skill and its hook rely on:

- **bash branch**: `curl`, `jq`, `base64`, `sed`, `grep` (available by default on mainstream Unix systems).
- **Native Windows PowerShell branch**: only PowerShell 7+ built-in cmdlets, no external deps.

**Do NOT pre-flight these proactively** — a pre-flight is itself a complex bash statement that triggers approval, defeating the purpose. Proceed straight into the real steps; if some command later returns `command not found`, only then prompt the user to install it (Debian/Ubuntu: `sudo apt install jq coreutils sed grep curl`; macOS: `brew install jq coreutils gnu-sed grep curl`; Windows: `winget install Microsoft.PowerShell` to get PowerShell 7+).

---

## Step 2 — Parse the MR URL

From the argument or user input, extract:
`https://gitlab.example.com/group/repo/-/merge_requests/42`

- `$GITLAB_HOST` = `https://gitlab.example.com`
- `$PROJECT_PATH` = `group/repo`
- `$PROJECT_PATH_ENCODED` = `group%2Frepo` (replace `/` with `%2F`)
- `$MR_IID` = `42`

If you cannot parse these, ask the user for the full MR URL.

---

## Step 3 — Detect the runtime environment

Run the following to determine the current shell, **then use the matching example in every later step**:

```bash
uname -s 2>/dev/null || echo "Windows"
```

- Output `Linux` / `Darwin` → use the **bash** examples.
- Command not found, or output `Windows` → use the **PowerShell** examples.

> PowerShell notes:
>
> - Use `Invoke-RestMethod` instead of `curl` (it parses JSON natively, no jq needed).
> - Environment variable syntax is `$env:GITLAB_TOKEN`.
> - Every request must include `-SkipCertificateCheck` (PowerShell 7+ required).

---

## Execution conventions (bash, important)

The placeholders `$GITLAB_HOST` / `$PROJECT_PATH_ENCODED` / `$MR_IID` / `$BASE_SHA` / `$START_SHA` / `$HEAD_SHA` in the bash examples below must be handled carefully:

- **Do NOT use `export`** to set them, and do NOT use the `VAR=value curl ...` inline-assignment form — either makes the command not start with `curl`, and the PreToolUse hook will fail to recognize and allow it.
- In every `curl` command, **substitute these placeholders with literal values**, so the command starts with `curl -sfk -H "PRIVATE-TOKEN: ...`.
- `$GITLAB_TOKEN` is the exception: leave it as-is — it's provided by the user's environment and the hook allows it.

### No disk writes (hard rule, applies to every step)

All data this skill handles (diffs, file contents, MR metadata, SHAs, intermediate analysis) **lives only in the session context memory** — it must not be written to disk under any circumstance. Specifically forbidden:

- **No shell redirection**: `curl ... > /tmp/foo.json`, `curl ... | tee file`, `curl ... >> file`, etc. The hook already blocks commands containing `>` / `<` and routes them to an approval prompt.
- **No calls to the `Write` tool** to create any `.json` / `.md` / `.diff` / `.txt` caches — not in `/tmp`, not in `.cache/`, not in `.claude/`. The sole exception is the one-time hook install in Step 0 (which writes to `~/.claude/hooks/` and `settings.json`).
- **No `tee`, `mkfifo`, `jq > out`**, or other implicit disk-write mechanisms.

The correct approach: a single `curl | jq` pipeline produces the analysis in context; if you need the data again later, just re-run the request. MR-sized data volumes never make extra API calls a performance concern.

---

Example (Step 4 token check, after literal substitution):

```bash
curl -sfk -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "https://gitlab.example.com/api/v4/user" | jq '.name'
```

---

## Step 4 — Check environment variables

**bash (macOS / Linux):**

```bash
curl -sfk -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "$GITLAB_HOST/api/v4/user" | jq '.name'
```

**PowerShell (Windows):**

```powershell
(Invoke-RestMethod -Uri "$GITLAB_HOST/api/v4/user" `
  -Headers @{"PRIVATE-TOKEN" = $env:GITLAB_TOKEN} `
  -SkipCertificateCheck).name
```

If a username is returned, the environment is ready — continue to Step 5. Otherwise guide the user to configure it (**do NOT run these commands for the user**):

> 1. Open `$GITLAB_HOST/-/user_settings/personal_access_tokens`.
> 2. Create a token with the **api** scope and copy it.
> 3. Set the environment variable for your shell:
>    - bash (Linux): `echo 'export GITLAB_TOKEN=glpat-xxx' >> ~/.bashrc`
>    - zsh (macOS): `echo 'export GITLAB_TOKEN=glpat-xxx' >> ~/.zshrc`
>    - PowerShell (Windows, persistent): `[Environment]::SetEnvironmentVariable('GITLAB_TOKEN','glpat-xxx','User')`
> 4. **Close the current terminal, open a fresh session**, and continue the review with:
>
>    ```
>    /gitlab-mr-review $MR_URL
>    ```

---

## Step 5 — Fetch diff_refs (required for line-level comments)

**bash (macOS / Linux):**

```bash
curl -sfk -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "$GITLAB_HOST/api/v4/projects/$PROJECT_PATH_ENCODED/merge_requests/$MR_IID" \
  | jq '{title, state, diff_refs}'
```

**PowerShell (Windows):**

```powershell
$mr = Invoke-RestMethod `
  -Uri "$GITLAB_HOST/api/v4/projects/$PROJECT_PATH_ENCODED/merge_requests/$MR_IID" `
  -Headers @{"PRIVATE-TOKEN" = $env:GITLAB_TOKEN} `
  -SkipCertificateCheck
$mr | Select-Object title, state, diff_refs
```

Save these three values — all three are mandatory when posting line-level comments:

- `$BASE_SHA`  ← `diff_refs.base_sha`
- `$START_SHA` ← `diff_refs.start_sha`
- `$HEAD_SHA`  ← `diff_refs.head_sha`

---

## Step 5.5 — Fetch existing discussions (for the analysis stage)

Pull all current discussions on the MR. The goal is to let the later analysis stage know "has this line / this issue already been discussed?" so that the skill can avoid duplicate comments and, when appropriate, append information as a reply instead of opening a new discussion.

**bash (macOS / Linux):**

```bash
curl -sfk -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "$GITLAB_HOST/api/v4/projects/$PROJECT_PATH_ENCODED/merge_requests/$MR_IID/discussions?per_page=100&page=PAGE"
```

**PowerShell (Windows):**

```powershell
Invoke-RestMethod `
  -Uri "$GITLAB_HOST/api/v4/projects/$PROJECT_PATH_ENCODED/merge_requests/$MR_IID/discussions?per_page=100&page=PAGE" `
  -Headers @{"PRIVATE-TOKEN" = $env:GITLAB_TOKEN} `
  -SkipCertificateCheck
```

Increment `PAGE` starting from 1 until an empty array is returned.

### Build in-memory indexes

For each discussion, extract (in memory only — no disk writes):

- `discussion_id` ← `.id`
- `resolved`: `true` if `.notes[0].resolvable == true` AND every entry in `.notes[]` has `.resolved == true`; otherwise `false` (non-resolvable discussions are always treated as `false`).
- `notes[]`: in chronological order, keep `{author, body, created_at}` — used by the LLM for semantic judgment later.

Then put each discussion into **one of two separate index tables**, based on its `position` fields:

- If `.notes[0].position.new_line` is set → put into `new_index`, key = `{position.new_path}:{position.new_line}`.
- Otherwise (only `position.old_line` is set) → put into `old_index`, key = `{position.old_path}:{position.old_line}`.

```
new_index:  "src/foo.ts:42"  → [{discussion_id, resolved, notes}, ...]
old_index:  "src/foo.ts:11"  → [{discussion_id, resolved, notes}, ...]
```

**Skip any discussion without a `position`** (i.e. MR-level comments, not line-level) — this skill does not handle them.

When Step 7.1 queries later: if your new issue is to be posted against `new_line`, search `new_index`; if against `old_line` (a pure deletion), search `old_index`. The two tables never cross-match, so deletion-line comments and addition-line comments can never be erroneously merged.

---

## Step 6 — Fetch the diff and compute line numbers

Fetch 100 items per page (GitLab's upper bound), page from 1 upwards, until the response is an empty array.

**⚠ Execution constraints (must follow):**
- Fetch page by page but **accumulate the results first** — only start analysis once every page has been collected, so cross-file context is intact.
- Use only the commands defined in this document; do not spontaneously add file search / index lookup operations.
- If a file has an empty `diff` and `too_large: true`, fall back to the file-contents API to review the HEAD version in full (see "Handling too_large files" below).

**bash (macOS / Linux):**

```bash
curl -sfk -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "$GITLAB_HOST/api/v4/projects/$PROJECT_PATH_ENCODED/merge_requests/$MR_IID/diffs?per_page=100&page=PAGE"
```

**PowerShell (Windows):**

```powershell
Invoke-RestMethod `
  -Uri "$GITLAB_HOST/api/v4/projects/$PROJECT_PATH_ENCODED/merge_requests/$MR_IID/diffs?per_page=100&page=PAGE" `
  -Headers @{"PRIVATE-TOKEN" = $env:GITLAB_TOKEN} `
  -SkipCertificateCheck
```

Increment `PAGE` from 1 until the response is empty. **Collect results from every page first**, extract the `new_path`, `old_path`, `diff`, and `too_large` fields for each file, and then analyze them as a whole in Step 7 to avoid misreadings due to missing context.

### Fetching a full file (use on demand during analysis)

While analyzing the diff, if a change is hard to understand (missing context, depends on other files, etc.), fetch the full HEAD version of the file to help:

**bash (macOS / Linux):**

```bash
# FILE_PATH_ENCODED: replace / with %2F in the path, e.g. src/foo.ts → src%2Ffoo.ts
curl -sfk -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "$GITLAB_HOST/api/v4/projects/$PROJECT_PATH_ENCODED/repository/files/FILE_PATH_ENCODED?ref=$HEAD_SHA" \
  | jq -r '.content' | base64 -d
```

**PowerShell (Windows):**

```powershell
$filePath = "src%2Ffoo.ts"   # / → %2F
$file = Invoke-RestMethod `
  -Uri "$GITLAB_HOST/api/v4/projects/$PROJECT_PATH_ENCODED/repository/files/$filePath?ref=$HEAD_SHA" `
  -Headers @{"PRIVATE-TOKEN" = $env:GITLAB_TOKEN} `
  -SkipCertificateCheck
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($file.content))
```

### Handling too_large files

When a file has `diff: ""` and `too_large: true`, use the "Fetching a full file" command above to pull the HEAD version and review it in full. Note in the analysis that the file was reviewed whole-file (not via diff). For line-level comments, use the file's actual line number directly as `new_line`.

### Computing absolute line numbers for each line

Hunk header: `@@ -old_start,old_count +new_start,new_count @@`

Initialize: `old_num = old_start`, `new_num = new_start`.

| Line prefix        | position field        | old_num | new_num |
| ------------------ | --------------------- | ------- | ------- |
| ` ` (context)      | `new_line = new_num`  | +1      | +1      |
| `+` (addition)     | `new_line = new_num`  | —       | +1      |
| `-` (deletion)     | `old_line = old_num`  | +1      | —       |

---

## Step 7 — Analyze the diff

**First, classify the file**: paths matching `*.test.ts` / `*.test.tsx` / `*.spec.ts` / `*.spec.tsx` / `__tests__/**` are test files and follow the ["test file exceptions" in RULES.md](RULES.md) — relax production-code rules (e.g. do not complain about `as` type casts, duplicated setup, magic values) and only raise issues for test-specific anti-patterns (`test.only`, conditional assertions, missing `expect`, un-`await`ed promises). All other files follow production-code standards.

Inspect the changed lines, focusing on:

- **Functional completeness**: is the requirement fully implemented? Are any branches or scenarios missed?
- **Logical correctness**: are conditionals, loops, and state transitions correct? Are there logic bugs or inversions?
- **Edge cases and error paths**: empty values, empty collections, out-of-bounds, concurrency, timeouts — all handled? (Not applicable to test files — tests are by definition feeding edge inputs.)
- **Simplification opportunities**: redundant logic, repeated code (DRY), over-abstraction, or reinvention of built-ins. (Test files lean toward DAMP — repetition is acceptable.)
- **Code quality**: unclear naming, excess complexity, missing error handling, dead code.
- **Security**: injection, authorization bypass, hard-coded secrets.
- **Performance**: N+1 queries, blocking hot paths. (Not applicable to test files.)
- **Code style**: see [RULES.md](RULES.md).

Record each issue as:

```
file:     src/foo.ts
new_line: 42        # for addition/context lines; for pure deletion lines use old_line instead
severity: CRITICAL | WARNING | SUGGESTION
body:     Chinese description + suggested fix
```

Only review changed lines. **Comment bodies must be written in Chinese** (review-output language convention for this team).

### 7.1 Decide the "send mode" by consulting existing discussions

For each issue you intend to raise, first look it up in the indexes built in Step 5.5:

- If you plan to post with `new_line` → look up `{file}:{new_line}` in `new_index`, plus the neighborhood `{file}:{new_line ± 3}`.
- If you plan to post with `old_line` (a pure deletion line) → look up `{file}:{old_line}` in `old_index`, plus the neighborhood `{file}:{old_line ± 3}`.

The ±3-line neighborhood exists to catch cases like "an existing discussion is anchored on the function signature, but my new issue is inside the function body". Whether the hits actually *overlap semantically* is decided **by you (the LLM) reading each discussion's `notes[].body`** — never apply a mechanical "same line ⇒ merge" rule.

Based on that semantic judgment, fill in the `action` field:

- **No hit (nothing in the neighborhood of either table)** → `action = NEW`: open a new discussion.
- **Hit on an unresolved discussion that overlaps with your issue** → `action = SKIP_DUPLICATE`: skip.
- **Hit on an unresolved discussion with different semantics (or you have a substantive addition)** → `action = REPLY`: reply on that discussion. Record `reply_to = discussion_id`. The reply body must explicitly acknowledge the thread (e.g. "Following up on the discussion above about X, one more note: ...").
- **Hit on an unresolved discussion whose conclusion contradicts your view** → `action = SKIP_SUPERSEDED`: do not post. Explain in the Step 7.5 summary that an existing discussion reached the opposite conclusion and you are withdrawing.
- **Only resolved discussions match** (no unresolved hits) → the resolved content is a reference for your judgment (e.g. the issue was raised before, fixed, but has been reintroduced). Default `action = NEW`, but the body may cite the historical discussion.

The sole basis for semantic judgment is the `notes[].body` content — do not merge issues just because they land "near each other". A single region can legitimately have multiple independent problems.

Every issue carries, finally:

```
file, new_line (or old_line), severity, body
action:   NEW | REPLY | SKIP_DUPLICATE | SKIP_SUPERSEDED
reply_to: <discussion_id>              # only when action = REPLY
ref_note: <one-line gist of the matched discussion>   # required whenever any historical discussion (resolved ones included) was matched; shown in Step 7.5
```

---

## Step 7.5 — Summarize the issue list for the user

After the diff analysis is complete, **do not post any comment yet**. First present the full list of findings as a **summary**, and **every item must include its diff context** (hard requirement — the user relies on the context to judge whether the issue is valid; file name + line number alone is not enough).

**The `action` from Step 7.1 must be visible for each item**, so the user can tell at a glance whether each is "new / reply / skipped" and why. Items marked SKIP_DUPLICATE / SKIP_SUPERSEDED must also be listed (even though they will not enter the Step 8 send loop) — this lets the user see "what the LLM saw from existing discussions and deliberately withdrew".

Start the summary with a **one-line tally** so the user knows how many will actually be sent:

```
Found N issues: will send M (NEW = a / REPLY = b), skipping S (SKIP_DUPLICATE = c / SKIP_SUPERSEDED = d)
```

Then list each item. For items that matched a historical discussion, show the `ref_note` (one-line gist) only — **do not** expand the original thread in full here; the full `notes[]` is expanded in the Step 8.1 REPLY preview to keep Step 7.5 compact. Format:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. [CRITICAL] src/foo.ts:42
   Send mode: new discussion
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Issue: SQL string concatenation → injection

Diff context (±3 lines, `>` marks the target line; +/- prefixes preserved):
   39 |     const xs = input.map(x => x.id);
   40 |     if (!xs.length) return [];
   41 |
 +>42 |     return db.query(`SELECT * FROM t WHERE id IN (${xs.join(',')})`);
   43 |   }
   44 |
   45 |   export default handler;

Suggestion: use parameterized queries, e.g. db.query('SELECT * FROM t WHERE id = ANY($1)', [xs])

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
2. [WARNING] src/bar.ts:77
   Send mode: reply to discussion #a1b2c3d4
   ref_note: @alice noted insufficient null handling but did not mention the timeout case
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
3. [SUGGESTION] src/baz.ts:15
   Send mode: skipped (SKIP_DUPLICATE)
   ref_note: @bob already raised the same naming issue, still unresolved
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
(Not sent — shown so you can verify the LLM's judgment.)
```

Source for the context snippet:
- If the file content was already fetched in Steps 5/6, slice `target ± 3 lines` from memory.
- Otherwise fetch it on demand via `GET /files/FILE?ref=$HEAD_SHA` and slice.
- Keep the `+` / `-` prefixes on changed lines so the user can distinguish adds/deletes; context lines have no prefix.

Then ask the user explicitly: **"Will send M and skip S — start sending one by one? Yes enters Step 8, which previews the full body and position for each item and waits for your approval before posting."**

At this prompt the user can:
- Approve directly → proceed to Step 8, one at a time.
- Edit/remove some items → adjust the list and re-summarize.
- Change an item's severity → adjust and re-summarize.
- **Override a SKIP**: if they disagree with the LLM's SKIP_DUPLICATE / SKIP_SUPERSEDED decision, they can request it be converted back to NEW or REPLY, re-summarize, then send.
- Cancel everything → end the flow.

---

## Step 8 — Per-item preview → await approval → send

**Hard rule**: before every comment is posted, show the user a "preview + context code" block and **wait for explicit approval** ("ok" / "send" / "y") before calling `curl` / `Invoke-RestMethod`. For each item the user may: approve, skip, or edit the body and then approve.

**Only items with `action ∈ {NEW, REPLY}` from Step 7.1 enter this step**; `SKIP_*` items are excluded.

### 8.1 Single-item preview format

For the Nth issue, print the following block as plain text (do NOT call the API yet):

**NEW (opens a new discussion):**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[N/Total] [CRITICAL] src/foo.ts:42
Send mode: new discussion
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Context (±3 lines, `>` marks the target line):
   39 |   const xs = input.map(x => x.id);
   40 |   if (!xs.length) return [];
   41 |
 > 42 |   return db.query(`SELECT * FROM t WHERE id IN (${xs.join(',')})`);
   43 | }
   44 |
   45 | export default handler;

Comment body (will be sent as body):
**[CRITICAL]** 直接拼 SQL 字符串会导致注入，改用参数化查询…

position fields:
  new_path = src/foo.ts
  new_line = 42
  (or old_path/old_line for a pure deletion line)

Send? [y = send / n = skip / e = edit body]
```

**REPLY (replies to an existing discussion):**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[N/Total] [WARNING] src/bar.ts:77
Send mode: reply to discussion #a1b2c3d4
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Existing discussion (full thread):
  @alice (2026-05-08): 这里 null 检查不足，应该…
  @bob   (2026-05-09): 同意，另外 …

Context (±3 lines, `>` marks the target line):
   74 |   if (user) {
   75 |     return user.name;
   76 |   }
 > 77 |   return fetchName(id, { timeout: 0 });
   78 | }

Reply body (will be sent as body, no position field):
**[WARNING]** 针对上面关于 null 检查的讨论，补充一点：timeout: 0 会导致…

Send? [y = send / n = skip / e = edit body]
```

**Source for the context snippet**: if a full file was already fetched in Step 6, slice from memory; otherwise fetch `files/FILE?ref=$HEAD_SHA` again and slice `new_line ± 3` lines.

### 8.2 After approval, build and send the request

Once the user replies `y`, choose the command below based on `action`. After sending, report GitLab's returned `discussion id` / `note id` or error to the user, then move to item N+1.

- 422 → tell the user the line is not in the diff, mark as "skipped", do not auto-retry.
- Non-2xx → show the error, let the user decide retry vs. skip.

#### 8.2.a NEW — open a new discussion (with position)

**bash (macOS / Linux):**

```bash
# Addition / context line → use new_line
curl -sfk -X POST \
  -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  -H "Content-Type: application/json" \
  "$GITLAB_HOST/api/v4/projects/$PROJECT_PATH_ENCODED/merge_requests/$MR_IID/discussions" \
  -d '{
    "body": "**[severity]** issue description",
    "position": {
      "base_sha":      "'"$BASE_SHA"'",
      "start_sha":     "'"$START_SHA"'",
      "head_sha":      "'"$HEAD_SHA"'",
      "position_type": "text",
      "new_path":      "path/to/file.ts",
      "new_line":      42
    }
  }'

# Pure deletion line → use old_line
curl -sfk -X POST \
  -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  -H "Content-Type: application/json" \
  "$GITLAB_HOST/api/v4/projects/$PROJECT_PATH_ENCODED/merge_requests/$MR_IID/discussions" \
  -d '{
    "body": "**[severity]** issue description",
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

**PowerShell (Windows):**

```powershell
# Addition / context line → use new_line
$body = @{
  body = "**[severity]** issue description"
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

# Pure deletion line → swap new_line/new_path for old_line/old_path
```

> PowerShell notes: use `ConvertTo-Json` to build the body (avoids quote-escaping pitfalls); substitute the real SHA values; `Invoke-RestMethod` parses the response JSON automatically.

#### 8.2.b REPLY — reply to an existing discussion (no position)

**bash (macOS / Linux):**

```bash
# Replace DISCUSSION_ID with the reply_to value recorded in Step 7.1
curl -sfk -X POST \
  -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  -H "Content-Type: application/json" \
  "$GITLAB_HOST/api/v4/projects/$PROJECT_PATH_ENCODED/merge_requests/$MR_IID/discussions/DISCUSSION_ID/notes" \
  -d '{
    "body": "**[severity]** reply text"
  }'
```

**PowerShell (Windows):**

```powershell
$body = @{
  body = "**[severity]** reply text"
} | ConvertTo-Json -Depth 3

Invoke-RestMethod -Method Post `
  -Uri "$GITLAB_HOST/api/v4/projects/$PROJECT_PATH_ENCODED/merge_requests/$MR_IID/discussions/DISCUSSION_ID/notes" `
  -Headers @{"PRIVATE-TOKEN" = $env:GITLAB_TOKEN} `
  -ContentType "application/json" `
  -SkipCertificateCheck `
  -Body $body
```

**Strictly forbidden**:
- Sending all comments in bulk without per-item approval (even though Step 7.5 summarized them — that was a coarse pass; Step 8 must re-confirm each one).
- Skipping the preview and jumping straight to `curl -X POST`.
- Sending any request for `SKIP_DUPLICATE` / `SKIP_SUPERSEDED` items.

---

## Troubleshooting

| Error                         | Fix                                                                                                   |
| ----------------------------- | ----------------------------------------------------------------------------------------------------- |
| 401                           | Token invalid or missing the `api` scope.                                                             |
| 404 (NEW)                     | Project path wrong — check `%2F` encoding.                                                            |
| 404 (REPLY)                   | Wrong `DISCUSSION_ID` or the discussion was deleted. Downgrade to NEW (resend with position) or skip. |
| 400 / 403 (REPLY)             | Target discussion is already resolved or the instance disallows appending to it. Downgrade to NEW or skip — do NOT force an unresolve. |
| 422                           | Line number is not in the diff — skip.                                                                |
| Exit code 49 (Windows bash)   | IPv6 binding or proxy conflict. Add `--ipv4` to curl; if it still fails, add `--noproxy '*'`.         |
