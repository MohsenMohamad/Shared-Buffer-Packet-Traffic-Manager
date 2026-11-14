# P05 public RAM response interface repair

The static no-response-backpressure check now resolves the public RAM port header
in either the declaration-only main layout or PR #24's implemented-module layout.
It still requires `output ram_response_t response` and rejects `ready`. Header
reading stops at the closing port delimiter, before the implementation body.
Frozen expectations, preparation source lists and production RTL are unchanged.
This is CI integration evidence, not memory/TX hardware qualification.

## Sources and preserved failure

| Identity | Revision |
| --- | --- |
| Current main / repair base | `f54fedebd1cfa94d44fee1c759bc9d5e7aa44b52` |
| Named PR #24 candidate | `479b5c1ceee2eee8db58d863bd5de5e20305cc8c` |
| Tested repair commit | `52d87a92d6941ab520c5ec164b18b671a14e54b5` |
| Tested repair tree | `f756fce551b910b8e61fac30c1a11cef1663aab3` |
| Isolated candidate plus repair commit | `81b8bd74cdaeac6a2e099b59516f9c70f96d12ac` |
| Isolated candidate plus repair tree | `a7d0a68e5af2947158701e6cde8034f1ff0e5c49` |

Both test trees were clean. The isolated tree was constructed by cherry-picking
the tested repair onto the exact candidate, without conflicts or resolutions.
Candidate production sources are absent from the repair branch's diff to main.
Later evidence-only commits do not replace these tested source identities.

The [failure record](../../verification/failures/p05-public-response-layout.json)
retains the focused pre-repair command and complete diagnostics at the clean
candidate. It also links the original PR #24 capture and hashes its unchanged
raw-output archive. The original full light run had 109 tests and one
`IndexError`: splitting only `rtl/include/tm_module_ports.sv` cannot find the RAM
module after it moves to `rtl/memory/tm_packet_ram.sv`. This is a
`verification-defect`, before any response contract assertion executes.

The repair follows [the public RAM contract](../spec/module-contracts.md) and
[the fixed unbackpressured storage contract](../spec/buffer-management.md).
Expected behavior did not change. The historical preparation exposure records
and original failure capture remain intact on their existing revisions.

## Executed checks

| Check | Main layout | Isolated candidate layout | Boundary |
| --- | --- | --- | --- |
| `make doctor` | PASS, exit 0 on repair base | NOT_RUN | Prepared tools unchanged; candidate checks below are tool independent |
| `python3 tests/toolchain/test_memory_tx_preparation.py -v` | PASS, 12 tests | PASS, 12 tests | Includes no-ready rejection in both layouts, missing/unterminated header rejection and a body-read guard |
| `python3 tools/check_repository.py` | PASS, exit 0 | PASS, exit 0 | Repository contract only |
| `python3 tools/check_light.py` | PASS, 111 tests, exit 0 | PASS, 111 tests, exit 0 | Python/JSON/shell checks and units; no HDL execution |
| `PYTHONPATH=tools python3 -m unittest discover -s tests/runner -v` | PASS, 2 tests | PASS, 2 tests | Failure-capture isolation |

The original focused candidate test reproduced the intended integration failure
with exit 1 before repair. Added isolated negatives reject a response-ready port
by the intended assertion; they do not count crashes as detector qualification.
Preparation path/inheritance, non-success DUT placeholder, scoped identity and
external-output capture tests continue to pass. No candidate simulation, formal
proof, performance or DUT coverage is claimed by these checks.

Raw local stdout/stderr and per-command exit/source/tree records are in
`work/p05-response-repair/`. The doctor manifest is under
`.build/runs/doctor-2026-11-14T045357.600723+0000-509a6a1f/summary.json`.
These ignored artifacts can be regenerated from the immutable sources below.
Hosted CI is recorded on the repair PR; it must complete before integration.

## Reproduction

Run the main-layout checks at the tested repair revision. For the candidate
layout, use a separate disposable worktree:

```sh
git fetch origin 479b5c1ceee2eee8db58d863bd5de5e20305cc8c
git worktree add --detach ../p05-response-candidate 479b5c1ceee2eee8db58d863bd5de5e20305cc8c
git -C ../p05-response-candidate cherry-pick 52d87a92d6941ab520c5ec164b18b671a14e54b5
cd ../p05-response-candidate
python3 tests/toolchain/test_memory_tx_preparation.py -v
python3 tools/check_repository.py
python3 tools/check_light.py
PYTHONPATH=tools python3 -m unittest discover -s tests/runner -v
```

Before the cherry-pick, this command reproduces the preserved failure:

```sh
python3 tests/toolchain/test_memory_tx_preparation.py PreparationBoundaryTests.test_public_response_has_no_backpressure -v
```

Merge only the CI repair PR after its required checks pass. P05 independent
production qualification resumes only after the maintainer confirms that merge.
PR #24 remains draft pending actual candidate qualification; no black-box
production candidate command or candidate verdict exists yet.
