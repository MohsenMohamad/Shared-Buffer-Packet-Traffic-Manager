# P05 fresh independent DV preparation

The oracle and P07/UVM replay qualification pass at clean tested commit
`290760486b627701a0555c0b98a27e4332ec9957` in [PR #23](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/pull/23).
This is preparation evidence, not hardware acceptance. The PR remains draft
for maintainer review of the scope qualification below; there is no RTL handover.

**Independence breach:** early tooling read nine dependency RTL implementations
and 33 results files before the expected-model commit. The initial “11
implementation-file digests” description was inaccurate: that count also included
one top declaration and one guidance file. The formal-source policy parsed RTL
text; Markdown/JSON validators read results text. This was not merely metadata
formatting. See the [exact exposure inventory](P05-source-exposure.md) and its
per-file hashes/read mechanisms. No separate P05 implementation/results path is
evidenced by pathname in the reconstructed early read set; P05 public declarations
were read. P05 content in generically named results remains unknown, not cleared.
The scoped checks pass, but independence acceptance is **not established**.
Later tests do not cure the exposure. Keep the PR draft for independent review.

## Source and expectation identities

| Identity | Purpose |
| --- | --- |
| `8d66a92768f2c72236171731262563814e875352` | Initial current-main base, including PR #19 |
| `9aa13c5` | Bounded first workflow/card/status alignment commit |
| `db8bbec` | Expected model and contract committed before retained sampling audit |
| `901c026` | Initial complete preparation implementation |
| `37c13b3` | Packet-lifetime link-capture repair and qualified build reuse |
| `290760486b627701a0555c0b98a27e4332ec9957` | Final metadata coverage criteria and tested preparation source |

The [execution index](P05-fresh-dv-preparation.json) records the tested tree,
source/configuration/tool/artifact hashes, exact commands, seeds, observed bins,
compile origin and original dirty state. Final checker/stimulus runs are clean
at the tested commit. SV compilations are reused only after exact registered
HDL/header, generated configuration, dependency, compiler-argument and tool
identity checks. Original compile revisions/dirty flags remain recorded; an
original dirty compilation is not relabeled as a clean final-revision compile.
No registered HDL changed in the two later Python checker/coverage repairs.

The [frozen contract and risk matrix](../../dv/memory_tx/contract.md) derive from
interfaces, module contracts, buffer management, queues/scheduling, verification
and formal specifications plus public declarations. Expectations use observed
writes/actions and externally accepted beats, not driver packet handles or DUT
cursors/free counts. Retained P07 reuse is limited to sample/stamp types, passive
stream sampling, held-stream SVA and report termination; no retained expected-byte
or policy checker is reused. The preparation define excludes those other checks.

## Executed qualification

| Check | Result and boundary |
| --- | --- |
| Oracle, six profiles | PASS: seeds 17,31,53 plus seed-17 replay, with distinct/repeatable traces |
| Bounded pressure | PASS: 192 sampled sink patterns per oracle run; latency 1/2, depth 4/8, cell bytes 16/32/64 |
| Literal witnesses | PASS: fragmented [5,1,9] chain, 35 literal bytes, keeps/returns/due cycles at both latencies/depths |
| Metadata and bytes | PASS: all final keeps, word/cell/MAX boundaries, every profile source/qid, maximum descriptor, duplicate tags and unused-lane/tag invariants |
| Reset and atomic batches | PASS: dispatch, pending, exact-full FIFO, partial cell and cell/packet-final holds; persistent arrays and distinctive ID/tag reuse; reserve/allocate/write/commit/retire overlap |
| Detector qualification | PASS: 36 labeled oracle probes; eight selected detector removals and two wrong model deltas at E0 seed 17 fail their intended self-tests |
| P07/UVM replay, six profiles | PASS: 26 executable legal/corrupt replays per profile, three seeds plus replay; 28 cases including validated build availability and trace-digest comparison |
| Passive collection and assertions | PASS: omissions, duplicate/mixed/missing-final callbacks, absent triggers, nonempty shutdown, held-data SVA, response/completion detectors and current-oracle replay |
| Saved coverage | PASS: nonzero owned bench code/covergroups, required observed bins, raw coverage and monitor exports per elaboration; no DUT coverage claim |
| Parameters/runner | PASS: both pinned frontends accept the public valid probe and reject five named invalid configurations; 10 boundary/cache tests; empty selection/replay fail; response has no ready |
| PR #19 capture regression | PASS: nine existing capture tests; new isolated outside-output fixture also retains an unexpected failure |
| Hosted CI at tested commit | [Light workflow 43510946402](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/43510946402) succeeded; hardware/toolchain suites skipped |
| Future DUT invocation | NOT_IMPLEMENTED, exit 1; never replaced by oracle/bench PASS |
| Production tests/performance/formal proof/DUT coverage | NOT_RUN |
| Candidate and merged-source confirmation | NOT_RUN; no named RTL candidate exists in this task |

Counts below are the seed-17 baseline observed through passive UVM export and
independent replay. Each row completes 26 packets; issued reads, responses and
external transfers agree. Full shutdown restores all cell/descriptor ownership,
credit and transaction obligations. The independent ledger recomputes credit
from reservations and external cell boundaries rather than copying model deltas.

| Profile | Latency | Accepted beats | Valid bytes | Cell returns | Sources/qids hit | Full arrivals/exchanges |
| --- | --- | --- | --- | --- | --- | --- |
| F0 | 1 | 1724 | 13696 | 229 | 4/16 | 1663/1151 |
| F1 | 2 | 1724 | 13696 | 229 | 4/16 | 1667/998 |
| I0 | 1 | 296 | 2284 | 155 | 2/4 | 238/88 |
| I1 | 2 | 296 | 2284 | 155 | 2/4 | 244/12 |
| E0 | 1 | 159 | 1191 | 86 | 1/2 | 102/27 |
| E1 | 2 | 576 | 4515 | 155 | 4/8 | 523/210 |

These are fixture transaction counts, not throughput or production measurements.
Allocator selection and scheduling are abstract component endpoints; this does
not qualify lowest-free-ID policy or whole-top allocation history. Metadata
port structure, production binding/coverage and internal link latching still
require later actual-source qualification. Prepared FP-TX assertions execute on
replay; [safety/progress and F01 boundaries](../../formal/tx/README.md) retain
separate assumptions and cover plans. No production formal proof is claimed.

## Unexpected failures and repairs

Ten original captures remain under `verification/failures/`: nine verification
defects and one tool-environment interruption. Source/patch or archived input,
commands and first diagnostics were preserved before repair. No capture opt-out
was added. Intentional faults remain isolated and separately labeled; none is
reported as a natural RTL discovery.

The verification fixes cover three detector-fixture interactions, two compile
scaffolding errors, two expected-response classification errors, stale
link-capture state across descriptor/cell reuse, and missing source/qid baseline
coverage. The latter two have independent before/fix/retest evidence: the old
checker accepted an absent capture in a second lifetime, and saved F0 output
initially hit only source/qid zero. The final two-lifetime legal/corrupt UVM
replays and raw-output metadata probe pass. The environment reconnect lost the
parent orchestration handle while its two child runs completed PASS; its unknown
exit status is retained as INCONCLUSIVE, followed by completed resumed execution.
All final mandatory checks pass; the confirmed independence breach remains unresolved.

## Reproduction and artifacts

Exact executed argv and per-run references are in the JSON index. A fresh build
can regenerate each profile without any saved binary:

```sh
for profile in F0 F1 I0 I1 E0 E1; do
  python3 tools/run.py regression --profile "$profile" --seed 17 --timeout 120 --build-timeout 600 --test memory-tx-oracle --test memory-tx-bench
  for seed in 31 53 17; do
    python3 tools/run.py regression --profile "$profile" --seed "$seed" --timeout 120 --build-timeout 600 --test memory-tx-oracle
  done
done
```

The final runs used each profile's explicit original preparation build manifest
with `--preparation-build-manifest`; those exact paths/hashes are in the index.
That option does not discover a build. It validates the named build and reruns
current stimulus/monitors/checking. Raw stdout/stderr, `samples.jsonl`,
`observed.jsonl`, replay inputs, `coverage.dat` and expected-negative waveforms
remain in the referenced `.build/runs` directories. The index stores compact
hashes/counters; expired raw artifacts can be regenerated with the commands.
The qualified stack is Verilator 5.054, pinned UVM 2020.3.2, Yosys 0.70+post/Slang
and Python 3.12.14; exact revisions and lock identities are in the index.

The future DUT command is deliberately non-success during preparation:

```sh
python3 tools/run.py regression --profile I1 --test memory-tx --seed 17 --timeout 120
```

The [public command/API/source handoff](../implementation/p05-rtl-handoff.md)
contains no checker internals or private vectors. A separately assigned DV task
must combine named RTL/DV commits in an isolated worktree, record the combined
tree and any resolution/dirty diff, validate the candidate before RTL merge and
confirm the actual merged source afterward. The maintainer controls preparation
merge, which establishes no hardware acceptance.
