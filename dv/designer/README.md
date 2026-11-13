# Memory/TX designer smoke

Run the production RAM, metadata wrapper and TX together with the prepared
repository toolchain. This is RTL-owner smoke, separate from P05-DV's independent
models, UVM campaign, coverage and FP-TX qualification.

```sh
python3 dv/designer/run_memory_tx.py --profile E0 --profile I1
python3 dv/designer/run_memory_tx.py --profile F0 --profile F1 --profile I0 --profile I1 --profile E0 --profile E1
```

Each selected profile runs FIFO depths four and eight by default. `--depth 4`
or `--depth 8` selects one. There is no random seed: byte patterns and sink
stall sequences are deterministic. `sources.json` adds only designer smoke to
the production registry; no independent suite/requirement registry is changed.
The entrypoint uses the existing `Run`/`Case` process bounds, provenance and
failure capture. Build products and full logs live in `.build/runs/`.

The edge monitor compares actual read requests/responses against observed
writes, accepted bytes against deterministic packet contents, and returns against
accepted beat ordinals. Cases include all keeps, cell/MAX boundaries, pending and
full-credit stalls, simultaneous issue/response/retire, overwriting returned
payload/links before old EOF, repeated IDs/tags and pending/full/stalled-EOF
resets. Continuous ready cases assert the latency+4 bound and one beat per
clock across cells. Metadata probes exercise the P03 link child and the explicit
TX/abort link and per-queue info query interfaces. These checks do not establish
independent requirement closure or a physical flat/banked comparison.
