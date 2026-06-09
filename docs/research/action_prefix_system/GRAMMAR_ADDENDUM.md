# Grammar Addendum — slash form + namespace prefix (operator mandate, 2026-06-09)

EXTENDS the §11.4.140 action-prefix design with two equivalences. Every registered action (e.g. BACKGROUND) MUST be invocable in ALL of these EQUIVALENT forms — same action, same expansion, same execution:

| # | Form | Example | Notes |
|---|---|---|---|
| 1 | `ACTION_NAME :: <rest>` | `BACKGROUND :: Do X` | bare `::` form (no namespace) |
| 2 | `PREFIX::ACTION_NAME :: <rest>` | `DEFAULT::BACKGROUND :: Do X` | namespaced `::` form |
| 3 | `/ACTION_NAME <rest>` | `/BACKGROUND Do X` | bare slash form — ONLY if `/ACTION_NAME` does NOT collide with an existing/built-in slash command of the host agent |
| 4 | `/PREFIX::ACTION_NAME <rest>` | `/DEFAULT::BACKGROUND Do X` | namespaced slash form — disambiguates from any existing `/ACTION_NAME`; ALWAYS safe |

## Namespace prefix
- `PREFIX` is an action NAMESPACE. The reserved default namespace is **`DEFAULT`**. Custom namespaces are permitted (e.g. a project/plugin namespace) so the same action can run under the default OR a custom prefix.
- An action is executable WITH or WITHOUT the prefix: `BACKGROUND ::` ≡ `DEFAULT::BACKGROUND ::` ≡ `/BACKGROUND` ≡ `/DEFAULT::BACKGROUND`.
- Namespace separator inside the token is `::` (no surrounding spaces): `PREFIX::ACTION_NAME`. This is DISTINCT from the action-body separator ` :: ` (spaces both sides) used in forms 1/2 between the token and `<rest>`.

## Grammar (extended, anchored to first non-blank line)
- `::`-form regex: `^(?:([A-Z][A-Z0-9_]*)::)?([A-Z][A-Z0-9_]*) :: (.*)$` → group1=optional PREFIX, group2=ACTION_NAME, group3=rest.
- slash-form regex: `^/(?:([A-Z][A-Z0-9_]*)::)?([A-Z][A-Z0-9_]*)\s+(.*)$` → group1=optional PREFIX, group2=ACTION_NAME, group3=rest.
- Token case: ACTION_NAME and PREFIX are UPPERCASE `[A-Z][A-Z0-9_]*` (directive/macro convention — DISTINCT from the §11.4.29 lowercase file/dir naming, which still governs the registry FILE names + script names). `DEFAULT` is the reserved default-namespace literal.
- Escape: leading `\` makes the line literal (no expansion): `\BACKGROUND :: x` and `\/BACKGROUND x`.
- Unknown grammar-shaped token (looks like an action but not in the registry) → ask per §11.4.66/§11.4.105, NEVER silently expand/drop (§11.4.6).

## Conflict rule (slash form)
- `/ACTION_NAME` (form 3) is honored as the action ONLY when `ACTION_NAME` (case-folded for the collision check) does not match a built-in/host slash command. The registry MAY carry a per-action `slash_bare: true|false|auto` and a `slash_conflicts: [..]` list; `auto` = enable bare slash unless a known host command collides.
- Form 4 (`/PREFIX::ACTION_NAME`) is ALWAYS unambiguous and always honored.

## Registry schema additions
```yaml
grammar:
  default_namespace: DEFAULT
  namespace_separator: '::'        # inside the token, no spaces
  body_separator: ' :: '           # token <-> rest, spaces both sides ('::' form)
  slash_prefix: '/'
  slash_body_separator: ' '        # token <-> rest (slash form)
actions:
  - name: BACKGROUND
    namespaces: [DEFAULT]           # which namespaces this action is registered under
    slash_bare: auto                # bare /BACKGROUND honored unless host-command collision
    slash_conflicts: []             # known colliding host slash commands (forces /DEFAULT::BACKGROUND)
    # ... expansion, rules, composes_with as before
```

## Impl impact
- `apx_parse_prefix` MUST recognize all 4 forms, returning (namespace|DEFAULT, action, rest, matched_form).
- `apx_expand_prompt` resolves namespace+action against the registry; bare-slash honored per the conflict rule.
- LAYER-2 hook handles all 4 first-line forms.
- The slash-command generator already emits `/background` (form 3) per agent; ADD the namespaced `/default::background` (form 4) where the agent's command syntax allows `::` (else a `default-background` alias) + document the collision fallback.
- recognition_instruction.md teaches the agent all 4 forms + the conflict rule + escape.

Naming: action/namespace tokens UPPERCASE; FILES/DIRS lowercase snake_case (§11.4.29). DEFAULT is the reserved default namespace literal.
