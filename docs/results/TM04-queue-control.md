# Multi-egress queue and control feasibility

**The primary traffic target passes in the finite model. Keep the control
freeze gate open.** Both direct and cached heads sustain 9,216 accepted and
9,216 delivered beats per port per primary window at either memory latency.
The primary serial admission prefix violates the 10 ns setup target. Reset
removal under the precommitted reference delay also violates the timing
budget. The [decision](../decisions/0010-multi-egress-queue-control.md)
identifies the evidence still needed before freezing the architecture.

## Cycle and resource behavior

The [definition](../../experiments/queue-control/README.md) was committed before
measurement. The [model](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/blob/a5a3f6533295f2c02f2cc26c116a3e9f8e8f3f5e/tools/queue_control.py) implements explicit
descriptor and cell IDs, identity and ownership, separate physical and
unreserved free pools, per-queue held credit, queue head/tail/link state and
the post-write publication slot. It consumes pre-edge capture and output
slots, tokens, requests and physical eligibility. Only grants from preceding
headers modify a later lane's prefix view. The conservation checks reconstruct
both cell equations and, in directed traces, independently recount ownership
per queue. One ordered disposition becomes visible on a subsequent edge.

| Boundary | Producer and consumer |
| --- | --- |
| Publication and dispatch | Final staged writes load one slot. The old slot publishes on the next edge. A previously empty queue becomes selectable one edge later. Each egress binds from the old head. A longer queue uses the old successor before append, and singleton replacement forwards the publication into head and tail. |
| Cached-head refill | Each queue holds one primary 116-bit or small 109-bit head record. Up to one old successor per egress reads the finite descriptor store. Refill and publication bypass complete on the pop edge. Head records can be consumed on successive edges on the same queue. |
| Physical allocation and return | The staged write arbiter drives pre-edge bitmap selection and the physical address sampler. TX and abort cursors each capture an independent old cell link. An earlier staged write can finish on an abort-marking edge. The newly marked abort becomes eligible only after that edge. |
| Reservation | A rotated batch selects distinct old-free descriptor IDs. The widened dynamic comparison uses the after-prefix, after-candidate shared remainder. All release deltas merge after the batch, including the dedicated cleanup lane. |
| Read, response and retirement | Bound active/next contexts feed one RR issue per edge. A pre-edge free slot is required. A fixed response commits its existing credit at issue plus latency. TX can use it at the next edge and returns the cell only on accepted cell-final. Reset flushes ownership and ignores stale-epoch responses. |

The primary descriptor store holds 29,696 metadata bits plus 2,048 queue-link
bits, compared with 872 and 24 in the small profile. The cached version adds
1,856 or 872 bits. The combined primary per-cell link and descriptor-owner
arrays hold 18,432 bits, compared with 112 small-profile bits. Those arrays
are register stores with combinational muxes. The direct head path looks up
length at every eligible class head and reads other fields only for the
selected head on each egress. Cache refill uses one successor address per
egress. A single append-link write is shared. Valid live link lookups and
writes address disjoint links, and empty/singleton consumers ignore stale
uninitialized links. Payload is external to the experiment. Its 524,288
primary or 8,192 small SRAM bits require independent 512-bit read and write
ports and the fixed one- or two-edge response.

## Directed witnesses and intended detections

The [directed runner](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/blob/a5a3f6533295f2c02f2cc26c116a3e9f8e8f3f5e/tools/queue_control_directed.py) uses independent
pre-edge fixtures and literal expected transition checks. It reports each
trigger, comparison and observed trace. All 336 rows pass, covering 28 cases
per profile, metadata organization and latency. The 48 intended detections
use legal neighbors and individually altered observations for early
publication selection, same-edge returned-ID bypass, loss of the cleanup
return lane and early first-beat handoff.

