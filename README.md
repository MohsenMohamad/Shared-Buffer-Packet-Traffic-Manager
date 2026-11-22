# Shared-Buffer Packet Traffic Manager

A single-clock SystemVerilog traffic manager for variable-length Ethernet
frames. The primary architecture connects four 64-bit inputs to four independent
64-bit outputs. Sixteen output queues share 1,024 payload cells and 256
descriptors. The design reserves an entire frame before service, publishes it
after the final validated write, and schedules four traffic classes per egress.

| Profile | Ports | Queues | Cells / descriptors | Frame bytes |
| --- | --- | --- | --- | --- |
| Primary | 4×4 | 16 | 1,024 / 256 | 60–1,536 |
| Small | 2×2 | 8 | 16 / 8 | 60–192 |

Both profiles use 64-byte cells, one shared read and one shared write per
cycle, and fixed read latency of one or two cycles. The contract defines
static or dynamic admission, byte DRR and packet round robin, an optional
strict class, token-bucket shaping, ECN metadata and AXI4-Lite control.
[Behavior](docs/spec/multi-egress-traffic-manager.md) · [Interfaces](docs/spec/multi-egress-interfaces.md)

## Status

The public ABI and independent pool replay bench are integrated. The cycle
model met the balanced four-port throughput target in the specified workloads.
Control timing studies support carrying balanced same-edge admission and
cached queue heads into integration. Production datapath implementation,
independent RTL qualification and composed reset/timing acceptance remain
open. [Current evidence and gates](docs/status.md)

## Run the available checks

Use the pinned Linux x86-64 toolchain from the [setup guide](docs/implementation/toolchain.md).

```sh
make setup
make doctor
make multi-egress-declarations
make multi-egress-pools-preparation
make formal-symbols
```

The declaration checks exercise the public interfaces. The pool command
runs directed and seeded SV/UVM replay with independent ownership and credit
checking, functional coverage and planted-fault detection. The symbolic check
qualifies the formal frontend. See the [verification plan](docs/spec/verification.md)
and [results](docs/results/README.md) for exact scopes and replay commands.
