# Packed portable contracts and atomic ownership

Historical representation decision, superseded by [0006](0006-modern-toolchain.md)
and [0007](0007-rtl-representation.md). At original G1, the native frontend used
module-local typedefs, non-ANSI ports and explicit width sums. Its wildcard-import,
`$bits(type)` and unpacked-port restrictions explained those choices at that
revision; they are not current language or design prohibitions. Current
production uses ANSI declarations, a fixed shared package and scoped dependent
types. The original G1 evidence remains historical, with no changed API,
ownership, lane ordering or timing contract.

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
