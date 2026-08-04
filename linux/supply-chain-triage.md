# Supply-chain triage — a repeatable recipe

For the question "a compromised npm package was just announced; am I affected?"
Written after the keyv/cacheable worm of **2026-08-04**, which is used throughout
as the worked example because its specifics broke several comfortable assumptions.

The ordering below is the whole point. Most triage advice starts with caches,
which is where the evidence is thinnest. **Lead with lockfiles and install
surface**; caches are a footnote.

## The worked example, and why it is instructive

A worm published across the keyv/cacheable family planted a `preinstall` hook
that fetched a Bun runtime, harvested credentials from the environment, and — the
part that makes it our problem specifically — **planted Claude Code hooks as its
persistence mechanism**. AI-agent configuration is now a first-class target, not
an exotic one.

Three findings worth carrying forward:

- **Provenance did not help.** The poisoned releases carried valid GitHub Actions
  provenance attestations. Provenance proves *where a build ran*, not that its
  inputs were trustworthy. Do not treat a green attestation as triage.
- **A release-age cooldown would have.** The malicious versions were minutes old
  when they began propagating. A 7-day floor blocks the entire window in which
  such a package is both published and undetected.
- **`ignore-scripts` would have, independently.** The payload needed `preinstall`
  to run. Two unrelated controls each stopping the same attack is the property you
  want, because either one can silently regress.

The devbox was clean on all counts: lockfiles pinned keyv 4.5.4 against an
affected 6.0.0, no `node_modules` anywhere under `~/src`, no pnpm store, and no
hooks in `~/.claude/settings.json` or any of the five repo-level
`.claude/settings.local.json` files.

## Step 1 — Lockfiles and install surface

Start here. A lockfile is a durable, greppable record of what *would* be
installed; a cache is an accident of what happened to be fetched.

```bash
# Which versions are actually pinned, across every lockfile in the tree?
rg -n '"(keyv|cacheable|<pkg>)"' --glob '*lock*' --glob 'package.json' ~/src

# pnpm and npm phrase this differently; check both rather than assuming one.
rg -n '^\s+/<pkg>@' ~/src/**/pnpm-lock.yaml
```

Then establish whether the packages were ever *materialised*. An affected version
in a lockfile that was never installed is a much smaller problem than a clean
lockfile beside a populated `node_modules`.

```bash
fd -td -HI '^node_modules$' ~/src | head          # nothing = nothing ever ran
pnpm store path 2>/dev/null || echo "no pnpm store"
```

Record the *absence* explicitly. "No `node_modules` under `~/src`" is a finding,
and the reason the devbox's caches looked clean was simply that nothing is ever
installed there — worth stating so the next reader does not mistake luck for a
control.

## Step 2 — Install-time execution controls

Confirm the defences are on **now**, not that they were configured once. Both of
these are load-bearing and both live in surprising places on this box.

```bash
npm config get ignore-scripts             # want: true
npm config get min-release-age            # npm >= 11.10 only
grep -i 'minimumReleaseAge' ~/.config/pnpm/config.yaml
```

The split is deliberate and subtle enough to be worth a comment: `~/.npmrc` is on
the agent's deny list, so the pnpm cooldown had to live in
`~/.config/pnpm/config.yaml` instead. That works, but it means "check the npmrc"
is the wrong instinct here. Verify it survives a pnpm major.

A cooldown that is merely *set* is not a cooldown that is *enforced*. Prove it
with an unsatisfiable floor and watch it fail loudly — `devbox-smoketest` already
does this, which is the right pattern.

## Step 3 — Agent persistence surfaces

New since 2026-08-04, and the reason this recipe exists as a document rather than
a one-liner. This campaign wrote its persistence into AI-agent configuration, so
these are now part of routine triage rather than a special case.

```bash
# Claude Code hooks — user level and every repo-local override.
python3 -c 'import json;print(json.load(open("'"$HOME"'/.claude/settings.json")).get("hooks","(none)"))'
fd -HI 'settings.local.json' ~/src -x sh -c 'echo "== $1"; grep -c hooks "$1" || true' _ {}

# Codex, and the classic surface everyone still forgets.
grep -rn 'hook\|exec' ~/.codex/config.toml 2>/dev/null
fd -HI -td '^hooks$' ~/src --exec sh -c 'ls -A "$1" | grep -v sample || true' _ {}
```

Git hooks belong in the same sweep. They predate this campaign by decades and are
still the cheapest persistence available to anything that can write to a repo.

## Step 4 — Caches, as a footnote

Only now, and mostly to close the loop rather than because it will find anything.

```bash
npm cache ls 2>/dev/null | rg '<pkg>' || echo "not in npm cache"
ls ~/.cache/pnpm 2>/dev/null || echo "no pnpm cache"
```

A cache hit without a lockfile hit means something fetched the package outside a
normal install — worth chasing. A cache miss proves very little, since caches are
routinely pruned.

## Step 5 — Write down what would have caught it

The step most often skipped, and the one that compounds. For each incident, name
the control that *did* block it and the control that *would have* if the first had
regressed. If the answer is "only one," that is the finding.

For 2026-08-04 the answer was two independent controls plus a lockfile that
predated the compromise — and, separately, one widely-recommended control
(provenance) that would have passed the malicious package through.

## Should this go in the Operations Runbook?

Raised in the previous session and left unanswered. **Yes, but as a pointer, not a
copy.** The runbook in `~/.claude/CLAUDE.md` is loaded into every session's
context; a five-step recipe with code blocks is a poor tenant there. A single line
pointing at this file gets the recall benefit without the context cost, and keeps
one copy to maintain rather than two that drift.
