# Shared types and ANSI production declarations

Use ANSI ports across the implemented and declaration-only APIs. Fixed enums,
packet metadata, status, statistics commands and AXI records have one definition
in `rtl/include/tm_fixed.sv`, compiled before consumers. Parameter-dependent types
are declared before their port use in `tm_types.svh`. Non-overridable
`localparam type` defaults refine the qualified type-parameter recipe without
adding configuration knobs. Guarded scalar widths and existing scalar override
validation remain unchanged. Record-derived widths use `$bits(type)`.

The same scoped dependent declarations serve ANSI headers, formal harness bodies
and the bench's fixed configuration package. `TM_ANSI_TYPES` changes only their
separator (comma versus semicolon); callers undefine it immediately. This avoids
mirrored records, recursively expanded anonymous copies and adapter casts.
There is no parameterized package or forward type reference. Bench types export
the fixed package's names so monitors and checkers share the encodings.

Keep published packed multi-lane vectors and lane-zero-at-LSB ordering. Keep the
FIFO's vector beat ports and storage: it performs only whole-beat copies, so it
needs DATA_W-derived BEAT_W and no unrelated descriptor/configuration types.
This is a useful generic boundary, not a frontend workaround. The selected
frontend correctly infers the record-array alternative as well; matched memory
ports, complete payload mapping and unchanged proofs qualify that conclusion.
The bitmap kernel's packed return lanes likewise express its generic contract.
No production API is renamed and no declaration-only block gains behavior.

The explicit free-input formal harness adapter, immediate properties, two-edge
startup reset and arbitrary later reset/actions remain. Native parsing of the
new richer declarations is unsupported. Native controls use the immutable
pre-migration Git baseline; the selected frontend always reads current registered
production sources. Property identities/counts and complete assumption predicates
are compared against that baseline. Sequential equivalence separately compares
old/current FIFO, pools, CSR and statistics, supplementing independent contract
checks rather than establishing the specification by correspondence alone.

This supersedes the active representation restrictions in decisions
[0002](0002-module-contracts.md) and [0003](0003-storage-primitives.md). Their
original results and reasons remain historical. The [migration report](../results/rtl-representation.md)
identifies executed evidence and limitations. P03+ remains paused, and allocator
characterization and scheduler optimization are outside this change.
