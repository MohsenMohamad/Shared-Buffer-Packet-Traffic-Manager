# RTL representation migration

Representation-only scope, recorded before RTL edits. Baseline is clean
`fb3cd3fd7e2c73379617f11a82c8418e1a590d24` (fetched `origin/main`).
The [capability table](../implementation/modern-toolchain-decisions.md) and
[P01 card](../implementation/tasks/P01-followup-representation.md) govern this
migration. P03+ production implementation and allocator/scheduler optimization
remain paused.

## Baseline and scope

| Concern | Frozen baseline / migration boundary |
| --- | --- |
| Production | FIFO, bitmap/cell/descriptor pools, AXI registers and statistics implemented; top and nine remaining APIs declaration-only |
| Layout | Packed lane zero at LSB; struct fields MSB first; 64-bit input/output metadata, raw qid 8 bits, status 45 bits, full beat 137 bits |
| Configuration | All six profiles in unchanged `verification/profiles.json`; existing scalar overrides and 25 invalid configuration checks retained |
| Ownership | Pools own bitmap/count; CSR owns config/channel holds; statistics owns counters/shadows; no new state owner |
| FIFO | Depth 2/4, registered ready, no fall-through, full-to-pop bubble, unreset payload, one clocked write and asynchronous head read |
| CSR/statistics | Independent AW/W, one read/write outstanding, stable stalled responses, read-before-write, pre-event snapshot, modulo counters and unchanged locks/errors |
| Reset/formal | Asynchronous assertion, two-edge startup constraint, arbitrary later reset/actions; existing assumptions/assertions/covers/mutations remain authoritative |
| Representation | Replace non-ANSI headers, consolidate fixed enums/records, derive widths from types, narrow unused type dependencies; preserve API names and packed boundaries |
| Inference | Compare actual memory dimensions/ports and mapped state against baseline; preserve known −0.09 ns reset-removal violation under unchanged FIFO constraints |

Historical P01/P02/P06/P07 and toolchain reports are preserved. Equivalence is
supplementary to independent contract simulation and formal checks, never a
replacement. No integrated datapath, allocator scaling, four-state simulation,
coverage closure or physical timing signoff is claimed.

Execution evidence will be added after checks run.
