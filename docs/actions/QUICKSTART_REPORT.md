# Quick Start — How do I report a bug, an issue, or a task?

**Revision:** 1
**Last modified:** 2026-07-14T21:50:00Z
**Authority:** constitution §11.4.202 (reporting directives) + §11.4.140 (action-prefix grammar)
**Maintainer:** constitution submodule
**Scope:** the one-page version. Full detail: [USER_GUIDE.md](USER_GUIDE.md) · [REFERENCE.md](REFERENCE.md)

---

## The three commands

Type one of these as the **first line** of your prompt, then just describe the
problem in plain language:

```
BUG:   subtitles render one frame late on the secondary display
TASK:  bump the pandoc pin to 3.2 and regenerate the exports
ISSUE: playback stutters on 4K HDR after ~40 minutes — not sure if bug or feature gap
```

| Use | When |
|---|---|
| `BUG:` | Something is **broken** — a regression, a defect, wrong behaviour a user can see. |
| `TASK:` | Internal **workstream** — refactor, doc, infra, gate, audit, chore. |
| `ISSUE:` | **Anything trackable** when you have not decided which of the two it is. |

Equivalent forms, if you prefer them: `BUG :: …`, `BUG ---> …`,
`/helix:bug …`, `/default-bug …`. (Bare `/bug` is **Claude Code's own built-in** —
use `BUG:` or `/helix:bug` instead.) `/task …` and `/issue …` work directly.

## What makes a good report

You do not need a template — write it as you would to a colleague. Include what
you know; the agent records anything you did not say as an explicit `UNKNOWN:`
gap rather than inventing it.

- **What** happens, and what you expected instead.
- **Where** — which app / device / screen / build.
- **How to reproduce** it, if you know.
- **How you would know it is fixed** (the acceptance condition).

## What the system does with it

1. **Creates a real, tracked workable item** — never a prose "yes, I'll look into
   it". Status `Queued`, a stable auto-incremented ticket id, the correct Type
   (`Bug` / `Feature` / `Task` — there is no fourth type), and a structured
   description (what / scope / reproduction / acceptance).
2. **Regenerates every derived document** from the workable-items database —
   the open and closed trackers, their summaries, and their `.md` / `.html` /
   `.pdf` / `.docx` siblings. Nothing is left stale.
3. **Pushes it to every configured external tracker.**
4. For `ISSUE`, if your text does not make the type obvious, **it asks you first**
   rather than guessing.
5. For `BUG`, if the defect is actionable now, it then **investigates the root
   cause before proposing any fix**.

## What it reports back to you

- the **assigned ticket id**;
- the **sync verdict** (which documents were regenerated);
- **each tracker's verdict**, with the path to the captured evidence.

A tracker whose credentials or client are missing is reported as an honest
**SKIP with the reason** (naming only the unset variable, never a value). A push
is **never faked** and its absence is **never hidden** — if a tracker was skipped,
you will be told.

## The guarantee

A report that is only acknowledged is a lost requirement. Every report becomes a
real tracked item, or it is explicitly and honestly refused. Nothing evaporates.
