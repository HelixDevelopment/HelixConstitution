# `scripts/post_update_hook.sh`

**Revision:** 1
**Last modified:** 2026-07-15T03:20:00Z
**Authority:** §11.4.164 (post-update auto-propagation) · §11.4.140 (action directives) · §11.4.28 / §11.4.80 (inherit by reference)

## Overview

The §11.4.164 auto-propagation seam. After a `git pull` / `git submodule update`
brings new constitution content into a consuming project, this script detects
what changed and installs it — skills, MCP configs, git hooks, and (new) the
CLI-agent **action directives**: the Claude Code `helix` plugin, the per-agent
slash commands, and the Agent Skills.

It is what makes "a new directive is live out of the box" true rather than
aspirational.

## Prerequisites

- The constitution submodule is checked out inside the project.
- `git` (to diff the update), `bash` 4.4+.
- Optional: `jq` (MCP config merge), `claude` CLI (plugin install — its absence
  is reported honestly, never faked).

## Usage

```bash
# From the consuming project root — the normal invocation:
bash constitution/scripts/post_update_hook.sh

# Explicit paths (CI, or a non-standard layout):
CONST_DIR=/path/to/constitution PROJECT_ROOT=/path/to/project \
  bash constitution/scripts/post_update_hook.sh
```

It is also invoked automatically by `scripts/hooks/post-merge`.

## Internal behaviour

1. **Detect** — diffs `ORIG_HEAD..HEAD` (falls back to `HEAD~1`) inside the
   constitution and classifies each changed path into: `skills/*`, `mcp/*.json`,
   `scripts/hooks/*`, `actions/*` · `plugins/*` · `.claude-plugin/*`, `scripts/*.sh`.
2. **Install skills** — symlinks each changed skill into the project.
3. **Merge MCP configs** — `jq`-merges into `<project>/.mcp.json`.
4. **Install git hooks** — copies into `<project>/.git/hooks/`.
5. **STEP 4b — wire action directives** — when anything under `actions/`,
   `plugins/`, `.claude-plugin/`, or `skills/` changed, runs
   `scripts/install_cli_agent_plugins.sh`, which regenerates every agent's slash
   commands from the registry, links the skills into `.claude/skills/`, wires the
   `UserPromptSubmit` prefix hook, and installs the `helix` plugin.
6. **Validate** — `chmod +x` + `bash -n` every touched script.
7. **Report** — a summary, plus a non-zero exit if any error was collected.

Idempotent: safe to re-run.

## Edge cases

- **Not the constitution root** → the script **aborts loudly** (it checks for
  `Constitution.md` + `scripts/`). It will never silently propagate nothing.
- **`ORIG_HEAD` unset** → falls back to `HEAD~1` and warns; deeper changes may be
  missed.
- **A real directory already sits where a skill symlink would go** → left
  **untouched** with a warning. The script never deletes a directory it did not
  create (§9.2 / §11.4.122).
- **`claude` CLI absent** → the plugin is not installed; the exact one-time
  commands are printed. Every other agent is still wired.
- **`jq` absent** → MCP configs are not merged; a warning names the file to merge
  by hand.

## Two defects fixed on 2026-07-15 (both silently disabled this seam)

1. **Pipeline subshell.** `detect_changes()` fed its classification loop with
   `echo "$x" | while read ...`, so every `ARR+=(...)` ran in a **subshell** and
   was discarded. The caller always saw empty arrays → *"No relevant changes
   detected"* → **nothing was ever installed**. Fixed with process substitution
   (`done < <(printf '%s\n' "$changed_files")`).
2. **`CONST_DIR` off-by-one.** The default was `$SCRIPT_DIR/../..`, which resolves
   to the **parent project root**, not the constitution. `git diff` therefore ran
   against the parent repo, whose paths look like `constitution/skills/…` and match
   **none** of the classifiers → again, silent no-op. Because
   `scripts/hooks/post-merge` never exports `CONST_DIR`, **every real pull hit
   this.** Fixed to `$SCRIPT_DIR/..`, plus a fail-closed assertion.

Both are permanently guarded by `tests/test_cli_agent_plugins.sh` (cases `C5b`,
`C5c`, `C5e`, `C5f`).

## Related

- `scripts/install_cli_agent_plugins.sh` — the installer this seam calls
  ([guide](install_cli_agent_plugins.md))
- `scripts/generate_agent_prefix_commands.sh` — the command generator
  ([guide](generate_agent_prefix_commands.md))
- `scripts/hooks/post-merge` — the git hook that invokes this script
- `docs/actions/ADMIN_MANUAL.md` — the operator-facing wiring manual

**Last verified:** 2026-07-15 (16/16 hermetic cases green; gate
`CM-CLI-AGENT-PLUGINS-WIRED` 9/9).
