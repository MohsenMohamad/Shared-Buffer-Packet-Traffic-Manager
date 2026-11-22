# TM03 multi-egress declaration validation

The primary 4×4 and small 2×2 public interfaces passed the declaration
matrix. Execution covers port shapes, binary layouts, address decoding
and intended detector failures. See the [interface contract](../spec/multi-egress-interfaces.md)
and [ABI decision](../decisions/0009-multi-egress-interface-abi.md).

## Source and tools

- Baseline `f64f87ce6d45186239db4150c3df548ca115918d`, the fetched
  `origin/main` and PR #29 merge.
- Clean tested commit `5ff24ba8ecbccc8f1fff6ae59396706d72d3a17d`,
  tree `67d016a03173a728eb420aa457c360a1a46dd136`. Sources are named
  by [the isolated declaration registration](../../verification/sources/multi-egress-declarations.json).
  The [single-egress production list](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/blob/4634d5a4dacb00304635ddb64a3f83747d8b03e8/verification/sources/production.json)
  remains at the baseline content.
- Verilator 5.054 (build `vUNKNOWN-built20261112`), Yosys 0.70+post
  `28ba3cb926fe376fa05ebfc1b921747d011d4557`, sv-elab
  `9dcee13ea3862347e1715dc51f63e9f845cdd222`, Slang
  `545f88b2ed3a2d20325fbd17413af177a6bca72f`.
  Dependency and package lock SHA-256 values are
  `4bc7cf21fed06e8ba7e3a2196c45e5aa5e58897d0164c4c0af55d9d1ea3fdc38`
  and `13ce46997fccbd49662be8140443e7321e4c8a8d29a1efc54fd56dd11d797996`,
  respectively. No timing constraints apply to the fixture.
- Exact per-case commands, source digests and observations from
  `make multi-egress-declarations` are in the local runner record
  `.build/runs/multi-egress-declarations-2026-11-21T050805.850034+0000-8790fb16/`.
  The declaration registration and runner regenerate those artifacts.

## Executed declaration matrix

The frontend checks compared every named port, direction and width against
the independent table, including the absence of memory ready ports.
The timed Verilator layout fixture drove the public declaration ports
and ran all four profile/latency cells together, including the high IDs
and full pool counts for primary L2 alongside small L1.

| Profile and read latency | Verilator elaboration | Yosys/Slang elaboration | Verilator layout |
| --- | --- | --- | --- |
| Primary L1 | PASS | PASS | PASS |
| Primary L2 | PASS | PASS | PASS |
| Small L1 | PASS | PASS | PASS |
| Small L2 | PASS | PASS | PASS |
| Paired primary L2 and small L1 | PASS | PASS | PASS in the shared layout executable |

| Layout check | Observed result |
| --- | --- |
| Bytes and framing | All eight stream byte/keep lanes, eleven final length/keep vectors per profile and the literal packet byte order. |
| Raw metadata and dispositions | All named routes, classes and length boundaries, both high tag bytes, all seven codes, absent versus present code zero, and all eight ECN/mark combinations. |
| Physical ports and memory | Every physical presence mask, with distinct sentinels in both directions. All 64 positions of the cell payload, separate command lanes, differing address high bits and response tag/epoch sentinels. |
| Ordered admissions and physical events | Every ordered prefix length, reject and WAIT records, every physical ingress/egress presence mask, singleton events, repeated opaque tags across ordinal/port/epoch contexts and present ID zero. |
| Return fan-in | All 32 primary and 8 small paired return masks, including cleanup alone, last egress alone and full fan-in. Separate zero-cell and intermediate cleanup, plus all return slots alongside prefix reservations and a cell allocation/write in one batch. |
| CSR and snapshot | 1,135 distinct primary and 573 distinct small words. Checked every aligned and misaligned byte address below 0x4000, plus upper-address and invalid-coordinate probes. Checked masks, reset/range/access metadata and two distinct low/high counter sentinels in both profiles. |

