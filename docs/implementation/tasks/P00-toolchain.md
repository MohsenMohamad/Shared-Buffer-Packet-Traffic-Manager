# P00: Open-source toolchain and executable capability gates

## Objective and prerequisites

Qualify a reproducible native open-source tool combination before production RTL work. This card defines G0; it is not an instruction to redo an existing qualified P00 implementation.

Dependencies: Initial specification seed. Preserve an existing P00 implementation as described below.

## Sources and work boundary

- [toolchain.md](../../spec/toolchain.md)
- [automation.md](../../spec/automation.md)
- [acceptance.md](../../spec/acceptance.md)

`tools/`, `tests/toolchain/`, dependency locks, `Makefile`, capability CI and their focused documentation.

## Execution sequence

1. Check whether P00 is already integrated. If it is, use its setup guide, lockfiles and evidence; use the [explicit refresh follow-up](P00-followup-toolchain.md) for authorized upgrades, or investigate a demonstrated missing capability. If it is still on a candidate branch, have that candidate reviewed and integrated by the maintainer before P01 rather than building a second toolchain.

2. For a unimplemented P00, install and lock the simulator/UVM/solver/formal/synthesis/STA combination. Verify source integrity and host ABI/compiler compatibility. Keep setup separate from test execution and prove that repeat installation reuses verified inputs.

3. Build the actual supplied UVM fixture with timing, assertions and coverage. Exercise successful and unsatisfiable randomization, two distinct seeds and same-seed replay. Inspect saved owned-code points and functional bins.

4. Run a held-output mutation and require the intended assertion and trace. Add a real unbounded proof, reachable cover and assertion counterexample on a formal fixture; distinguish each outcome.

5. Map a real fixture through Liberty/ABC and run constrained max/min OpenSTA paths. Preserve the identified cell library and all timing inputs.

6. Exercise the bounded runner against compiler errors, missing tools, malformed/empty selections and timeout descendants. Check nonempty result/artifact generation, not just a shell exit.

7. Use the repository command entry points in independent hosted capability jobs. Preserve portable unsupported-feature reproducers separately from the required executable UVM baseline.

## Required checks

| Area | Evidence required |
| --- | --- |
| Installation | Clean setup, repeat setup, locked version/integrity checks and native host prerequisites. |
| Capabilities | `make doctor`, `make repo-check`, `make test-unit`, `make lint`, `make test-uvm-smoke`, `make formal-smoke`, `make synth-smoke`, `make ci`; these are capability checks at this stage. |
| Checker rejection | Intended assertion/counterexample detection, real compiler/tool-error rejection, empty selection rejection and bounded process cleanup. |
| Evidence boundary | Saved coverage and traces; two-state/X-Z and UVM service limits distinguished from TM verification. |

## Completion

G0 has an executable required UVM path, proof/cover/mutation and mapping/STA fixtures, with reproducible setup and genuine error detection. A candidate result is not integrated completion until its change is merged.

Requirement focus: G0 capability evidence; no production-hardware requirement is closed by fixtures.
