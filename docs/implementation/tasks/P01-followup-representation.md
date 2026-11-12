# P01 follow-up: Qualified RTL representation

Improve production declaration/type readability using the exact frontend
combination qualified by the [P00 refresh](P00-followup-modern-toolchain.md).
Complete this representation change before allocator characterization, preserving
external behavior, finite ports, source ownership and proof/checker strength.

Dependencies: P00 refresh plus integrated P01/P02/P06/P07. P03+ remains paused
until the planned stabilization review. This is a separate PR from tool selection.

1. Consume the refresh's capability-to-design table and executable disposable-copy
   probes. Select ANSI headers and named non-overridable width constants where
   they improve readability. Use fixed packages for truly shared fixed types;
   use qualified parameter-dependent record/type-parameter recipes only where
   they simplify this design and pass production formal/synthesis.
2. Preserve parameter validation, guarded indices/count widths, invalid-qid width,
   field/packing order, memory widths/ports/read latency and all existing APIs.
   Never use a typedef before declaration or invent parameterized-package syntax.
3. Remove duplicated include/type definitions and width formula workarounds only
   where the accepted recipe covers their replacement. A FIFO with bitwise-only
   operations need not acquire redundant typed aliases. Do not add interfaces,
   abstraction layers or algorithms merely because parsing succeeds.
4. Convert registered production and verification callers together; retain the
   native diagnostic path only for its documented supported subset. The formal
   bridge must retain arbitrary streams, initialization, two-edge startup reset,
   later reset freedom, all assumptions/assertions/covers and intended mutations.
5. Recheck all six profiles/invalid elaborations, heterogeneous instances,
   independent FIFO/CSR/statistics behavior, P02/P06 formal and P07 fixture
   detectors/replay/coverage. Rerun inferred-memory/latency and mapped-integrity
   checks affected by representation changes. Record exact tested tree/tool IDs.

Completion supplies an integrated readable representation with no behavior or
verification regression. The [P02 scaling study](P02-followup-scaling.md) then
measures that actual production source under precommitted matched conditions.
It must not characterize a temporary duplicate or change allocator semantics.

## Executable accepted recipe

`tests/frontends/generate.py` generates `type_parameter` and `named_widths`
copies from the real FIFO/CSR/statistics sources. Use `type_parameter` where
parameter-dependent named records improve readability: ANSI vector ports with
record-derived default type parameters declared before use, fixed shared package
imports, and guarded scalar/index widths. `make representation-formal` additionally
changes the FIFO storage element to `beat_t`, retaining its full width and
bitwise behavior. Both depth-2/depth-4 FIFO proofs/covers and CSR proof/cover/
mutation pass on those copies; `make fifo-mapping` includes every payload bit.
`make frontends` checks all six profiles, invalid contracts and two heterogeneous
instances. Rerun these commands on the converted registered production sources.

Keep the explicit symbolic-input harness adapter. Native `read_verilog` still
fails the richer forms and mislowers the minimized record-array fixture; it is
a diagnostic control, not a portability veto. No parameterized packages or
forward-referenced typedefs are part of the recipe. Source-relative filenames
containing whitespace remain unqualified by the current Yosys command adapter.
