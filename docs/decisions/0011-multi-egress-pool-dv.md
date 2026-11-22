# Multi-egress pool verification boundary

The pool checker derives eligibility from live ownership and pre-edge capacity. It accepts any unique free address or descriptor and treats grants and service choices as inputs. Admission decisions, queue order, arbitration, framing, and memory response timing have their own composed checks.

## Frozen expectations

- A descriptor grant consumes one distinct old free ID and its full reservation from the shrinking credit prefix. A returned ID and credit become usable on the following edge.
- A write consumes one physically free old ID and one reserved cell of the named RX frame. Unreserved credit can be zero. Publication follows the final write by one edge. Dispatch and retirement use earlier owned state.
- TX cell retirement consumes assigned ownership and releases one unit of reservation. A physical abort reclaim consumes assigned ownership and leaves the reservation unchanged. Cleanup releases the remaining reservation and descriptor once after all physical cells have returned.
- The checker keys each cell by address and each frame by descriptor and full owner identity. Epoch and ingress sequence distinguish frames with identical tags, including frames that reuse IDs after reset.
- Sample observations at the rising edge with all lanes and presence bits. Compare reported per-queue and global counts against ownership after every eligible batch. Require full capacities and empty maps after drain.

The coverage plan defines the count, old occupancy and source crosses, reasoned exclusions, directed triggers, named negative checks and randomized subset obligations. Isolated pool preconditions can align a staged write, multiple TX finals and abort service. Composed RTL must establish those alignments with real ingress, queue, TX and memory interfaces. [Coverage plan](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/blob/b67c593a94aa2c577e8af25c64ee3855abadfaf3/dv/multi_egress_pools/coverage_plan.py)

## Source identity

The branch starts at `4d6940fda61e44b3c73cd4962a0c4d1857889e61`, the merge of PR #33. Main passed the repository checks and full CI summary before branch creation. [Exact main CI run](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/44990236495)

The allowlist governs the source projection. The baseline doctor ran against a separate Git repository of those public inputs and the locked tool installation. Repository-wide Markdown readers would load feasibility and author reports. Repository-wide syntax checks and test discovery would load retained DV and unlisted tooling. These checks are deferred to hosted repository CI. Preparation uses scoped builds and provenance. [Baseline allowlist](../../verification/multi-egress-pools/baseline-allowlist.txt)

Primary and small use the public behavior and edge ABI. P02 supplies local resource risks. The widened contract governs lane counts, cleanup independence, allocation boundaries and owner identity. [Behavior](../spec/multi-egress-traffic-manager.md) · [ABI](../spec/multi-egress-interfaces.md) · [P02 task](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/blob/4634d5a4dacb00304635ddb64a3f83747d8b03e8/docs/implementation/tasks/P02-storage-primitives.md)