The rotated one-ID case grants the old free ID to ingress 1 and preserves
WAIT heads. The return can be granted beginning on the next edge. The
four-grant case combines a staged write with four TX returns. A separate
case aligns four packet finals with the independent last abort reclaim and
checks all five cell and descriptor IDs, owners and widened credit deltas.
An ingress awaiting cleanup cannot offer a new eligible header on the final
cleanup edge. The three-cell contested abort case completes at its last
allowed RR arbitration edge, with a neighboring case adding coincident TX
cell returns. Under continuous eligibility and one grant per edge, at most
four arbitration edges separate grants, giving the primary cleanup bound
of `4*max(1,k)` edges including zero-cell cleanup.

The dual-bucket witness requires 65 bytes before binding. At 64.75 bytes,
a 0.5-byte same-edge refill can first enable binding on the next edge.
An open DRR visit resumes with its saved deficit after that wait. The
late-strict cases bracket the 17-to-16-beat boundary and keep the chosen
successor bound under stall. The small profile can fill six slots with
two three-cell frames, which uses all cells in both bound frames. Only the
primary geometry can additionally have an unread seventh cell. Both
profiles exercise simultaneous response, retirement, independent issue and
distinct-address write under the six-slot boundary.

Verilator compares both admission variants on each sampled edge at both
sizes, including rotated scarcity, static and dynamic DROP/WAIT, α thresholds
and randomized offers and returns. A separate fixture compares direct/cached
queue overlap and drives allocation and the two cell-link consumers. These
are analysis fixtures with separate sources. They establish scoped behavior
of the measured logic through the exposed endpoints.

## Traffic replay

Every run uses 2,048 warm-up and 9,216 measurement edges with four staging
cells and six prefetch slots. All runs finish previously offered frames,
drain and reconcile physical IDs, cells, reservation credit and descriptor
ownership. [Measured data](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/blob/4634d5a4dacb00304635ddb64a3f83747d8b03e8/docs/results/TM04-queue-control.json) gives per-port beats,
bytes, frames, outcomes, idle/blocked edges, maxima and final ownership
through drain.

| Profile and organization | Balanced RX and TX result |
| --- | --- |
| Primary direct and cached | Repeated 60, 65, 1,536 and the specified mixture each deliver and accept 9,216 beats per port at L=1 and L=2, with zero loss or stalls. |
| Primary cached plus registered request | All eight windows reach 9,216 in both directions. This variant delays first read eligibility from binding + 1 to binding + 2. Publication, pop, token debit and TX ownership keep their prior edges. |
| Small direct and cached | Repeated 60, 65, 192 and the small legal mixture each reach 9,216 in both directions at L=1 and L=2. |
| Small cached plus registered request | Seven windows reach 9,216 in both directions. At L=2 the mixture accepts 9,216 per input, delivers 9,216/8,478, and rejects 81 ingress-0 frames for descriptor scarcity in the window, 99 through drain. |

The primary fixed permutation is `(ingress+1) mod 4`, class 0, packet RR,
ready sinks and no shaping. The primary mixture is
`60,65,1536,64,129,1518,61,513`. The small diagnostic mixture is
`60,65,192,64,129,190,61,113`. The small independent replay substitutes a
192-byte frame for 1,536 bytes and uses the smaller pool. Its DROP losses
and reduced rate are diagnostic.

The independent-length reference and both zero-extra-cycle primary
organizations reproduce one L=1 and two L=2 ready-but-idle edges, zero input
stalls and zero frame loss. All missing frames in this table are 1,536 bytes.
In each row the first cell becomes visible one edge after the predecessor's
next-beat deadline. Egress 0 at L=2 also loses one arbitration edge between
request and issue. The other two issue on their first eligible edge, so
read bandwidth or a deeper prefetch store alone cannot advance them.
The registered request replay changes the boundary timing and raises the
L=1 count to two, with two again at L=2.

| Latency / egress | Last preceding beat / idle | Final write / publish / bind | Request / issue / response | Eligible / accepted |
| --- | --- | --- | --- | --- |
| 1 / 1 | 3816 / 3817 | 3813 / 3814 / 3815 | 3816 / 3816 / 3817 | 3818 / 3818 |
| 2 / 0 | 3432 / 3433 | 3427 / 3428 / 3429 | 3430 / 3431 / 3433 | 3434 / 3434 |
| 2 / 1 | 3817 / 3818 | 3813 / 3814 / 3815 | 3816 / 3816 / 3818 | 3819 / 3819 |

