# Composed queue/control timing criteria

PR #32 merged at `523f1a025aa37c60b813408ee0884ef3d5a406dd`; its
head was `a188957a7ff716f32c94ec3a4bc92f81ed102443`.
The branch starts from the same revision on `origin/main` after the
[full main workflow](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/44901160895)
passed. The entry doctor passed before measurement. Keep the source/configuration identities and run manifests with the
results. The versioned [prior evidence](../../docs/results/TM04-control-timing.json)
records the Liberty, tool locks, reference SDC, ABC script and mapping recipe
digests. Preserve the original fixture source for matched maps.

## Entry sources

| Path in the entry tree | SHA-256 |
| --- | --- |
| `experiments/queue-control/admission.sv` | `50420c10f3df908c4e1d9059f92f99dac7b94c8738e96f64d087268f625477f7` |
| `experiments/queue-control/queue_head.sv` | `54978c349bb25f63067730d4097364a294766502d4ec0289ca8656b0f037ce15` |
| `experiments/queue-control/cell_control.sv` | `4793845afad252cd22e78772a7e3a9b35702fe3003201fe687667fd9f9fdc2fb` |
| `tools/queue_control_sta.py` | `b6518983bd3b0cb45ab9b16934c80ed5886644d8748e2f750b894c1f1896fdb6` |
| `tools/queue_control.py` | `e85ab661c9d08c48529cc2aae40fb615dc263457363db27d62cbadcbb44f3649` |
| `tools/queue_control_directed.py` | `547335b2bb71f64f19601137639548e790562d85c449c9f0e1f27f0943762cee` |

The three fixture digests match the historical mapped sources. The earlier
map source commits are `e40a1b9def8fcddb387156e7252162fd5aa09c3c`
(admission), `401209ac85c9167fb458c9663c257237e7c62dd1` (head),
and `045ae4a70efdc246e3d0033137d5b39430eea127` (cell). Use the
new runner manifest as the tested identity.

## Measurement matrix

| Point | Primary / small parameters | Live timing paths |
| --- | --- | --- |
| `admission-balanced-rx` | Balanced prefix, RX framing and selectable static/dynamic plus DROP/WAIT | Old credit, held credits and header/configuration through first-service grant/reject/abort, and return feedback through descriptor and queue-credit update |
| `head-token-feedback` | Same-edge cached refill and registered token feedback | Published/old-successor cache fill, old queue and port balance compare through registered binding, debit and refill |
| `cell-cleanup-feedback` | Dedicated registered abort cursor and independent TX and abort links | TX and abort lookup through cursor/pool, returns through next-edge eligibility, reset-to-write |
| Connected control | Registered RX owner, publication, TX slots, outstanding credit and cleanup | First service and credit loop, cache and binding feedback, TX issue/accept and abort return to both pools |

Use primary 4×4/1,024 cells/256 descriptors/1,536 bytes and small
2×2/16 cells/8 descriptors/192 bytes. Exercise read latencies one and two.
Map both profiles with the [short ABC recipe](abc-short.script) and the
[reference SDC](reference.sdc). Use Nangate45 typical at 1.10 V and 25 °C
(`8d540a4d4cf6d09d27c87ad067857a9c0c2eeb023ab7a56e058cd3113db4e9b1`),
the ideal 10 ns rising clock, 0.10 ns uncertainty, 0.2/2.0 ns data min/max
I/O, 0.05 ns slew and 10 fF load. Keep mapped consumer widths and loads.
Compare global and focused max/min delay, slew, capacitance, fanout,
sequential state and area. Check actual endpoint groups, plus supported
electrical constraints with zero residual violations. Record a missing
limit or endpoint explicitly. Keep isolated repair baselines separate.

Preserve the original 0.20/2.00 ns reset reference, including the historical
−0.14368 ns removal and 0.34368–9.36461 ns primary window. The external reset
coordinator owns release relative to the core clock. Its implementation and
distribution are unspecified. Recompute each ideal-root limit from recovery,
removal and reset-to-write where applicable, at the fixed 0.05 ns slew.
Sweep 0.20 ns, ideal half-cycle 5.00 ns, and 9.99 ns as clearly labeled
deterministic arrival references. Use both min and max for each sample,
without changing data constraints. Verify which timing check fails or
passes at each endpoint. A falling-phase model is an analytical reference
only. Integration must provide a justified launch, root slew and distribution
envelope before physical reset closure.

Accept a mapped buffer edit only after showing all affected sink and output
functions are unchanged and the same mapped sequential cell interfaces are
live. A before/after connectivity proof may contract only added buffer cells
whose locked Liberty functions are unary identity. Qualify the proof with
a wrong sink on a disposable candidate. Qualify endpoint validation with
an intentionally omitted required group. Report process status separately
from timing/electrical acceptance. Preserve the first unexpected failure
with its source, replay input and output before changing it.

## Edge witnesses

| Witness | Trigger and independent expected result | Neighbor and detection |
| --- | --- | --- |
| Descriptor scarcity | Four primary headers rotate from ingress 1 with one pre-free descriptor and a simultaneous old-owner return. Only ingress 1 grants the old ID, with next-edge return visibility. | DROP consumes rejects. WAIT retains pending heads. Detect a return-ID bypass. |
| Dynamic threshold | Old U=10, zero minima and H, n=2, alpha=64. Reserve and service at threshold 2. Old U=9 computes threshold 1 and temporarily fails. | Compare DROP with WAIT. Cross malformed first service with a legal old-owner release. Detect missing/reordered service and incorrect credit merge. |
| Cached replacement | Publish B while dispatching singleton A. Bind A, cache B after the edge. | Empty append cannot bind on publish. Longer queue follows old successor. Detect early or lost publication. |
| Late strict binding | Cross active 17 to 16 remaining beats. Strict eligible head published on previous edge wins. Publication on binding edge leaves already chosen successor bound. | Stall both slots and verify no replacement or repeated debit. |
| Dual tokens | A 65-byte head facing 64.75 bytes plus 0.5 refill is ineligible that edge; 65 bytes fits and charges exactly once before refill. | Limit queue and port separately and together. Detect post-refill eligibility or repeat charge. |
| Full read credit | Six occupied-plus-outstanding slots, response, accepted retirement and legal issue to different egress. Full egress cannot issue against the old count. | With final beat stalled credit stays full; response is eligible at issue + L + 1. Detect early issue or transfer. |
| Five returns and reset | Hold four TX final beats until an independent final cleanup and release all together. Expect distinct ownership on five lanes, one merged credit update, old-free selection and returned IDs eligible next edge. Reset with issued work. | Stall a final beat or delay cleanup. Check full pool restart and reject a physically arriving stale epoch. Detect a dropped cleanup lane or stale response effects. |

Replay the existing RTL comparators and directed model at both profiles.
Use seed 104729 for admission and per-ingress seeds 104729 + ingress ID
for supplemental independent lengths. Require all eight primary balanced
permutation windows after 2,048 warm-up edges to accept and deliver 9,216
beats at each port and drain with all frames and resources accounted for.
Repeat the independent lengths and small mixed case. Preserve timestamped
handoffs and any bubbles or losses. A change to ownership or edge latency
needs explicit attribution and workload comparison before adoption.

Keep same-edge admission and cached heads as candidates. Treat missing
DRR, shaping, serializer, payload, bus or distribution logic as an explicit
boundary with timing consequences. Keep the freeze gate open for a failed
or unmeasured required path, an unresolved reset source, or a missed
performance gate. Production RTL and independent qualification have their
own entry criteria.
