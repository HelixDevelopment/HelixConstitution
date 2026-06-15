# Resolved ClickUp IDs — clickup_sync target

| Field | Value |
|---|---|
| Revision | 1 |
| Last modified | 2026-06-09T00:00:00Z |
| Secret? | NO — these IDs are not credentials and may be committed (§ task brief). The `pk_…` API key is the only secret and is NOT recorded here. |

## Source URLs (operator-provided, from `.env`)

```
CLICKUP_FOLDER = https://app.clickup.com/90182716341/v/f/901814301358/901811154372
CLICKUP_BOARD  = https://app.clickup.com/90182716341/v/b/5-901814301358-2
```

URL grammar: `app.clickup.com/<workspaceId>/v/<viewType>/<id1>/<id2>`
- `v/f/...` = **folder view**; `v/b/...` = **board view**.
- In `v/f/<A>/<B>`, **A = folder id, B = the space the folder lives in** (NOT a list — see proof).
- In `v/b/5-<A>-2`, the embedded `<A>` = the same folder id; `5-…-2` is the board-view slug.

## Confirmed IDs (read-only GET probes, 2026-06-09)

| Entity | ID | Name | Proof (HTTP) |
|---|---|---|---|
| **Workspace / Team** | `90182716341` | **FinTech Labs** | `GET /api/v2/team` → 200, team present |
| **Space** | `901811154372` | **ATMOSphere OS** | embedded in `GET /folder/901814301358` → `space.id`; `GET /space/901811154372` → 200 |
| **Folder** | `901814301358` | **ATMOSphere System** | `GET /api/v2/folder/901814301358` → **200** |
| **List (sync target)** | `901818394542` | **List** | embedded in folder JSON; `GET /api/v2/list/901818394542` → **200** |
| **Board view** | slug `5-901814301358-2` | (board view of folder/list) | view of the folder's tasks, columns = List statuses |

### Disambiguation proof (why B is the Space, not a List)
- `GET /folder/901814301358` → **200**, JSON `name="ATMOSphere System"`, embedded `space = { id: 901811154372, name: "ATMOSphere OS" }`, and `lists = [ { id: 901818394542, name: "List", task_count: 0 } ]`.
- `GET /list/901811154372` → **HTTP 401** `{"err":"Team(s) not authorized","ECODE":"OAUTH_023"}` — i.e. `901811154372` is **not a list** the key can read as a list (it is a Space id; the list endpoint rejects a space id with an auth-style error, not 404). Confirmed it IS the space via `GET /space/901811154372` → 200.
- `GET /list/901818394542` → **200** — the real list.

> NOTE on the 401: ClickUp returns `OAUTH_023 Team(s) not authorized` when the id resolves to an
> object of the wrong type / outside the token's authorized scope, rather than a clean 404. Do NOT
> interpret this single 401 as "key invalid" — the same key returned 200 on the folder, list, space,
> team, fields and tags calls in the same run.

## Workspace members (id → name, for assignee/creator resolution — §11.4.104 attribution)

`GET /api/v2/team` → team `90182716341` "FinTech Labs", `multiple_assignees=True`.

| user id | username | email | role |
|---|---|---|---|
| 113552839 | IVAN BIYAK | ivan.biyak@fmd-mir.com | 3 |
| 113552821 | *(null)* | vadim.safronov@fmd-mir.com | 3 |
| 113548797 | Владимир Радостовец | 7555694@gmail.com | 3 |
| 113543571 | Андрей Шабатура | a.shabatura@fmd-mir.com | 3 |
| 113543565 | Денис Хрисанов | d.khrisanov@fmd-mir.com | 3 |
| 113543561 | Александр Подоревский | a.podorevskiy@fmd-mir.com | 3 |
| 113543555 | Еламан Болысханұлы | e.bolyskhan@fmd-mir.com | 3 |
| 113543508 | Дмитрий Лазарев | d.lazarev@fmd-mir.com | 3 |
| 113541731 | m.vasic@fmd-mir.com | m.vasic@fmd-mir.com | 3 |
| 296697381 | Жанар | z.begimbetova@fintechpro.dev | 3 |
| 302413976 | Daulet Bekishev | dauletbekishev@gmail.com | 1 |

- `role`: observed values 1 and 3. `UNCONFIRMED:` exact numeric→name map (general ClickUp convention: 1=owner, 2=admin, 3=member, 4=guest). 302413976 (role 1) = workspace owner.
- `m.vasic@fmd-mir.com` (id 113541731) is the operator's likely member identity (matches the project operator) — relevant to §11.4.104 "never tag the operator" rule. `UNCONFIRMED:` until operator confirms which member is them.
