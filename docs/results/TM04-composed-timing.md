# Multi-egress composed control timing

Keep the dependent RTL freeze gate open. The three primary PR #32 points
reproduced their capacitance violations of −1.28716 fF for admission/RX,
−0.25986 fF for head/token feedback and −4.49575 fF for cell/cleanup
feedback. Small admission/RX also reproduced −1.27144 fF. Targeted buffer
splits clear the measured capacitance violations. The system reset coordinator
owns deassertion, and its launch and distribution are still unspecified.

The wider fixture exposes a new −0.00890 ns hold path in each profile and a
−4.96019 fF capacitance violation in the primary profile. The shortest path
feeds a beat counter's inverted output back into its D input. Adding buffers
at the affected D pins and splitting loaded nets clears the measured
violations without an extra edge. Carry forward balanced same-edge admission
and same-edge cached-head refill for the next integration measurement.
[Decision 0010](../decisions/0010-multi-egress-queue-control.md)

## Mapped results

All six PR #32 points reproduce the previous mapped Verilog SHA-256. The table
gives global slack before and after repair. A single value means no change.
All paths use the reference 10 ns clock and Nangate45 typical.

| Profile | Point | Setup (ns) | Hold (ns) | Capacitance (fF) | Final slew (ns) |
| --- | --- | ---: | ---: | ---: | ---: |
| Primary | Admission and first service | +2.38019 | +0.03629 | −1.28716 → +0.73684 | +0.07973 |
| Primary | Cached head and tokens | +6.08245 | +0.01437 | −0.25986 → +0.07908 | +0.07148 |
| Primary | Cell and cleanup | +6.38969 | +0.01623 | −4.49575 → +0.12756 | +0.06863 |
| Small | Admission and first service | +4.27282 → +4.27291 | +0.04117 | −1.27144 → +0.20104 | +0.07258 |
| Small | Cached head and tokens | +6.45257 | +0.01444 | +4.71147 | +0.10407 |
| Small | Cell and cleanup | +7.09374 | +0.01229 | +2.79153 | +0.09923 |
| Primary | Connected control | +2.35324 | −0.00890 → +0.00073 | −4.96019 → +0.25293 | +0.07514 |
| Small | Connected control | +4.34837 | −0.00890 → +0.00455 | +0.81047 | +0.07258 |

**Setup and hold pass** in the measured fixtures after repair, including
focused min and max paths. The connected groups cover reservation into RX
state, returned credits into admission and the descriptor pool, publication
into the cache, cache and tokens into binding, debit feedback, TX and abort
link service, and response ownership into prefetch. The final primary hold
margin is 0.73 ps under the ideal-clock reference.

