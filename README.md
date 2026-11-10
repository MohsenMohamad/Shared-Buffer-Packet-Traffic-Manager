# Shared-Buffer Packet Traffic Manager

Single-clock SystemVerilog traffic-manager slice with shared cell storage, descriptor queues, admission control, deficit round robin and backpressure.

Default configuration: four 64-bit packet inputs, sixteen logical queues, one output, 64 KiB of payload cells and 256 descriptors. The design uses whole-packet credit reservations and store-and-forward commit.

## Project state

This initial repository contains the implementation specification, staged work items and tool-capability test sources. Traffic-manager RTL and its subsystem verification are not yet delivered. Track integration gates in [docs/status.md](docs/status.md).

## Documentation

- [Specification index](docs/spec/README.md)
- [Implementation plan](docs/implementation/plan.md)
- [Contribution and validation workflow](CONTRIBUTING.md)
- [Dependencies](tools/dependencies.json)

`make repo-check` validates the specification package and requirement data. Hardware build, simulation, formal and implementation commands are introduced by the toolchain task and subsequent component tasks. Executed results identify their exact source revision, profile and tool versions.
