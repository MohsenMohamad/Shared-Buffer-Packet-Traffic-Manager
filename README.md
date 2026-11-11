# Shared-Buffer Packet Traffic Manager

Single-clock SystemVerilog traffic-manager slice with shared cell storage, descriptor queues, admission control, deficit round robin and backpressure.

Default configuration: four 64-bit packet inputs, sixteen logical queues, one output, 64 KiB of payload cells and 256 descriptors. The design uses whole-packet credit reservations and store-and-forward commit.

## Project state

This repository contains the implementation specification, executable toolchain capability gates, and G1 module/type/event contracts. The registered FIFO and cell/descriptor pools are implemented; the top and other component APIs remain declarations. Integrated traffic-manager behavior and subsystem verification remain pending. Track integration gates in [docs/status.md](docs/status.md).

## Documentation

- [Specification index](docs/spec/README.md)
- [Implementation plan](docs/implementation/plan.md)
- [Contribution and validation workflow](CONTRIBUTING.md)
- [Dependencies](tools/dependencies.json)
- [Toolchain setup and commands](docs/implementation/toolchain.md)

`make setup` installs the pinned native tools. `make ci` exercises UVM/randomization/assertions/saved coverage, formal prove/cover/mutation, and mapped synthesis/max/min STA on independent fixtures. `make repo-check` validates documents and requirement data only. Executed results identify their source revision, profile and tool versions.

G1 contract regression: `make regression RUN_ARGS="--profile E0 --test contracts --seed 17"`.
See [module contracts](docs/spec/module-contracts.md) for APIs and scope.
Declaration compilation does not establish traffic-manager functionality.

Storage component regression: `make regression RUN_ARGS="--profile E0 --test pools --seed 17"`.
Production local proofs: `make formal-rtl RUN_ARGS="--timeout 240"`.
See [P02 evidence](docs/results/P02-storage-primitives.md) for scope and results.