All eight execution markers were present exactly once for each of the four
profile/latency cells. CSR enumeration and split-word markers ran for both
profiles. Layout vectors exercise transport capacity. A fixture word may
combine independent event maxima without establishing a reachable DUT edge.
CSR state constraints are specified by access class and the [CSR rules](../spec/multi-egress-interfaces.md#axi4-lite-register-map).
Runtime AW/W handling, merged-strobe validation, idle gating, increments and
snapshot coherence require production DV.

### Expected guard and detector outcomes

Each guard uses a single override in the primary profile. The positive
primary elab cell is its legal neighbor (L2 for the upper latency
boundary). Both tools emitted the named sentinel and rejected the
configuration with exit status 1.

| Override | Named sentinel suffix | Verilator | Yosys/Slang |
| --- | --- | --- | --- |
| `PROFILE=2` | INVALID_PROFILE | Detected | Detected |
| `MEM_RD_LATENCY=0` | INVALID_READ_LATENCY | Detected | Detected |
| `MEM_RD_LATENCY=3` | INVALID_READ_LATENCY | Detected | Detected |
| `N_RX=3` | INVALID_GEOMETRY | Detected | Detected |
| `N_TX=3` | INVALID_GEOMETRY | Detected | Detected |
| `N_CLASS=3` | INVALID_GEOMETRY | Detected | Detected |
| `N_CELL=512` | INVALID_GEOMETRY | Detected | Detected |
| `N_DESC=128` | INVALID_GEOMETRY | Detected | Detected |
| `MAX_FRAME_BYTES=1535` | INVALID_GEOMETRY | Detected | Detected |
| `DATA_W=32` | INVALID_PAYLOAD_WIDTH | Detected | Detected |
| `CELL_W=256` | INVALID_PAYLOAD_WIDTH | Detected | Detected |

The same compiled layout executable passed without plusargs, then exited
with status 1 for each isolated plusarg and exactly the corresponding detector.
The runner rejects alternate failures and missing execution markers.

| Planted fixture defect | Observed detector | Legal neighbor |
| --- | --- | --- |
| `+reverse-bytes` | `byte-order` | PASS |
| `+truncate-route` | `raw-route` | PASS |
| `+suppress-cleanup` | `cleanup-return` | PASS |
| `+alias-csr` | `csr-address-alias` | PASS |
| `+swap-halves` | `snapshot-word-order` | PASS |

## Reproduction and supplemental checks

Use the prepared repository toolchain. The runner records the Verilator
`--json-only` and Slang `read_slang` commands per configuration, the
Verilator `--binary --timing --assert` layout build, the legal execution
and all five plusarg invocations. `make doctor` passed on the baseline
and the clean declaration run repeated the version/capability checks.

```sh
make doctor
make multi-egress-declarations
for profile in F0 F1 I0 I1 E0 E1; do
    make regression RUN_ARGS="--profile $profile --test contracts --seed 17" || exit
done
make repo-check
python3 tools/check_light.py
make test-unit
PYTHONPATH=tools python3 -m unittest discover -s tests/runner -v
git diff --check
git diff --check origin/main...HEAD
```

All six single-egress contract suite selections passed at seed 17.
The repository check, 117 Python units in the light and runner-unit
commands, two runner-isolation tests and both diff checks passed.

## Captured development failures

| Capture under ignored `.build/runs/` | Disposition and repair |
| --- | --- |
| `tm03-ad-hoc-tool-path/` | Tool environment. Bare shell probes exited 127 for Verilator and Yosys. Loaded the prepared environment and reran both frontends. |
| `tm03-frontend-probe/` | Verification/declaration authoring defect. Both frontends rejected the reserved identifier `cell`. Renamed the two fields to `address` and repeated the probes and gate. |
| `multi-egress-declarations-2026-11-21T050435.973512+0000-c8ea25f2/` | Verification defect in the Verilator report reader. Four standalone cases passed an incomplete parameter tuple to the shape reader. The paired case exposed a parameter-type AST node absent from the reader. Case captures retain the affected inputs and commands. Fixed both paths, then repeated all five cases and the full matrix. |

Queue/control feasibility, datapath implementation, independent DV,
production UVM, proofs, throughput, synthesis and mapped timing are open
under the [acceptance plan](../implementation/plan.md#multi-egress-integration-and-release-acceptance).

## PR #30 named packet-field checks

Clean tested commit `8c3de9b8ee3c545b660916dcfefc9b3deb94b6fe`, tree
`1fbe24f7719c15efc4cdf46fb512e9fe9a9c9cc2`. The tool and lock
identities above also apply. The fixture drives named egress and
disposition fields and compares the packed output port lanes against
independent slices from the interface table. In both profiles, valid
records drive different values in each of the swapped positions.

`make multi-egress-declarations` passed its full matrix. All four
primary/small and L1/L2 legal runs reached the physical port marker and
the combined legal executable exited 0. The runner made two separate
disposable copies of the registered sources. Each copy swapped one
equal-width declaration pair, compiled with exit status 0, and was
executed separately with `+layout-profile=0` and `+layout-profile=1`.

| Planted declaration swap | Primary observed detector | Small observed detector |
| --- | --- | --- |
| Egress source and destination | `egress-source-destination-layout`, L2, exit 1 | `egress-source-destination-layout`, L2, exit 1 |
| Disposition destination and class | `disposition-destination-class-layout`, L2, exit 1 | `disposition-destination-class-layout`, L2, exit 1 |

Exact compiler and executable commands, mutant file digests and detector
output are recorded in
`.build/runs/multi-egress-declarations-2026-11-21T052214.564416+0000-af44932b/`.
The unmodified gate command reproduces both disposable swaps. The local
repository, light syntax and Python units, runner-isolation and diff
checks also passed.

```sh
make multi-egress-declarations
make repo-check
python3 tools/check_light.py
make test-unit
PYTHONPATH=tools python3 -m unittest discover -s tests/runner -v
git diff --check
git diff --check origin/main...HEAD
```
