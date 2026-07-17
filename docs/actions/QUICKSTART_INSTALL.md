# Quick Start — How do I install this in a new project?

**Revision:** 2
**Last modified:** 2026-07-14T22:05:00Z
**Authority:** constitution §11.4.140 + §11.4.164 (post-update auto-propagation) + §11.4.75 (mechanical enforcement)
**Maintainer:** constitution submodule
**Scope:** the one-page version. Full detail: [ADMIN_MANUAL.md](ADMIN_MANUAL.md) · [REFERENCE.md](REFERENCE.md)

---

## Prerequisite

The constitution submodule is present in the project (typically at
`./constitution`). Nothing is ever copied out of it — everything is wired **by
reference**.

## The one command

From the **project root**:

```bash
bash constitution/scripts/install_cli_agent_plugins.sh
```

Real output:

```
[install-plugins] regenerated slash commands from registry (10 Claude Code command file(s))
[install-plugins] wired 10 gemini command(s) → .gemini/commands/
[install-plugins] wired 10 qwen command(s) → .qwen/commands/
[install-plugins] wired 10 codex command(s) → prompts/
[install-plugins] wired the UserPromptSubmit prefix hook (free-form 'NAME :: task' forms)
[install-plugins] linked 3 skill(s) into .claude/skills/ (4 legacy dir(s) without SKILL.md skipped)
[install-plugins] plugin 'helix@helix-constitution' is INSTALLED (verified via `claude plugin list`)
[install-plugins] done — action directives + skills are wired for this project
```

That is **everything**: the commands are regenerated from `actions/registry.yaml`
and symlinked into every agent's command directory, the free-form prompt hook is
wired, the three Agent Skills are linked, and the `helix` plugin is installed and
**verified** with `claude plugin list` (a tool's own success message is never
trusted). **Idempotent** — re-running is always safe, and the prompt hook is
registered exactly once no matter how often you run it.

## Verify

```bash
bash constitution/scripts/install_cli_agent_plugins.sh --check
```

Real output:

```
[install-plugins] constitution side: marketplace + plugin manifests present; 10 command(s); 3 skill(s)
[install-plugins] project side: 3 skill symlink(s) in .claude/skills/
[install-plugins] project side: UserPromptSubmit prefix hook is registered
[install-plugins] project side: plugin 'helix' is installed + enabled
[install-plugins] VERDICT: WIRED
```

(10 = 5 directives × 2 command files each; 3 = the three Agent Skills; the 4
skipped legacy dirs have no `SKILL.md` and are not part of this system.)

Then, in Claude Code, `/helix:` + Tab should list `background`, `reminder`, `bug`,
`task`, `issue`, and their `default-` aliases. Or simply type:

```
ISSUE: smoke-testing the directive wiring
```

## The one-time step you need only if the `claude` CLI is missing

The installer will **say so honestly** and not claim success. Run, from the
project root:

```bash
claude plugin marketplace add ./constitution
claude plugin install helix@helix-constitution
```

Everything else still completes — the commands are generated, the other agents'
command directories are wired, the prompt hook is registered, and the skills are
linked. Gemini CLI, Qwen Code and Codex CLI do not need the `claude` CLI at all.
With the CLI absent, `--check` honestly reports the plugin state as **UNKNOWN**
rather than claiming either way.

## After installation

On every subsequent constitution pull, run:

```bash
bash constitution/scripts/post_update_hook.sh
```

If a directive was added upstream, it is re-wired into your project
automatically — no manual step.