The bounded stall lets egress 0 deliver 8,064 beats while all other primary
ports deliver 9,216. Incast DROP preserves 9,216 delivered beats on egress 0
and rejects short frames on descriptor scarcity or long frames on cell credit.
Incast WAIT retains headers and accepts 2,304 beats per input in the window
without loss. Synchronized return witnesses and replay reach four TX returns.
Cleanup traffic completes each malformed frame and independently serves the
two unaffected egresses at full rate. The concrete error beat has one missing keep bit, so the abstract and
concrete capture-byte counts differ on that beat. Pool pressure explains the
small DROP losses. For example, the small direct independent replay at L=2
has 16/12 cell-credit and 36/21 descriptor rejects in the window. The
synchronized small return hold exhausts descriptors during warm-up and
causes four rejects per ingress through drain.

## Mapping and timing

The timing study uses the pinned Slang frontend and Yosys/ABC mapping logic,
Nangate45 typical at 1.10 V and 25 °C, ideal 10 ns clock, 0.10 ns uncertainty,
0.2/2.0 ns data I/O delays, 0.05 ns slew and 10 fF per output. Reset has a
separate rising deassertion envelope relative to the rising launch edge. A
falling assertion is asynchronous. This budget is a reference stimulus,
and the envelope required of a future source is derived from measured slack.
The [scoped SDC](../../experiments/queue-control/reference.sdc) precedes the
measurements. The expected omitted-reset-input case is rejected by OpenSTA
constraint coverage.

The queue endpoint is the binding register that captures selected frame
identity and payload cursor. The cell endpoints stand in for the payload
address sampler, TX issue and cleanup cursor register. Admission captures
receive grant, ID, abort and release accounting in registers. Reports retain
setup and hold, asynchronous recovery/removal, reset-to-write setup/hold when
present, required reset envelope, state/endpoint counts, sequential and
combinational area, and mapped fanout by clock, reset and data.

| Profile | Cone | ABC script | Sequential / combinational area (µm²) | Setup / hold (ns) | Recovery / removal (ns) | Max reset / data fanout |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| small | head-direct | default | 5,599.83 / 8,518.92 | +6.68351 / +0.01623 | +7.94904 / -0.14368 | 291 / 10 |
| small | head-cached | default | 9,543.02 / 11,011.07 | +6.68543 / +0.00397 | +7.94904 / -0.14368 | 291 / 10 |
| small | cell | default | 756.50 / 1,347.56 | +7.31122 / +0.01964 | +7.93947 / -0.14368 | 48 / 10 |
| small | admission | default | 484.12 / 5,797.47 | +1.28133 / +0.03455 | +7.93947 / -0.14368 | 91 / 10 |
| small | admission-lookahead | default | 484.12 / 6,472.58 | +3.11391 / +0.03449 | +7.93947 / -0.14368 | 91 / 10 |
| small | admission | short | 484.12 / 9,340.59 | -0.43367 / +0.03629 | +7.93947 / -0.14368 | 91 / 10 |
| small | admission-lookahead | short | 484.12 / 9,532.91 | +1.67972 / +0.03629 | +7.93947 / -0.14368 | 91 / 10 |
| primary | head-direct | default | 147,743.85 / 426,143.97 | +6.38463 / +0.00499 | +7.94904 / -0.14368 | 789 / 10 |
| primary | head-cached | default | 156,136.68 / 303,387.63 | +6.22553 / +0.00397 | +7.94904 / -0.14368 | 789 / 10 |
| primary | cell | default | 89,148.30 / 176,272.08 | +6.51561 / +0.00732 | +7.93947 / -0.14368 | 1091 / 10 |
| primary | admission | default | 3,011.12 / 42,986.93 | -10.87996 / +0.06034 | +7.93947 / -0.14368 | 566 / 10 |
| primary | admission | short | 3,011.12 / 86,719.99 | -14.70553 / +0.04244 | +7.93947 / -0.14368 | 566 / 10 |
| primary | admission-lookahead | short | 3,011.12 / 97,524.91 | -4.56895 / +0.04507 | +7.93947 / -0.14368 | 566 / 10 |Both default head organizations and the cell-control cones meet the scoped
data setup and hold checks. The cached primary head cone uses 19.9% less
mapped area than the direct primary cone. The primary cache and cell
cones still exceed Liberty capacitance by 0.03693 fF and 4.96770 fF at
their worst pins. Typical low-margin data hold is +0.00397 ns in the
primary cache, +0.00499 ns in the direct head, and +0.00732 ns in cell
control. Inspect the endpoint and fanout data in the [measurements](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/blob/4634d5a4dacb00304635ddb64a3f83747d8b03e8/docs/results/TM04-queue-control.json).

