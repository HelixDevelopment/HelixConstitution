# Golden-BAD dedup — exempt_statuses ON, but BOTH duplicates are LIVE (MUST FAIL DEDUP-02)

Neither row carries an exempt status: this is a genuine, unresolved duplicate
of one feature across two live records. The exemption MUST NOT suppress it.

| № | Ticket | Task | Scope | Status |
|---|--------|------|-------|--------|
| 9.1 | WIT-911 | roster gate blind verdict is unreachable dead code | roster-gate | Queued |
| 9.2 | WIT-912 | roster gate blind verdict is unreachable dead code | roster-gate | In progress |
