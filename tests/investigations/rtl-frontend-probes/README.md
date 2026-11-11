# RTL frontend representation baseline

This preserves the investigation at `a473b8c535d02b50b23604047f1bae64638c89df`.
It qualifies representations on the old pinned frontend combination, without
changing production RTL, dependencies, specifications or registered source sets.
It does not decide the representation for a newer frontend. Re-evaluate that
choice with separately identified tools and evidence.

## Original investigation

[original/provenance.json](original/provenance.json) records the exact observed
tool identities, investigated revision and SHA256s. The original tools were:

| Tool | Exact observed identity |
| --- | --- |
| Verilator | `Verilator 5.054 2026-11-01 rev vUNKNOWN-built20261110` |
| Yosys | `Yosys 0.52 (git sha1 fee39a3284c90249e1d9684cf6944ffbbcbb8f90)` |
| SBY | `SBY v0.71` |
| Z3 | `Z3 version 4.13.3 - 64 bit` |
| Compiler | `g++ (Debian 14.2.0-19) 14.2.0` |

The qualified source pins include SBY commit
`79fc9eddca5e33a28cc2f2cd19c9825efd9a7255`; the Verilator archive and other
dependency pins remain in [dependencies.json](../../../tools/dependencies.json).
That file's original hash is checked before replay.

[original/commands.json](original/commands.json) retains the original exact argv,
working directories, return codes, formal configurations, diagnostic excerpts,
and log/wave hashes. Its absolute paths are historical evidence, not current
source dependencies. Bulky raw logs, builds, netlists and waves are not committed.

| Candidate | Original Verilator result | Original Yosys result | Interpretation |
| --- | --- | --- | --- |
| `baseline` | Simulation PASS | Synthesis PASS | Existing non-ANSI local records |
| `ansi_vectors` | Simulation PASS | Synthesis PASS | Explicit ANSI vectors; local field access remains typed |
| `package_vectors` | Simulation PASS | Frontend rejection, exit 1 | Wildcard import rejects at `TOK_PACKAGESEP` |
| `package_scoped` | Simulation PASS | Synthesis PASS | Fixed package types/constants with explicit qualification |
| `inline_struct` | Simulation PASS | Frontend rejection, exit 1 | Anonymous struct ports reject at `TOK_STRUCT`; fields repeat |
| `type_parameter` | Simulation PASS | Frontend rejection, exit 1 | Parameter-dependent type parameters reject at `TOK_ID` |
| `forward_typedef` | Compile rejection, exit 1; simulation NOT_RUN | Frontend rejection, exit 1 | Port typedef appears after use |
| `minimal` | Simulation PASS | Synthesis PASS | Qualified package form; FIFO drops unused records and aliases |
| `named_widths` | Simulation PASS | Synthesis PASS | Same form with named, non-overridable ANSI width constants |
| `bits_type` | Simulation PASS | Frontend rejection, exit 1 | `$bits(package_type)` width rejects at `OP_CAST` |

Successful build, simulation and synthesis commands exited 0. A rejection is
matched only against its intended diagnostic. The runner does not classify an
arbitrary nonzero exit, missing tool or timeout as a successful negative check.

The old-stack recommendation was ANSI ports, fixed package definitions and
packed-vector boundaries with local typed records for parameter-dependent data.
The smallest ANSI-only step does not require package extraction. Named widths
improve headers; vector boundaries lose field names and some type checking.
Module-local records and `$bits(typed_signal)` layout guards retain field-oriented
logic and catch width drift. The FIFO stores complete beats and needs no record
aliases. No production migration is included here.

## Configurations and exercised behavior

Simulation and synthesis each contain both configurations in the same design:

| Parameter | A | B |
| --- | --- | --- |
| `N_RX` | 1 | 2 |
| `N_Q` | 2 | 4 |
| `N_CELL` | 16 | 32 |
| `N_DESC` | 8 | 16 |
| `RX_FIFO_DEPTH` | 2 | 4 |
| Statistics record bits | 1290 | 1944 |

Both use `DATA_W=64`, `CELL_BYTES=16`, `MAX_PACKET_BYTES=128`,
`MEM_RD_LATENCY=1`, `TX_FIFO_DEPTH=4`, `SCHED_MODE=1`, `TRACE_ENABLE=1`,
`QUANTUM_DEFAULT=128` and automatically derived index/count/deficit widths.
A is E0; B is a valid custom configuration, not the exact I0 profile.

Copies of the actual FIFO/CSR/statistics implementations exercise no fall-through,
stalls, malformed keep preservation, simultaneous push/pop, reset suppression,
independent AW/W capture in both orders, zero strobes, held B/R responses,
overlapping reads/writes and address-range checks. Statistics checks cover
global/final-queue lanes, rejection enums, keep-byte counting, merged high-water,
pre-update snapshots, shadow CSR reads and disabled/idle clear. Successful
simulation requires both configuration markers and `PROBE_PASS`.

