# golden_false_nonhook_decoys — the gate MUST NOT FIRE, in either direction

Every declared hook is installed, executable and byte-identical. Around them sit
the decoys measured on the real source roots — of 19 entries there, only 5 are
git hooks:

  source side : `lib/` and `fixtures/` directories, `test_pre_commit_credscan.sh`,
                `guard-forbidden-commands.sh`, `credential_scan_lib.sh`,
                `action_prefix_expand.sh`
  live side   : the `lib/` DIRECTORY the installer copies beside the hooks

A gate that reads either root wholesale emits 14 false refusals; a gate without
the live-side canonical filter reports `lib/` as an undeclared live hook. Both are
FAIL-bluffs of the same severity as a false pass (§11.4.201(1)).

Expected: exit 0, silent on every decoy.
