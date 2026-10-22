# Backends: setup and failure modes

All facts below were measured on macOS between 2026-10-21 and 2026-10-22, with
agy 1.4.4, codex-cli 0.152.0 and Claude Code 2.1.308.

## agy (Antigravity CLI, Gemini 4 Argon)

**Sign-in.** `agy models` can succeed on an account that cannot run a turn.
Print mode also calls `loadCodeAssist`, which answers `403 VALIDATION_REQUIRED`
until Google verifies the account (`support.google.com/accounts?p=al_alert`).
The fix is the "Verify your account" link in the error. Finish it in the browser
as the account agy uses: the link ends in a bare `&authuser`, so Google picks the
browser's default account.

**The allow-list.** Headless mode cannot prompt, so it denies every command that
`~/.gemini/antigravity-cli/settings.json` does not allow. After a denial, agy
ends the turn with an empty response, status `SUCCESS` and exit 0. The tool
prompts agy to use its own file tools, but keep a read-only list as well:

```json
"permissions": {"allow": [
  "command(git grep)", "command(git log)", "command(git show)", "command(git diff)",
  "command(git blame)", "command(git ls-files)", "command(git status)",
  "command(git rev-parse)", "command(git merge-base)", "command(ls)", "command(cat)",
  "command(head)", "command(tail)", "command(wc)", "command(grep)", "command(rg)",
  "command(nl)", "command(tree)", "command(jq)"]}
```

- Rules are literal prefixes. `command(grep)` does not cover `/usr/bin/grep`,
  and that exact miss cost one review.
- The list applies to interactive agy too, and there it runs without
  `--sandbox`. Leave out commands that can write: `sed -i`, `find -delete`,
  `awk` with `system()`.
- No per-run grant exists. `ANTIGRAVITY_PERM_GRANTS` had no effect in either
  format tried.

**`--sandbox`.** It blocks writes, including in the workspace (`touch`: Operation
not permitted), and it blocks the network (`curl`: Could not resolve host). The
tool always passes it.

**Quota.** `agy -p /usage` costs 0 tokens. It reports separate buckets: Gemini
5-hour and weekly windows, "Claude and GPT models", and a Gemini 4 Argon weekly
limit. Only the Argon weekly limit moved: 10 to 11 points per large review, 4 to
8 per failed run. The Gemini 5-hour window never moved.

**Speed.** 491 to 671 seconds per review, 3.7 to 5 times slower than codex on
the same PR.

## codex

- **Identity.** An npm package also named `codex` can shadow the real CLI and
  exit 0 with nothing. The tool requires `codex --version` to start with
  `codex-cli`.
- **stdin.** With a prompt argument and an open stdin, `codex exec` prints
  "Reading additional input from stdin..." and waits forever. The tool sends the
  prompt on stdin through `-`.
- **Credits.** A depleted workspace shows as `rate_limit_reached_type:
  workspace_member_credits_depleted` in `~/.codex/sessions/**/rollout-*.jsonl`.
  Three reviews used 88 points of a 5-hour window, about 3 reviews per window.

## claude

- A nested `claude -p` works inside a Claude Code session. It reads the prompt
  from stdin.
- `--allowedTools Read,Grep,Glob` with Edit, Write, NotebookEdit and Bash
  disallowed leaves it unable to write. A probe confirmed this.
- This CLI version prints an array of events, and the last element holds
  `result`, `is_error`, `total_cost_usd` and `usage`.
- It loads your CLAUDE.md and skills, so even a one-line prompt cost $0.47 on
  claude-opus-5-5. `CLAUDE_MODEL` selects another model.