**Slew and capacitance pass** their supported checks on all
eight maps. Overall electrical acceptance is **UNSUPPORTED** under this
reference because the library and SDC supply no max fanout limit. The JSON
retains clock, reset and data fanout counts, plus area, sequential area,
flops, output widths and exact endpoints. The connected primary fix adds
608 load buffers and nine D-pin buffers, with 56,848 flops preserved. The
small fix adds six D-pin buffers and preserves 3,315 flops. The primary map
has 56,848 ideal clock sinks, 4,820 reset sinks and a maximum data fanout of
10 cell inputs after repair. The isolated buffer results are recorded in
the [PR #32 report](TM04-control-timing.md).

The before/after checker contracts only newly added unary identity buffers
validated against the locked Liberty. It requires every original mapped
instance, pin connection and output port to match after contraction. A
wrong-load connection on a disposable comparison triggers the connection
check. Omitting a required min report triggers the endpoint check. The
first unexpected hold results and the initial limits of the repair and
report tools are preserved with replay inputs.
[Failure captures](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/blob/4634d5a4dacb00304635ddb64a3f83747d8b03e8/verification/failures/TM04-composed-timing.json)

## Reset at the system boundary

**Physical reset closure remains unresolved.** The 0.20 ns historical reference fails removal by
0.14368 ns. The prior PR #32 primary intersection was 0.34368–9.36461 ns.
The repaired PR #32 points give 0.34368–9.38589 ns. The connected maps require
arrival between 0.34368 and 6.88617 ns for primary and 0.34368 and 7.22538 ns
for small. Each interval is relative to a rising clock launch at an ideal
reset root and assumes 0.05 ns slew. The late connected bound comes from
reset gating through the read-address output. Recovery, removal, control
and explicit link/owner write endpoints are measured separately.

An ideal half-cycle arrival at 5.00 ns passes the reference checks. At
0.20 ns the removal detector fires. At 9.99 ns the late checks fire.
These are deterministic arrival samples with identical data constraints.
The reset coordinator supplies the epoch, and the environment owns synchronous
release. Integration needs the coordinator's launch phase, minimum and
maximum delay, root slew, and distribution skew to the actual captures,
including recovery, removal and write gating. The experiment uses the
R01 convention. [Public interface](../spec/multi-egress-interfaces.md#memory-and-frame-identity) ·
[Behavior contract](../spec/multi-egress-traffic-manager.md#reset-epochs-and-observation) ·
[R01 reset timing](../spec/reset-timing.md)

## Connected edge witnesses

The bounded SystemVerilog fixture has a real reservation owner and first-beat
framing decision, publication slot, cached metadata and binding state,
per-queue and per-port token feedback, scheduler mode selection and deficit
state, link arbitration, six occupied-plus-outstanding slots, and acceptance
driven retirement and cleanup. The fixture uses context and ring registers
on the existing ownership edges. It receives modeled capture heads, staged
cell availability and late framing marks, and a testbench memory that returns
issue metadata at fixed latency. Byte storage, ingress staging and drain
logic, disposition storage, the payload serializer/mux and AXI CSR/counter
paths have no mapped timing result. Their data, fanout and configuration
paths can reduce the observed slack. The fixture uses one live RX context per
ingress through materialization. The throughput replay uses the edge model
with the published staging depths.

| Trigger | Observation and legal neighbor |
| --- | --- |
| Rotated batch, one old-free descriptor and TX return | Primary ingress 1 gets ID 255 in DROP and WAIT. The other three see old descriptor scarcity. The pending WAIT head first uses returned ID 0 on the next edge. Small uses old ID 7. |
| 65-byte header with alpha 64/256 | With zero minima, U=10 grants ingress 1 two credits. U=9 reaches temporary queue limit. DROP rejects and WAIT retains the head. A malformed first-beat grant shares an edge with legal TX release, then cleans up with zero cell writes. |
| Cached head and late strict priority | Empty publication starts binding on the next edge. Singleton pop binds old A and caches B. Multi-entry pop follows the old successor. The eligible strict head published before the 16-beat opportunity wins; publication on that edge leaves the low successor bound through a stall. |
| Queue and port token boundaries | A reachable 64.75-byte balance with 0.25-byte refill keeps a 65-byte head blocked until the next edge. Queue-only, port-only and dual cases each debit once. The model also exercises the assigned 64.75-byte balance with 0.5-byte refill. That combination is a seeded arithmetic witness because whole-byte debits and 0.5-byte increments from an integer full bucket cannot produce 64.75. |
| Full old read credit and response | The connected fixture retires a cell with six old occupied-plus-outstanding slots and issues a read to another egress. Occupancy falls to five. The model adds the simultaneous pending response and the held-final neighbor. Connected publish/bind/issue edges 5/6/7 yield response/first transfer 8/9 at L=1 and 9/10 at L=2. |
| Five returns and reset | After normal offers, writes, responses and a held final beat on each output, all five primary lanes return distinct owners and restore U=1,024. Holding one TX final leaves U=1,023 until acceptance. Reset with a live issue restores the pools, reuses the address legally and filters a stale epoch. |

All four connected profile/latency runs passed. The edge model passed 360
directed witnesses, including the exact full-credit exchange, and detected
48 intended faults. The PR #32 admission and metadata comparators passed at
both profile sizes. The machine evidence retains the trigger edges, fresh
results, and case-specific endpoint groups. This is analysis fixture
evidence. Production RTL, independent DV and formal qualification require
their own phases.

## Traffic

**Balanced traffic passes** in the edge model. The cached same-edge
candidate accepts and delivers 9,216 beats per port in each of the eight
primary balanced windows after 2,048 warm-up cycles. Each run reconciles
frames, bytes and ownership after drain. Small mixed traffic meets the
same beat count at both latencies.

Primary independent lengths replay the prior one idle egress cycle at L=1
and two at L=2, with full input rate and no frame loss. Each traced gap
waited for the successor's first cell. Small independent lengths have
descriptor and cell pressure. They are supplemental diagnostics outside
the fixed-permutation gate. Staged admission misses all eight primary
balanced windows. Registered requests preserve those windows but miss
the small mixed L=2 replay with 99 descriptor drops. Neither alternative
is selected. The comparison JSON records the timestamped handoffs and
per-workload beat, idle and loss deltas for both alternatives.

## Tested sources and reproduction

| Item | Identity |
| --- | --- |
| PR #32 merge and branch entry | `523f1a025aa37c60b813408ee0884ef3d5a406dd` |
| Main entry gate | [CI 44901160895](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/44901160895), success |
| Pinned criteria, baseline maps, directed model and traffic | `10b85fb9a394937d4dd0717d7a85afead7d39246` |
| Connected baseline source and map | `2cb0dd9f2d3d01a0d25c3c32fd010f399d11eb72` |
| Connected directed simulation | `9ba19c051f59345916525797f9b277df05ec9e68` |
| Final legacy comparators, multi-sink hold and reset reports | `7295c7066c17079f4f4a24ebd8254062a8700fc4` |

Use the [committed criteria](../../experiments/queue-control/composed-timing.md)
and [machine evidence](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/blob/4634d5a4dacb00304635ddb64a3f83747d8b03e8/docs/results/TM04-composed-timing.json) for file digests, raw artifact
references, per-path measurements, and traffic accounting. Run the existing
prepared Verilator 5.054, Yosys 0.70/Slang/ABC and OpenSTA 3.2.0 tools.
The mapping matches PR #32's 10 ns, 0.10 ns uncertainty, 0.2/2.0 ns min/max
data I/O, 0.05 ns slew and 10 fF output load at Nangate45 typical 1.10 V and
25 °C. The connected boundary wires internal producer and consumer pins
directly and constrains its external ports with the same SDC. The reset
sweep changes only the reset input delay.

In the prepared checkout, use the criteria commit for the six legacy maps,
the connected map commit for the connected maps, and the final tool sources
for repair and focused reports. Preserve the ignored map directory across
the revision changes.

```sh
export CXX=g++-14
source .tools/activate.sh
make doctor
root=.build/composed-control-timing
for point in admission-balanced-rx head-token-feedback cell-cleanup-feedback; do
    python3 tools/queue_control_sta.py --point "$point" --short-abc \
        --jobs 2 --sta-timeout 900 --output "$root/$point"
done
python3 tools/queue_control_sta.py --point connected --short-abc \
    --jobs 2 --sta-timeout 900 --output "$root/connected"
```

```sh
mkdir -p "$root/compared"
for point in admission-balanced-rx head-token-feedback cell-cleanup-feedback connected; do
    for profile in primary small; do
        name="$profile-$point"
        map="$root/$point/$name"
        repair="$root/electrical/$name"
        hold=()
        detector=()
        if [[ $point == connected ]]; then hold=(--repair-hold); fi
        if [[ $name == small-admission-balanced-rx ]]; then detector=(--qualify-detectors); fi
        python3 tools/queue_control_electrical.py "$map" "$repair" --rounds 4 "${hold[@]}"
        python3 tools/queue_control_composition.py "$map" "$repair" \
            "$root/compared/$name.json" "${detector[@]}"
    done
done
```

The comparison command returns nonzero for an unsupported electrical limit,
a failing check or an invalid report. A completed JSON gives the individual
verdicts. For a replay of the successful small full-hold repair above, the
recorded artifact uses `electrical/small-connected-all-hold`.

```sh
mkdir -p "$root/replays"
python3 tools/queue_control_directed.py --json "$root/replays/directed.json"
for profile in primary small; do
    python3 tools/queue_control.py --profile "$profile" --variant cached --expect-gate \
        --json "$root/replays/$profile-cached.json"
    for variant in staged-admission registered-request; do
        python3 tools/queue_control.py --profile "$profile" --variant "$variant" \
            --json "$root/replays/$profile-$variant.json"
    done
    case "$profile" in
        primary) ports=4 cells=1024 desc=256 maximum=1536 ;;
        small) ports=2 cells=16 desc=8 maximum=192 ;;
    esac
    for latency in 1 2; do
        case_root="$root/connected-sim-ownership/$profile-L$latency"
        mkdir -p "$case_root"
        verilator --binary --timing --assert -j 2 --top-module connected_control_tb \
            -DQUEUE_CONTROL_CONNECTED --Mdir "$case_root" -GP="$ports" -GN_CELL="$cells" \
            -GN_DESC="$desc" -GMAX_BYTES="$maximum" -GL="$latency" \
            experiments/queue-control/{connected_control_tb,connected_control,admission,queue_head,cell_control}.sv
        "$case_root/Vconnected_control_tb"
    done
done
make multi-egress-declarations
python3 tools/multi_egress_feasibility.py --expect-gate
make repo-check
python3 tools/check_light.py
git diff --check origin/main...HEAD
```

Use the [PR #32 commands](TM04-control-timing.md#reproduction-and-evidence)
for the two legacy comparators, including admission seed 104729. The primary
independent workload uses one seeded generator per ingress at 104729 plus
ingress ID. Balanced sequences and window sizes are fixed in the runner.
