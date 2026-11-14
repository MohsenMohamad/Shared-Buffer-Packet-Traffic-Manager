# P05 production memory/TX: RTL-author results

The production payload RAM, metadata wrapper and TX engine pass the designer
checks below. This report establishes RTL-author component evidence only.
Independent P05 candidate qualification, FP-TX and hardware acceptance remain
NOT_RUN. Independent DV implementation, reports, patches, source hashes and
source-bearing raw output were not manually inspected. Standard commands may
process/hash DV internally under the clarified task authorization.

## Tested candidate and boundary

Candidate `fa91a3fe3e675a1b42dd684359758acfbcdb0b94` on
`feat/p05-memory-tx`, based on current-main
`f54fedebd1cfa94d44fee1c759bc9d5e7aa44b52`. Final checks ran with clean
production/designer source state. Later report-only commits do not change the
tested RTL. [Draft PR #24](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/pull/24)
is the implementation review and qualification handoff.

The existing public port declarations were moved into
`rtl/memory/tm_packet_ram.sv`, `rtl/memory/tm_metadata.sv` and
`rtl/tx/tm_tx.sv` without changing their signatures. Production membership is
registered in `verification/sources/production.json`; designer membership is
separate in `dv/designer/p05_sources.json`. See the
[control/port decision](../decisions/p05-memory-tx.md) for exact credit equations,
array ports, retirement rules and reset assumptions.

Native tools were Verilator 5.054 (2026-11-01, installed build
`vUNKNOWN-built20261112`) and Yosys 0.70+post with the installed Slang frontend.
Exact version strings, profile parameters, commands, observed counts and local
artifact paths are retained in [the compact record](P05-memory-tx-rtl.json).
The designer runner collected no independent source provenance/digests.
Subsequently, the authorized standard `make doctor` passed on
`6982a5e7837e5723f4a0698cff140da239cb30e6` using the prepared installation.
No toolchain installation, rebuild, lock/stamp edit or bypass was performed.

## Executed results

| Check | Result | Scope and observations |
| --- | --- | --- |
| Designer simulation | PASS, 36 runs | F0/F1/I0/I1/E0/E1 × TX depths 4/8 × seeds 17/19/23; 3,324 completed packets plus six reset-abandoned packets per run. |
| Payload response | PASS | Public request/write observations check exact latency 1/2 and data; no response-ready channel exists. |
| Credit, data and retirement | PASS | Embedded assertions plus public-port smoke check full stalls, simultaneous issue/response/retire, bytes/keep/last/user, fragmented chains, returns and reuse. Each run observed at least 180 triple events and 14 full-pressure cycles. |
| Reset | PASS | Dispatch, pending reads, full FIFO, partial cell, cell-final and packet-final holds; same IDs/tag reused with distinctive bytes after reset. Tags/counts flush without clearing payload/link/info arrays. |
| First-valid and streaming | PASS, designer scope | First valid sampled 3 cycles after dispatch at latency 1 and 4 at latency 2, within L+4. Always-ready cases require continuous valid after the first transfer across cell boundaries. |
| Verilator RTL lint | PASS, 60 module checks | RAM, metadata, TX, existing queue and scheduler APIs in all six profiles and both depths. No warning suppressions; final native stderr logs were empty. |
| Slang lowering/synthesis | PASS, 12 module checks | RAM/metadata/TX in I0/I1, depths 4/8; `synth -noabc`, `check -assert`, and structural confirmation of 64-bit 1R1W payload memory at full configured capacity. No timing, Liberty area or physical banking claim. |
| Scoped whitespace review | PASS | Permitted implementation/designer/report paths only; original failure snapshots are retained byte-for-byte in archives. |
| `make doctor` | PASS, exit 0 | Prepared environment; executed on `6982a5e7837e5723f4a0698cff140da239cb30e6`. No mismatch or toolchain changes. |
| `python3 tools/check_repository.py` | PASS, exit 0 | Standard repository contract check on the same revision; no hardware acceptance. |
| `python3 tools/check_light.py` | FAIL, exit 1 | 109 unit tests reported one error: `test_memory_tx_preparation.PreparationBoundaryTests.test_public_response_has_no_backpressure`, `IndexError`. Independent test/traceback not inspected; unresolved P05-DV triage. |

The three standard checks ran on the report-only successor
`6982a5e7837e5723f4a0698cff140da239cb30e6`, with unchanged production and
designer sources relative to the tested RTL candidate. The subsequent report
and failure-capture commit is documentation/evidence only. Standard-check
execution times and exact commands are in the compact JSON record.

The smoke uses the actual RAM, metadata and TX with public ports. Dispatch and
payload writes are designer stimulus; it does not integrate RX, scheduler,
pools or top-level ownership. The affected queue/scheduler checks above are
lint, not reruns of independent functional suites. No formal proof, independent
coverage closure or subsystem throughput acceptance is claimed.

Lengths sweep 1 through `2*CELL_BYTES+8`, all eight final keeps near maximum
packet length, and the maximum-length stalled case. Always-ready cases overwrite
returned nonfinal cells/links on the following edge. Reset cases hold low across
two rising edges and restart the same descriptor/tag/cells. Existing RAM pipeline
responses remain unbackpressured; TX discards responses without live tags.

## Reproduction

Use the existing prepared installation. No setup/install command was run.
From the repository root:

```sh
source .tools/activate.sh
make doctor
python3 tools/check_repository.py
python3 tools/check_light.py
# check_light currently exits 1; the designer matrix below is separate.
for profile in F0 F1 I0 I1 E0 E1; do
  for depth in 4 8; do
    python3 dv/designer/run_p05.py --profile "$profile" --depth "$depth" --seed 17 --seed 19 --seed 23 || exit
    python3 dv/designer/run_p05.py --profile "$profile" --depth "$depth" --lint || exit
  done
done
for profile in I0 I1; do
  for depth in 4 8; do
    python3 dv/designer/run_p05.py --profile "$profile" --depth "$depth" --synth || exit
  done
done
```

Every runner invocation records native argv, profile, seeds, tool versions,
candidate revision, path-scoped dirty state and stdout/stderr under ignored
`work/p05/`. The committed compact record links the exact final artifacts.
Those artifacts can be regenerated by the commands above; no DV-source or
repository-wide test discovery is used.

## Preserved failures

The earlier two designer failures were captured before repair with commands,
profile, seed, native output and permitted source snapshots. Neither is claimed
as a functional hardware-bug discovery. The later standard light-check error
was also preserved before triage; no repair was attempted.

- [Compile capture](../../verification/failures/p05-designer-20261113T223902499406Z/capture.json): `cell` was a reserved SV keyword in the new tag records. Renamed it `cell_id`; compilation and subsequent smoke pass. The capture labels the build failure `tool-environment` and retains the precise syntax diagnosis.
- [Designer-smoke capture](../../verification/failures/p05-designer-20261113T223909642253Z/capture.json): the smoke counted current issue before current retirement, falsely reporting excess credit. Classified `verification-defect`; corrected the RTL-owned smoke to evaluate the merged edge. Production credit arithmetic was unchanged.

An initial whitespace review flagged an unchanged trailing blank line in the
archived P04 source snapshot. The original bytes remain in `source.tar.gz`;
archiving the snapshot avoids presenting unchanged historical RTL as new source.
No production code was changed for that archival warning.

## Standard light-check failure

[Failure capture](../../verification/failures/p05-standard-light-20261114T042319106270Z/capture.json)
records the exact candidate, prepared environment, command, exit status and
source-free summary. Raw stdout/stderr are retained in an opaque archive and
were not opened for test source, checker expressions or traceback inspection.
The sanitized summary contains only test identity, test totals and error class.

The check reported 109 tests and one `IndexError` in
`test_memory_tx_preparation.PreparationBoundaryTests.test_public_response_has_no_backpressure`.
Review of production declarations confirms RAM/TX response ports still have no
response-ready signal. The available symptom supplies no public stimulus,
observed interface failure or violated RTL contract. It does not justify a
speculative RTL change or a test expectation change. Disposition is unresolved;
P05-DV must triage the independent preparation test and provide a contract-level
failure if production RTL is implicated. Independent DV and shared check tooling
remain unchanged.

## Independent qualification handoff

The public [P05 task card](../implementation/tasks/P05-memory-tx.md) on the
fetched main still records preparation independence as unresolved. Its linked
DV implementation report was not opened. The published automation/module
contracts provide no candidate-RTL memory/TX qualification command or guarantee
that its output is limited to contract-level symptoms. No candidate command was
available to repeat; no oracle self-test was substituted.

The earlier restriction on standard commands' internal DV processing/hashing
was explicitly clarified. Doctor and repository checks now pass; the light
check executes and fails as recorded above, rather than remaining blocked.
Its failure belongs to the independent preparation test's triage until a
contract-level RTL defect is supplied. No independent functional memory/TX
regression or FP-TX proof was run, and no independent qualification is claimed.

P05-DV must triage the light-check error, publish a candidate-RTL command with
source-free result output, and qualify the final `feat/p05-memory-tx` head
recorded in PR #24 against its frozen expectations. Its production/designer
sources remain identical to tested RTL revision
`fa91a3fe3e675a1b42dd684359758acfbcdb0b94`. Return command, candidate revision, configuration, seed, public
stimulus, observed/expected interface behavior and contract violation only.
Public APIs retain exact response timing and no response backpressure. Credit
includes buffered plus outstanding beats and current external retirement;
responses never free credits. Cells retire only on cell-final external
handshakes, descriptors only through final `tx_done`, and reset cancels all
live tags. Independent expectations, detectors and registrations were not
modified. This PR remains draft pending that qualification and integration review.
