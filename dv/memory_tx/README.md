# Independent memory/TX preparation

This suite qualifies a new observed-write oracle and a P07/UVM passive-edge
replay bench. It executes no target or dependency RTL implementation. The
[contract](contract.md) defines frozen expectations and the risk/check/cover
matrix; [FP-TX preparation](../../formal/tx/README.md) defines proof boundaries.

```sh
make regression RUN_ARGS='--profile E0 --test memory-tx-oracle --seed 17 --timeout 120'
make regression RUN_ARGS='--profile I1 --test memory-tx-bench --seed 17 --timeout 120 --build-timeout 600'
make regression RUN_ARGS='--profile I1 --test memory-tx --seed 17 --timeout 120'
```

The first command executes model/trace qualification, 192 bounded sink patterns
across latency 1/2, FIFO depth 4/8 and cell size 16/32/64, literal fragmented-chain
witnesses, reset, metadata, held-field, conservation and detector tests. At E0
seed 17 it also qualifies eight detector removals, two wrong model deltas,
public parameter rejection through both frontends and preparation boundaries.
Run seeds 17,31,53 plus replay at each production profile for saved diversity.

The second compiles the explicit preparation source set and runs a UVM sequence,
sequencer and driver, P07 passive stream monitor, passive action monitor, sealed
collector, assertions and an independent checker over exported sampled actions.
It executes three generator/simulator seeds plus the original-seed replay,
all reset boundaries, atomic overlap and labeled corrupt signals/collector
callbacks. `observed.jsonl`, `coverage.dat`, functional counters, replay input,
logs and expected-negative waveforms are per-case artifacts. Covergroup/code
collection here is bench qualification, never DUT coverage closure.

The third is the future DUT invocation. During preparation it returns
NOT_IMPLEMENTED and nonzero, even if other modes passed. It never searches for
an implementation. A later DV task must register exact named candidate sources
and a passive binding before enabling this mode; empty selection cannot PASS.

All modes use `tools/run.py` and existing evidence/capture, with an explicit
source identity restricted to public declarations and preparation inputs.
No production source-list inheritance is permitted. Failure capture is still
mandatory, including outputs outside the repository. The fixtures contain no
traffic manager or behavioral TX implementation; the replay environment's
persistent RAM image is not evidence of production memory/TX correctness.

An explicit `--preparation-build-manifest PATH` can reuse this task's passing
SV/UVM compilation when registered HDL/headers, generated configuration,
dependencies, tool identities and compiler arguments match exactly. It records
the original compile revision and binary hash and reruns stimulus, monitors and
current Python checking. It never discovers a build or an RTL implementation.
The normal invocation still compiles. Mismatched or incomplete identities fail.
