# golden_true_missing_declared — the gate MUST FIRE, naming exactly `post-merge`

All five canonical hooks exist in the source roots (`src_a/`, `src_b/`); the live
hook dir (`live_hooks/`) holds four. `post-merge` is the omission.

This is the fixture form of the §11.4.205 forensic: the superseded implementation
reported PASS on exactly this shape, because its declared set was the same literal
it installed from and so could not name a hook it did not itself list.

Expected: exit 1, output contains `MISSING post-merge`, and NOTHING else fires.
