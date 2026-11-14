# Prepared FP-TX boundary

`memory_tx_obligations.sv` compiles and executes only on labeled public-action
replay during preparation. It is not registered as a production proof; its
preparation results establish no production prove/cover/mutation result.
The separate production binding and its scope are described below. `sample_enable` gates the finite
replay capture window; a production binding must tie it high, never assume it
low to hide work. All arbitrary inputs are explicit ports; there are no native
anyconst/anyseq constructs. Fixed future packet/byte witnesses must use the
F01 history/stability recipe across all resets.

Safety permits arbitrary sink readiness and assumes only the published reset,
legal dispatch/ownership and fixed 1/2-cycle RAM boundary. Assertions check the
response due pipeline, issued-minus-retired reservation, response-minus-retired
arrival count, final keep/last and exact cell/descriptor completion. The separate
observed-write oracle checks bytes, metadata, fragmented physical identity,
link capture and epochs. Covers describe pending/full/exchange/final-hold and
restoration; replay cover counters do not establish formal reachability.

Future reduced production safety: two queues/four descriptors/eight cells as
separately named formal knobs, both latencies, supported cell words, depth 4/8.
Bind actual production sources without a behavioral TX replacement. Prove
credit, order, held output, exact retirement and no read after reuse unboundedly;
check covers and intended outstanding-credit/early-retirement mutations. Keep
payload abstractions and legal metadata assumptions explicit and discharge
caller ownership in composition. The current simulation obligation module does
not by itself prove no stale payload, link capture or physical uniqueness.

Progress is separate: add an explicit bounded-stall or always-ready sink and
RUN/initialized/committed input premises. Check first valid <= L+4 and one beat
per cycle after fill, including cell boundaries for CELL_WORDS>=2. Do not import
those assumptions into safety or report bounded progress as unbounded safety.
See [frozen expectations](../../dv/memory_tx/contract.md) for the risk/cover map.

## Production candidate binding

The `memory-tx` formal selection now binds `tx_formal.sv` to the named production
`tm_tx_api`; replay obligations above remain preparation evidence only. Safety
uses SMTBMC/Z3 k-induction with the pinned Slang frontend. Covers and intentional
source-copy counterexamples use SMTBMC/Z3 too. Earlier ABC/PDR preprocessing
experiments are retained as non-success; they establish no property result. Only an actual completed prove status establishes
unbounded safety; timeouts, UNKNOWN and cover/replay PASS do not.

The production-supported formal dimensions are N_RX=1, N_Q=2, N_CELL=16,
N_DESC=8, CELL_BYTES=16 and MAX_PACKET_BYTES=128. Latency 1/2 crosses depth 4/8.
An arbitrary eight-cell permutation is captured at each accepted dispatch. It
is a committed-chain environment knob, not a claim that the production module
elaborates at eight physical cells. All stimuli use F01 explicit input ports;
the chain may change for every packet. No global chain-stability assumption remains.

| Environment contract | Excluded behavior and nonvacuity |
| --- | --- |
| Two startup reset samples; arbitrary later resets, including short later resets | New dispatch waits through initialization. Pending-reset and same-ID/tag restart covers remain required. |
| Legal idle-only dispatch, every length 1..128, arbitrary descriptor/tag/qid | Excludes busy dispatch and malformed descriptors outside the TX API contract; no packet size is selected from DUT state. |
| A fresh arbitrary eight-cell permutation on each accepted dispatch | Allows every legal chain prefix and changing chains across ID/tag reuse. Only non-tail owned links are immutable; tail and returned links are arbitrary. A prefix can always extend to eight distinct IDs in the sixteen-cell configuration. This is a local ownership contract, not a caller/pool composition proof. |
| Arbitrary 64-bit word sampled at each read, exact unreset physical response pipeline | No response backpressure or reset cancellation is assumed. Payload memory structure/byte readback is independently exercised in simulation. |
| Sink readiness is an unconstrained input | Safety has no fairness, maximum-stall or always-ready assumption. Performance simulation names its readiness boundary separately. |

The checker counts issue, live arrival and external retirement independently.
FIFO/pending-tag/cursor correspondence, valid ranges and returned-ID masks are
asserted helper invariants, not assumptions. Assertions cover credit, arrival
space, held fields, ordered address/metadata/keep/last, exact cell/descriptor
retirement, no read after return, tail handling and reset validity.

Required covers include full credit with pending responses, pending sink stall,
full response/issue/retirement exchange, final-beat hold, pending reset, returned
link alteration, completion and same-ID/tag reuse after a pending reset. Covers
are reached separately from proofs. Omitted outstanding credit, premature cell
return and stale-response validity mutations are disposable production-source
copies; each must hit its named independent detector. Simulation additionally
requires a normally exiting server and a passing legal neighbor.
