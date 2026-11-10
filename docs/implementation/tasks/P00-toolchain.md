# P00: Open-source toolchain and executable capability gates

## Dependencies

Initial specification seed

## Relevant contracts

- [ toolchain.md ](../../spec/toolchain.md)
- [ automation.md ](../../spec/automation.md)
- [ acceptance.md ](../../spec/acceptance.md)

## Scope and primary paths

tools/setup.sh; tools/doctor.py; tools/run.py; tests/toolchain/; Makefile; dependency lock; .github/workflows/

## Deliverable

Install and pin the open-source toolchain in the cloud workspace. Add idempotent setup, version/capability reporting, bounded runner and CI capability jobs. Qualify the supplied UVM smoke and a negative assertion build, saved code/functional coverage, seed replay, a real formal prove/cover/mutation trio and a mapped Liberty/OpenSTA max/min smoke. Preserve exact source pins and report unsupported constructs. Keep the initial implementation independent of hardware modules.

## Validation

make doctor; make repo-check; make test-uvm-smoke; make formal-smoke; make synth-smoke; make ci. Inspect actual saved coverage points/bins. Prove that compile/tool errors and empty selections cannot pass. Pin the final compatible toolchain combination.

## Exit condition

G0. If a tool feature is unsupported, deliver its minimal reproducer and implementation/test source with UNSUPPORTED status; continue independent setup. The primary executable UVM path remains required.

Deliver one cohesive reviewable change. If the card is larger than a safe single change, split it along tested component boundaries and record what remains. State actual executed commands/results and unresolved limits in the PR. Update a compact handoff only when unfinished work needs continuation.
