# A01: Allocator selection evaluation and reviewed disposition

## Objective and entry

Act on the [established scaling result](../../results/allocator-scaling.md) before
P08. Dependencies: the merged P02 characterization and [R01](R01-reset-timing.md).
Do not repeat characterization simply to reproduce its already recorded numbers.

The current P01 module contract specifies the lowest **pre-state** free ID.
The broader buffer-management contract requires a valid free ID, and no recorded
comparison establishes that numeric ordering is necessary. A01 owns reviewing
that policy instead of treating it as an immutable product requirement.
Uniqueness, conservation, valid selection, exact return handling and the required
API bandwidth remain correctness obligations under every candidate.

## Work

1. Trace whether any real consumer needs numeric ID order, rather than inferring
   need from tests written for the old implementation. Review the current P01
   wording explicitly. If numeric ordering has no functional justification,
   propose an any-valid-free-ID contract and update specifications, checkers and
   properties together in a reviewable policy commit before adopting a candidate.
   Preserve no-return-bypass and query/action timing unless a separate explicit
   latency/interface decision is justified. Do not silently drop a failing property.
2. Commit the baseline identity, candidate structures, equal capacities including
   1024, constraint/library inputs and decision rules before measuring candidates.
   Preserve the original exploratory 6 ns F0 selection screen as a screen, not a
   newly invented F0 acceptance requirement. Define how area, delay, fanout,
   state and latency tradeoffs decide the disposition.
3. Isolate semantic contract checks from implementation correspondence. Use an
   independent live-ID model driven by API actions to check free selection,
   availability, counts, invalid/duplicate returns, sticky errors and atomic
   updates. Keep policy-specific ID-order tests separate from universal safety.
   Under the current contract retain lowest-ID checks; under a reviewed relaxed
   contract replace them with the justified policy checks while preserving all
   ownership/capacity/return negatives. Do not copy a selector into the oracle.
4. Compare the real production bitmap/pool with a balanced/hierarchical selector
   and a bounded free-list alternative when the reviewed contract permits it.
   Measure reset initialization/readiness, simultaneous one/two returns, allocation
   rate, memory ports, duplicate detection and added state as well as delay/area.
   No ideal FIFO with invented ports or hidden refill latency is a valid comparison.
   Keep guarded widths, pre-state legality and required output cones live; do not
   substitute an encoder-only surrogate for the wrapper.
5. Qualify any adopted implementation with affected simulation, unbounded local
   proofs, covers and intended defects. Supplement with equivalence where useful;
   equivalence alone does not establish the contract. Bit-exact ID equivalence is
   not an appropriate acceptance criterion after a reviewed ID-policy change;
   verify the permitted behavior and unchanged packet/resource contract instead.
   Consume R01 for reset timing
   and report data setup/hold separately from recovery/removal/fanout.
6. Adopt a clearly justified correct implementation under the reviewed contract or retain the
   baseline with a concrete reviewed reason. Preserve rejected-candidate evidence
   and update the current source/selection decision without rewriting history.
   If every candidate misses a screen, state the unresolved performance risk and
   reviewed disposition. No automatic policy change or claim of F0 closure follows.
7. Assign P08 the real selected-ID-to-admission/accounting/metadata consumer-path
   recheck at I0 and 1024 cells. This isolated comparison is not an integrated
   timing bound.

## Completion

A reviewed policy decision and measured disposition exist, implementation-independent pool safety
remains checked, and any selected production change has affected correctness
evidence. A01 must finish before P08; P03/P04/P05 can proceed independently.
