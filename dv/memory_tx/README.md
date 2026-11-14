# Memory/TX verification

`memory-tx` executes exact candidate RAM, finite-port metadata and TX through a
clocked public-interface adapter and the frozen observed-write oracle/resource
ledger. `memory-tx-oracle` and `memory-tx-bench` remain separate preparation
self-tests; their PASS cannot satisfy production execution.

In a detached combination of current main, the named RTL revision and the
DV-only qualification revision:

```sh
python3 tools/run.py regression --profile I1 --test memory-tx --candidate-revision 479b5c1ceee2eee8db58d863bd5de5e20305cc8c --seed 17 --jobs 2 --timeout 180 --build-timeout 600
```

The command checks candidate source identities before executing, then crosses
latencies 1/2 and FIFO depths 4/8 with seeds 17/31/53 and seed-17 replay. Repeat
for F0, F1, I0, I1, E0 and E1 geometries. `--memory-latency` and `--tx-depth`
select a smaller diagnostic scope; they do not establish the complete matrix.
Missing candidate identity/source, missing mandatory observed bins, nonempty
shutdown, build/runtime failures and changed seed replay are non-success.

`candidate-public.json`, semantic `public-inputs.jsonl`,
`public-output-checks.jsonl` and `public-interface-result.json` contain source
identity, configuration, seed, public stimulus and expected/observed interfaces
without verification implementation excerpts. Expected data masks exclude unused
lanes. Full samples, raw transport, separate stdout/stderr, generated configuration,
coverage, binary digests and failure captures remain available for DV diagnosis.
The server's independently advancing edge timestamp rejects missing/duplicate/
mixed samples, and every server exit status is checked.

The standalone physical RAM phase checks 64-bit 1R1W, exact response latency,
reset-persistent readback and simultaneous distinct-word accesses. Packet tests
check all kept bytes, metadata including return/completion tuples, order,
exactly-once completion, full credit, stalls, fragmented chains, earliest/random
legal reuse, stale links, reset/reused IDs and shutdown conservation. Atomic
first-allocation/write/commit carries the RX handoff metadata directly; metadata
read muxes are independently compared with pre-edge array contents.

```sh
python3 tools/run.py formal-rtl --profile E0 --test memory-tx --candidate-revision 479b5c1ceee2eee8db58d863bd5de5e20305cc8c --timeout 300
python3 tools/run.py coverage --profile I1 --test memory-tx --coverage-manifest PATH_TO_PASSING_UNMUTATED_CASE_MANIFEST
```

See [FP-TX scope](../../formal/tx/README.md). Saved coverage is checked against
source, adapter/checker, binary, sample and artifact identities per elaboration;
mutations never contribute production coverage. Functional bins are mandatory.
Measured code counters do not claim code-coverage or P12B structural closure.

Preparation remains independently runnable:

```sh
python3 tools/run.py regression --profile E0 --test memory-tx-oracle --seed 17 --timeout 120
python3 tools/run.py regression --profile I1 --test memory-tx-bench --seed 17 --timeout 120 --build-timeout 600
```

Its explicit `memory-tx-preparation` source list still has no production
inheritance. Exact `--preparation-build-manifest` reuse retains the original
compile identity and reruns current checking. Historical results and provenance
qualifications remain in [the preparation report](../../docs/results/P05-fresh-dv-preparation.md).
