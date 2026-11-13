# Prepared FP-TX boundary

`memory_tx_obligations.sv` compiles and executes only on labeled public-action
replay during preparation. It is not registered as a production proof and no
production prove/cover/mutation result exists. `sample_enable` gates the finite
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