The formal harness uses the actual FIFO with its existing properties and two
small parameterized snapshot stages. Fixed package enums appear in real ports
and logic; local records back packed snapshot lanes. Reset is assumed low for
the first two sampled edges and arbitrary afterward; there is no sink fairness.

| Formal expectation | Original result |
| --- | --- |
| `prove` | PASS, unbounded k-induction; depth 8 for `ansi_vectors`, `package_scoped`, `minimal`; depth 4 for `named_widths` |
| `cover` | PASS within bound 16; all eight covers reached by step 7, including both last-queue snapshot lanes and FIFO reset while busy |
| `mutation` | Expected FAIL, exit 2, depth 8; both `a_snapshot` assertions fail at step 4 with nonempty VCD |

The mutation XORs the captured owned vector with 1. It must fail the intended
assertions in both configurations. Covers establish reachability, not safety.
The original first reset model made reset-while-busy unreachable; it was corrected.
A mutation search at depth 4 was inconclusive and was replaced by depth 8.
Early harness syntax/path failures were corrected before qualification. These
initial outcomes are not counted as passing checks. An additional ANSI depth-4
induction result is retained in the historical command records.

## Reproduce from a fresh checkout

Required tools are Python 3.11+, Bash, Make, the old Verilator/Yosys/SBY/Z3 pins,
and the qualified C++ toolchain (GCC 14). No UVM library, Docker or GUI is needed
for these probes. Prepare tools separately using the repository's existing
[toolchain instructions](../../../docs/implementation/toolchain.md); replay
commands never install, download or upgrade dependencies.

From the checkout root, activate the prepared repository-local toolchain:

```sh
source .tools/activate.sh
probe=tests/investigations/rtl-frontend-probes
python3 "$probe/generate.py"
python3 "$probe/verify.py"
python3 "$probe/run.py"
python3 "$probe/formal_run.py"
```

For an externally prepared toolchain, source its `activate.sh` instead. The
original managed environment used `/workspace/toolchain/activate.sh`; this is
not required by any probe script. `--help` documents tool timeouts and selections.

The generator and runners accept `--repo-root`; `generate.py` accepts `--output`,
and both runners accept `--generated` and a new, non-existing `--output` directory.
Defaults resolve from the script location, not the current working directory.
For example, from another directory:

```sh
python3 "$checkout/$probe/generate.py" --repo-root "$checkout" --output "$scratch/generated"
python3 "$checkout/$probe/verify.py" --repo-root "$checkout" --generated "$scratch/generated"
python3 "$checkout/$probe/run.py" named_widths --repo-root "$checkout" --generated "$scratch/generated" --output "$scratch/simulation"
python3 "$checkout/$probe/formal_run.py" named_widths --repo-root "$checkout" --generated "$scratch/generated" --output "$scratch/formal"
```

The default generated sources and unique run directories are under ignored
`.build/rtl-frontend-probes/`. Each run retains exact commands, separate stdout
and stderr, tool identities, raw return codes, checked expectations and generated
Yosys/SBY scripts. Exit 0 means all selected old expectations matched, including
explicit expected rejections; inspect `summary.json` to distinguish these from
positive passes. Formal prove, cover and mutation remain separate cases.

Default replay refuses tool-version mismatches. `--exploratory` explicitly labels
a different-stack comparison and records whether the old expectations still
match; it does not qualify a new stack or make a representation decision.
`run.py --phase simulation` and `run.py --phase synthesis` allow independent
replay without rebuilding the other phase.

## Preservation checks and scope

[original/sources](original/sources) contains small frozen candidate sources for
review; [fixtures](fixtures) contains the simulation, synthesis and formal
harnesses. [generate.py](generate.py) recreates candidates from production inputs.
[verify.py](verify.py) requires all 53 candidate/header, harness and relevant
input hashes to match the original. Every replay performs this check first.
The path-portability edit changes orchestration only; SV bytes, parameters,
assertions, reset assumptions and source ownership are unchanged.

[preservation-results.json](preservation-results.json) records new preservation
executions separately from the original investigation. Original raw return codes
are never replaced by the later run's outcomes.

The new replay matched 19 build/simulation, 10 synthesis and 12 formal
expectations. A separately relocated checkout also matched the `named_widths`
simulation, synthesis and three formal checks when invoked from `/tmp`.
The new runner's first quoted-include attempts failed and were corrected by
staging identical headers. One unchanged depth-8 proof timed out at 120 seconds
during concurrent jobs and passed with `--timeout 240`; both outcomes are retained.

These are representation capability checks on two configurations, not a full
traffic-manager regression, six-profile qualification, equivalence proof,
four-state validation or physical implementation result. Verilator is two-state;
Yosys synthesis here uses generic logic rather than Liberty/STA signoff. Vector
boundaries still require explicit width maintenance. Anonymous structs, import
syntax, type parameters and `$bits(type)` limitations are observations about this
pinned Yosys frontend, not universal SystemVerilog restrictions.
