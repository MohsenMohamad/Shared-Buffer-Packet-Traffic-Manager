# RTL-owned designer smoke

P05 smoke composes production RAM, metadata and TX through their public ports.
It is owned by RTL and establishes no independent verification acceptance.
`p05_sources.json` lists its exact sources separately from independent suites.

After activating the prepared native tools:

```sh
source .tools/activate.sh
python3 dv/designer/run_p05.py --profile I0 --latency 2 --depth 4 --seed 17 --seed 19 --seed 23
python3 dv/designer/run_p05.py --profile I1 --depth 8 --lint
python3 dv/designer/run_p05.py --profile I1 --depth 8 --synth
```

The runner reads only its explicit designer source registration, the production
source registration, listed production/designer sources and public RTL headers.
It records the candidate base revision and path-scoped dirty state; it does not
hash or inspect independent verification. Native tools receive only those
explicit source files and `rtl/include`. `FORMAL` is never defined, so RTL's
independent property includes are inactive. No test discovery or general
provenance wrapper is invoked.

The smoke checks response timing, byte lanes, keeps, user, stalls, fragmented
chains, reuse following returns, cell/descriptor retirement events, full read
credit pressure and reset boundaries. It sweeps lengths through two cell
boundaries and all final keeps at maximum length. Seeds affect ready patterns.
Always-ready cases require continuous valid after the first transfer.

Logs and command/result records are under ignored `work/p05/`. Unexpected native
failures preserve a snapshot of permitted source, commands, configuration, seed
and output under `verification/failures/p05-designer-*`; classify them before
repair and retain them. No independent DV capture or report is opened by this
runner. Synthesis checks lower the three modules through Slang and `synth
-noabc`, confirm the payload capacity and 1R1W ports, and run `check -assert`.
They provide neither mapped timing/area evidence nor formal proof.