The default primary serial prefix misses data setup by 10.87996 ns from
`minimum[1]` to `_72559_/D`. With admission mode fixed on the same
mapped netlist, static setup is −1.35056 ns and dynamic setup is
−10.87912 ns. The matched short-script comparison improves primary
setup from −14.70553 ns to −4.56895 ns with the lookahead prefix.
Total area grows from 89,731.11 to 100,536.03 µm², and the lookahead
point also exceeds max capacitance by 7.07420 fF. The redundant default ABC
run for the primary lookahead was stopped after more than 20 minutes
without a netlist, after the matched short-script comparison completed. With its mode fixed,
static setup has +0.44205 ns and dynamic setup has −4.56895 ns. This
supports further work on the dynamic computation and merged state
feedback within the same edge. Lookahead selects the precomputed result
for the actual earlier-grant subset and adds no register to the prefix.
The sampled RTL comparison therefore uses the same admission edges as
the direct/cached model.

The reference `rst_n` release has −0.14368 ns removal slack at every
reported point. Its observed recovery slack is at least +7.93947 ns.
At 0.05 ns input slew and ideal distribution, the required root release
window across the default-mapped cones is 0.34368–9.44830 ns after launch,
including the primary cell write gate. The short mapping moves the latest
required arrival across the measured cones to 9.37792 ns. The
reference earliest arrival of 0.2 ns violates this envelope. Recovery
and removal coverage, graph reset fanout and the write-gate paths appear
separately in the measurements. A characterized reset source and physical
distribution are needed for closure.

All summarized netlists pass the Yosys mapped check and the OpenSTA
constraint coverage check. Expected state counts, measured flop counts,
and driven consumer bits agree. The Liberty reports support slew and
capacitance checks. The netlist fanout counts come from connected sink
pins.

The isolated mapped cones cover packet-RR selection and length eligibility
from externally supplied pre-edge token balances/binding opportunity.
They take already-resolved framing, publish metadata, receive staging,
credit release and cursor requests. Full DRR, strict selection, token
refill and debit, ECN qualification, response tags and assembler are
exercised at the model boundary or excluded from timing. Full counter/CSR,
packet bytes, payload memory and cross-cone composition are outside the
measurement. Build-success, nonnegative single-corner data slack and passing
directed model cases leave the integration gates open.

## Reproduction and provenance

Run the original model commands below at
`a5a3f6533295f2c02f2cc26c116a3e9f8e8f3f5e`. Those commands are archived
model-only results. Use the RTL and timing revisions in the table for the
corresponding native commands.

| Scope | Tested revision |
| --- | --- |
| Clean fetched `origin/main`, PR #30 merge, doctor and entry declaration gate | `a00af49c2e89299d2b05ca1426ad823b1c80be69` |
| Premeasurement definition | `fd31ff6f2bc01dcc8b4fc9982738a5ae5274305d` |
| Original study gate, 132 concrete workloads and directed witnesses | `a5a3f6533295f2c02f2cc26c116a3e9f8e8f3f5e` |
| Register-array queue/cell synthesis sources | `71a7afbc5e380471cec5de8574706d62486b7ef8` |
| Serial reference map and admission RTL fixture | `0996ea10a5c0b53c00e61f6ec84c91d5933c0d22` |
| Metadata RTL fixtures and final declaration gate | `546fe6b611d564d92273fd3d2f35d214c3e4e214` |

