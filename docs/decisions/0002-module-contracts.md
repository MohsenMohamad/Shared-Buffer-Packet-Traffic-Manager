# Packed portable contracts and atomic ownership

G1 uses common parameter headers, module-local packed record types and packed
lane vectors in production declarations. Verilator 5.054 and pinned Yosys
`read_verilog -sv` consume identical sources. Parameterized packages/interfaces
and unpacked ports would add unsupported frontend dependencies. Yosys does not
accept `$bits(type)` in these port widths; explicit shared width constants are
checked against `$bits(typed_signal)` during elaboration instead. The contracts
suite qualifies this representation before component tasks depend on it.

Module APIs are deliberately named `_api` and contain no assignments. The
external tm_top is also declaration-only. A generated elaboration harness
instantiates every API with the selected production parameters; it is never a
functional DUT, formal proof or mapped implementation. Subsequent components
replace declarations, retaining signatures and their normative timing.

Accounting owns U/R/A/H, pools own bitmaps/free counts, queue control owns
head/tail/count, scheduler owns deficit/visit state, and statistics owns live/
shadow counters. Top composes queries and arbitrates TX over abort cell returns.
All legality uses pre-state, with one atomic merged update per owner. In
particular, two descriptor returns do not provide bypass allocation credit.
Invalid returns set the invariant error without inflating capacity; duplicate
returns count once. These choices implement the existing resource invariants.

Descriptor-info writes occur once at admission, using first-cell bypass data;
a malformed first beat may leave unused head information because it never
publishes. Metadata uses explicit register-array mux ports (including N_Q head
info reads and two cell-next reads). Publication and dispatch are nonblocking
single-edge actions with legality guaranteed by reservation/pre-state checks.
Scheduler visit closure uses the merged post-dispatch queue count. These choices
resolve previously unspecified internal wiring without changing packet/CSR
semantics. A lower-port metadata design requires a documented API revision.

Independent monitors report explicit idle or active samples into a clock barrier.
Only a sealed complete batch advances reference state. Exhaustive callback-order
examples cover conservative admission and queue replacement. This preserves
verification.md's independence contract without claiming the complete P07 model.
