# P07 UVM foundation qualification

This report concerns an executable UVM bench and its independent checkers on
a declared behavioral fixture. It does not validate the production traffic
manager. P01 types/APIs and the integrated P02 FIFO/pool implementations were
inspected; the fixture does not instantiate or replace production modules.

## Executed scope

The source and sink agents execute sequencer/driver transactions and independent
passive monitors. AXI uses independent write/read request workers, separate AW/W
holds, all three directed arrival orders, B/R stalls and overlapping reads and
writes. The RAL fixture block executes frontdoor write/read/mirror operations
through the real adapter, sequencer and passive register predictor. The complete
production register-map declaration is constructed and checked for layout/reset
shape; the production slave and its register behavior remain unverified here.

The byte model consumes handshaken input bytes and status pulses, identifies
frames by epoch/source/ordinal and checks output bytes, metadata, keep, count and
surviving per-source/per-queue order. The service model separately validates FIFO
service, admission reasons, format/commit/status causality, ownership, scalar
resource equations and AR-edge resource CSR snapshots. The scheduling model
checks pre-state committed heads and a one-queue-per-free-cycle DRR scan, including
credit carry, true-empty closure and freeze during TX ownership. Trace reports
cannot supply expected payload bytes or justify an admission decision.

The fixture exercises duplicate tags, all source/queue lanes in each executed
profile, partial final words, cell boundaries, source gaps/stalls, sink stalls,
a bad qid, a sparse first-beat keep, zero-cell abort cleanup and reset with RX
work plus a stalled AXI response. Separate model probes exercise atomic reserve,
materialization, TX completion and abort completion with two descriptor returns.
The negative atomic probe rejects an admission that only fits after same-cycle
releases. The two-port atomic scenario is excluded for E0 because two simultaneous
status destinations require two ports; I0 executes it.

The barrier probe shuffles all monitor callbacks for 128 complete idle batches
and rejects duplicate, missing/mixed-cycle and stale reports. P01's separate
Python tests retain their exhaustive six-source permutation checks; those tests
are not substituted for execution of the UVM bench.

## Results and evidence

The final run summaries and case data are recorded in the companion evidence
file when qualification completes. Only executed fixture checks receive PASS.
The `fixture_qualification` fields in the requirement registry do not change
production requirement status.

The genuine UVM report-server extension preserves error/fatal reports and stops
with nonzero status. Accellera's default `UVM_EXIT` uses `$finish`, which can return
zero on this simulator; continuing past a fatal can produce unrelated secondary
failures. Every seeded negative must have exactly its intended first detector,
a nonzero process status and a nonempty waveform. An unrelated assertion,
compiler error, crash or timeout does not qualify it.

## Reproduction and artifact retention

From the repository root:

```sh
make setup JOBS=2
make doctor
make regression JOBS=4 RUN_ARGS='--profile I0 --test uvm-foundation --seed 23 --output .build/p07-evidence'
make regression JOBS=2 RUN_ARGS='--profile E0 --test uvm-foundation --seed 17 --output .build/p07-evidence'
make regression RUN_ARGS='--profile E0 --test contracts --seed 17'
make repo-check
make test-unit
python3 -m unittest discover -s tests/contracts -v
```

Each fixture suite builds a distinct executable with `--timing --assert
--coverage --trace-vcd`, unmodified pinned UVM 2020.3.1 and `UVM_NO_DPI`, then runs
its supplied seed, identical replay, alternate seed and a small-quantum variant.
Manifests retain the generated profile configuration, registered source hashes,
revision/dirty state, dependency/tool versions, exact argv, timestamps, separate
stdout/stderr, return codes and result categories. Coverage is read from saved
`coverage.dat` counters and reported by `verilator_coverage`; it is never inferred
from a printed percentage. Negative and unexpected positive-failure reruns retain
waveforms from the identical binary/profile/seed. `first_failure.json` links the
logs and recent event batches for triage.

Raw artifacts stay under ignored `.build/p07-evidence/`. The UVM foundation
workflow executes E0 and I0 and retains `.build/` for 14 days; workflow presence
alone is not hosted execution evidence. Regenerate expired artifacts with the
commands above and the recorded revision. See [bench reuse](../../dv/README.md)
and [the design decision](../decisions/0004-uvm-foundation.md).

## Qualification boundaries

The new library subset comprises factory/config-db use, parameterized UVM
sequencer/driver APIs and response delivery, typed mailboxes, analysis ports and
implementation/subscriber callbacks, register fields/maps/adapter/predictor,
frontdoor RAL, the standard report-server extension, queue shuffling, covergroup
bins/crosses and held-channel SVA. Full fixture/probe execution qualifies this
subset together; unsupported/ignored owned constructs are build failures.
The upstream `NO_DPI_USED` and `NO_VISIT_CHECK` warnings describe the already
qualified no-DPI baseline, not disabled owned checks. No dependency patch is used.

Production RAM response credits/latencies, link traversal, nonzero-cell abort
cleanup/concurrency, WAIT resource traffic, configuration locking, snapshot
statistics, packet-RR mode, full reason/parameter matrices, fairness, performance,
production assertion closure and coverage closure remain for later tasks.
The checker exposes static limits/WAIT and quantum configuration for integration;
this stage qualifies the declared DROP/default-limit fixture and its DRR variants.
Other registered profiles are available but have no executed result unless listed
in the evidence. Verilator remains a two-state simulator; X/Z behavior is outside
this result. Saved bench line/branch/toggle and functional coverage do not imply
production RTL coverage or reviewed closure of mandatory production bins.