The [machine-readable evidence](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/blob/4634d5a4dacb00304635ddb64a3f83747d8b03e8/docs/results/TM04-queue-control.json) gives each map
and STA revision, script and netlist SHA-256, exact lock and Liberty
identities, case-analysis artifacts, source digests and drain results.
The later STA/sensitivity runs marked dirty had in-progress report text
in the working tree. Mapped RTL and constraint inputs match their recorded
commits. The model uses Python 3.12.14. The native tests and STA use the
qualified repository installation.

```sh
mkdir -p .build/queue-control
export CXX=g++-14
source .tools/activate.sh
make doctor
make multi-egress-declarations
python3 tools/multi_egress_feasibility.py --expect-gate
python3 tools/queue_control_directed.py --json .build/queue-control/directed.json
for p in primary small; do
  for variant in direct cached registered-request; do
    python3 tools/queue_control.py --profile "$p" --variant "$variant" \
      --json ".build/queue-control/$p-$variant.json"
  done
done
python3 tools/queue_control_sta.py --output .build/queue-control/mapped --jobs 2
python3 tools/queue_control_sta.py --output .build/queue-control/short-admission \
  --point admission-lookahead --short-abc
python3 tools/queue_control_sta.py --output .build/queue-control/short-serial \
  --point admission --short-abc
make repo-check
python3 tools/check_light.py
git diff --check
git diff --check origin/main...HEAD
```

Run the supplemental abstract probe with the same uniform choices and one
PRNG per ingress.

```sh
PYTHONPATH=tools python3 - <<'PYCODE'
import random
from multi_egress_feasibility import Frame, Study
from queue_control import RANDOM_LENGTHS

class Independent(Study):
    def __init__(self, latency):
        super().__init__("independent", 0, latency, 4, 6)
        self.rng = [random.Random(104729 + port) for port in range(4)]

    def make_frame(self, port):
        return Frame(port, (port + 1) % 4, 0, self.rng[port].choice(RANDOM_LENGTHS))

for latency in (1, 2):
    Independent(latency).run()
PYCODE
```

To reproduce the RTL fixture runs after activating the
toolchain, use the same elaboration settings as the model profiles.

```sh
for profile in primary small; do
  case "$profile" in
    primary) p=4 cells=1024 desc=256 max_bytes=1536 ;;
    small) p=2 cells=16 desc=8 max_bytes=192 ;;
  esac
  admission=".build/queue-control/rtl-$profile"
  metadata=".build/queue-control/metadata-$profile"
  mkdir -p "$admission" "$metadata"
  verilator --binary --timing --assert -j 2 --top-module admission_tb \
    --Mdir "$admission" -GP="$p" -GN_CELL="$cells" -GN_DESC="$desc" -GMAX_BYTES="$max_bytes" \
    experiments/queue-control/admission.sv experiments/queue-control/admission_tb.sv
  "$admission/Vadmission_tb" +verilator+seed+104729
  verilator --binary --timing --assert -j 2 --top-module metadata_tb \
    --Mdir "$metadata" -GP="$p" -GN_CELL="$cells" -GN_DESC="$desc" \
    experiments/queue-control/queue_head.sv experiments/queue-control/cell_control.sv \
    experiments/queue-control/metadata_tb.sv
  "$metadata/Vmetadata_tb"
done
```

The [reproducible failure record](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/blob/4634d5a4dacb00304635ddb64a3f83747d8b03e8/verification/failures/TM04-queue-control.json)
preserves initial failed attempts and their dispositions. The included
fixtures, exact source identities and replay commands regenerate raw traces,
mapped netlists and STA logs in ignored build storage. Repository contracts,
117 lightweight tests and syntax checks, Markdown links and Git whitespace
checks pass.
