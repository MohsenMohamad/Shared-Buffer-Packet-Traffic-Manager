# Multi-egress control timing follow-up

The dependent RTL freeze gate remains open. The balanced same-edge
admission map meets the 10 ns data setup and hold budget in both fixture
profiles. It preserves rotated admission and the cached-head data path. The staged alternative reduces
setup pressure but misses the balanced throughput requirement with the
published storage depths. Physical reset closure requires a characterized
upstream release source and distribution.

The [comparison criteria](../../experiments/queue-control/follow-up.md) were
committed as `0b4e850` before the reruns. The starting revision was the
fetched `origin/main`, `4d4356e1125d1b18c04c9eaa478cd7425c00e026`,
which merged [PR #31](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/pull/31)
from `d6c05433186e78d509f70100470c95754ca7a3b4`. The
[prior measurements](TM04-queue-control.md) retain the original fixture,
default-map evidence and registered-request boundary.

## Mapped path and same-edge changes

The primary matched short-script reruns reproduce −14.70553 ns serial and
−4.56895 ns lookahead setup slack. Fixing only the mode on the primary
lookahead map gives +0.44205 ns static and −4.56895 ns dynamic. The dynamic
worst path starts at input `minimum[1]` and ends at `_157339_/D`, the sticky
`invariant_error` register after merged resource checking. The static worst
path reaches the same endpoint from the register holding `free_desc[215]`.
Descriptor availability joins the dynamic path, while the encoded selected ID
has separate RX and free-bitmap consumers.

| Dynamic path checkpoint | Arrival (ns) | Sink fanout | Mapped dependency |
| --- | ---: | ---: | --- |
| `minimum[1]` | 2.00000 | 1 | Configured input delay |
| `_83184_/Z` | 6.53045 | 4 | Last new queue minimum reaches the chained old protected sum |
| `_83450_/Z` | 6.88939 | 1 | Old unreserved credit joins the cone |
| `_83477_/ZN` | 7.11849 | 3 | Rotated route and length join the subset and same-queue calculation |
| `_84120_/ZN` | 7.44728 | 2 | Selected α first reaches the path |
| `_84669_/ZN` | 8.63142 | 5 | Mode and static limit join the policy result |
| `_87168_/ZN` | 8.73010 | 1 | Old descriptor availability reaches the decision |
| `_139270_/Z` | 11.39710 | 1 | Per-queue release selection first joins update feedback |
| `_146564_/ZN` | 14.12629 | 1 | Descriptor return and return-ID checking join |
| `_157339_/D` | 14.42589 | — | Merged accounting detection captured |

These are path arrivals and structural fan-in milestones on the measured
netlist. ABC absorbs several arithmetic and selection signals, so the
milestones bound segment contributions. The static descriptor branch takes
4.33963 ns from `free_desc[215]`'s Q transition to its first convergence
with other decision inputs. In the dynamic case the first 4.53045 ns after
the input budget reaches all 16 minimum terms. From the first release-queue
convergence to the consumer adds 3.02879 ns. The
[path annotator](../../tools/queue_control_path.py) retains the cells, arc
delays, slew, fanout and consumer aliases for the complete path.

The factored variant computes one old deficit and excess per rotated lane.
For a hypothetical subset it sums each touched queue once. If its subset
total is `T` and its old protected deficit is `d=max(M-H,0)`, it consumes
`max(0,T-d)` shared cells, and its new excess is that value plus
`max(0,H-M)`. For a positive request the last member of a subset consumes
shared credit exactly when the final queue subtotal exceeds its old deficit.
The candidate sees the old shared pool less the subset's total spill. The
grant logic remains ordered and selects the original lowest pre-edge-free
IDs. The product keeps all bits before dropping eight fractional bits.
Configuration is still a runtime input. The balanced variant forms all
positive old deficits before summing them, then forms masked reservation and
release terms per queue before merging. There is no maintained credit
aggregate or new admission state in either same-edge version.

## Checked edge behavior

| Trigger | Check |
| --- | --- |
| Nonzero rotation, one old-free descriptor, coincident return | Primary offers all four headers. Ingress 1 wins the last old ID in DROP and WAIT. Other lanes receive descriptor scarcity. The returned ID is eligible at the next decision using updated state. |
| 65 bytes, α=64, zero minimum | U=10 permits the first two-cell grant because `(64*8)>>8=2`. Later same-queue prefix lanes fail. At U=9 the result is temporary queue limit because `(64*7)>>8=1`. DROP and WAIT are checked. |
| α=0 and minimum crossing; α=4096 at the shared threshold | The α=0 test consumes only protected credit and checks restored credit after simultaneous TX returns. With α=4096 and one post-candidate shared cell, a malformed 65-byte header grants and aborts. A two-cell follow-up at U=1 reports cell scarcity before temporary queue policy, and a one-cell request sees a zero threshold. |
| Merged updates and directed ownership | The same-queue neighbor grants on consecutive edges with an old-owner release on the first. The comparator independently recounts per-ID credit and queue ownership. Separate witnesses align four primary grants with all TX returns and a staged write, and all five return lanes with a staged write and the other three ingress grants. The cleaning ingress cannot grant a new header on its cleanup edge. |
| Old request credit, response and restart | With six occupied slots, a return on the edge cannot enable issue on that edge. Responses occur at `t+L`, first visible at `t+L+1`. Directed traces cover both profiles and both latencies, stale-epoch rejection, and reset cancellation of a sampled admission batch. |

The Verilator comparator uses the serial and original lookahead fixtures
plus the same-edge candidates and staged commit. Legal old-ID and widened
resource checks run at both profile sizes, with seed 104729 for randomized
headers and cleanup releases. The edge model checks staged DROP/WAIT,
commit coinciding with an old return, pending batch reset, and first-beat
abort through cleanup and ordered disposition.

## Staged contract and replay

At edge `t`, sample one batch of eligible old capture heads, rotated
hypothetical fit terms and old-free descriptor ranks. This reserves no
credit, consumes no header and emits no admission or ingress-service event.
There can be one outstanding batch. At `t+1`, resolve its actual prefix
using the sampled eligibility and atomically reserve credit and an ID for
each grant. Service each decided first beat and report its admission and
ingress-service observations on that edge. A malformed granted beat also
reports abort mark on `t+1`. Reject disposition can appear on `t+2`;
abort cleanup can first serve on `t+2` and its disposition follows cleanup.
A good frame still publishes after its final staged write, then dispatches
and issues reads only under the original old-state rules.

Capture and nonheader service continue independently. Heads arriving during
the outstanding batch cannot join it. Returns update live state on both
edges and enter the next batch at `t+2` at the earliest. No other grant can
take an ID promised by that batch ahead of commit. A WAIT keeps its head and
is retried under a later snapshot. Reset cancels all pending terms, clears
ownership and leaves no stale admission event. This changes the visibility
of an otherwise usable return and defers a currently eligible first beat.
The original contract and public declaration remain the basis for dependent
work. Adopting the staged version requires a maintainer decision.

Every window is 9,216 clocks after a 2,048-clock warm-up. The primary cached
baseline and the registered-request diagnostic meet all eight balanced
targets. The small cached baseline also meets all eight. Small registered
request at L=2 still delivers 9,216/8,478 mixed beats and drops 99 short
frames through drain due to descriptor scarcity.

| Staged workload | L | Accepted beats | Delivered beats | Loss through drain |
| --- | ---: | --- | --- | --- |
| Primary 60 | 1 and 2 | 8,192 each | 8,192 each | 0 |
| Primary 65 | 1 and 2 | 8,294 each | 8,294 each | 0 |
| Primary 1,536 | 1 and 2 | 9,168 each | 9,168 each | 0 |
| Primary mix | 1 and 2 | 9,072 each | 9,072 each | 0 |
| Primary independent | 1 and 2 | 8,972/8,987/9,029/8,988 | 8,987/8,971/8,973/9,028 | 0 |
| Small mix | 1 and 2 | 8,608 each | 8,608 each | 0 |
| Small independent | 1 | 8,489/8,497 | 8,469/8,426 | 6/3 descriptor and 2/1 cell rejects |
| Small independent | 2 | 8,489/8,497 | 8,427/8,331 | 10/8 descriptor and 5/2 cell rejects |

The uniform balanced losses track the ingress stalls. Each header adds a
service bubble, so first response visibility misses every counted boundary
by one edge even when the read issues immediately. For example the primary
60-byte L=1 trace samples at 2035, services at 2036, writes at 2047,
publishes at 2048, binds at 2049, issues at 2050 and first transfers at 2052.
The predecessor finishes at 2050 and the response arrives on idle edge 2051.
The mixed and independent windows also have idle edges before publication is
visible or before the successor requests a read. Arbitration adds delay on
some independent boundaries. The replay evidence retains the counts and an
example per cause, and the raw replay retains every gap at both latencies.
All qualified balanced and primary independent workloads reconcile commits,
deliveries and ownership through drain. Diagnostic incast, stall and abort
runs report their measured losses separately.

## Electrical, reset and composition

Primary balanced admission saves 19.65% mapped area against the short-script
lookahead. On its runtime-selectable map the worst setup slack is +2.38987 ns.
Fixing mode for diagnosis gives +4.06065 ns static and +2.39013 ns dynamic.
The 10 ns result includes grant, RX state, descriptor bitmap, per-queue credit
and all merged deltas.

Split the sink load at each violating driver with a noninverting buffer.
Retain output loads, register count, consumer widths and sink-pin evidence.
The selected primary admission's worst pin is the NOR3 `_105035_/ZN`
with 10 sink pins, loaded to 17.30886 fF against 16.02170 fF.
Five buffers repair that pin and the four smaller violations. The
worst capacitance slack moves from −1.28716 fF to +1.61996 fF, with
unchanged worst setup and hold. The primary staged map also needs a
data buffer at the pending register D pin to repair the shortest feedback
path. Its reference removal defect remains.

Cached head's violating NOR3 `_302830_/ZN` has 10 sinks. A single load
split moves worst capacitance slack from −0.03693 fF to +1.26422 fF.
Cell control's NOR4 `_168320_/ZN` has nine sinks. Thirty load splits
move its worst capacitance slack from −4.96770 fF to +0.17666 fF.
Both preserve the original setup and hold minima. The historical
lookahead and factored repair attempts leave residual near-limit pins.

| Profile | Fixture | ABC | Area (µm²) | Setup / hold (ns) | Slew (ns) / capacitance (fF) slack | Worst setup path |
| --- | --- | --- | ---: | ---: | ---: | --- |
| small | admission | short | 9,824.71 | -0.43367 / +0.03629 | +0.05327 / -2.50945 | `minimum[3] → _14383_/D` |
| primary | admission | short | 89,731.11 | -14.70553 / +0.04244 | +0.06092 / -1.24588 | `minimum[5] → _128069_/D` |
| small | admission-lookahead | short | 10,017.03 | +1.67972 / +0.03629 | +0.07844 / +1.06758 | `minimum[2] → _15393_/D` |
| primary | admission-lookahead | short | 100,536.03 | -4.56895 / +0.04507 | +0.02656 / -7.07420 | `minimum[1] → _157339_/D` |
| small | admission-factored | short | 9,799.71 | +2.00022 / +0.03629 | +0.06887 / -0.40744 | `minimum[1] → _15375_/D` |
| primary | admission-factored | short | 91,931.73 | -3.83815 / +0.04244 | +0.03460 / -7.07420 | `minimum[5] → _145375_/D` |
| small | admission-balanced | short | 8,180.03 | +4.28367 / +0.04117 | +0.07465 / +0.20104 | `raw_class[8] → _12630_/D` |
| primary | admission-balanced | short | 80,779.94 | +2.38987 / +0.03263 | +0.06187 / -1.28716 | `minimum[100] → _127477_/D` |
| small | admission-staged | short | 9,814.87 | +5.14948 / -0.01593 | +0.05352 / -2.47380 | `minimum[1] → _14360_/D` |
| primary | admission-staged | short | 91,659.08 | +2.09826 / -0.01844 | +0.02017 / -5.53979 | `minimum[1] → _141506_/D` |
| small | head-cached | default | 20,536.26 | +6.65898 / +0.00397 | +0.09996 / +6.37465 | `port_credit_bytes[27] → _20863_/D` |
| primary | head-cached | default | 459,524.31 | +6.22553 / +0.00397 | +0.07067 / -0.03693 | `port_credit_bytes[30] → _602545_/D` |
| small | cell | default | 2,005.37 | +7.29742 / +0.01845 | +0.09983 / +2.85486 | `abort_valid[1] → _2435_/D` |
| primary | cell | default | 265,420.39 | +6.51561 / +0.00732 | +0.02550 / -4.96770 | `read_eligible[1] → _316321_/D` |
| small | admission-rx | short | 9,783.75 | +1.97787 / +0.04244 | +0.07286 / +0.27507 | `minimum[3] → _15385_/D` |
| primary | admission-rx | short | 92,225.66 | -3.82896 / +0.04244 | +0.05847 / -1.90946 | `minimum[5] → _145554_/D` |
| small | admission-balanced-rx | short | 8,103.42 | +4.27282 / +0.04117 | +0.06146 / -1.27144 | `raw_class[8] → _12470_/D` |
| primary | admission-balanced-rx | short | 81,451.86 | +2.38019 / +0.03629 | +0.06187 / -1.28716 | `minimum[99] → _127521_/D` |
| small | head-token-feedback | short | 27,923.88 | +6.45257 / +0.01444 | +0.10407 / +4.71147 | `token_start → _24349_/D` |
| primary | head-token-feedback | short | 503,872.63 | +6.08245 / +0.01437 | +0.07028 / -0.25986 | `token_start → _432884_/D` |
| small | cell-cleanup-feedback | short | 2,570.89 | +7.09374 / +0.01229 | +0.09923 / +2.79153 | `staged_valid[0] → _2437_/D` |
| primary | cell-cleanup-feedback | short | 322,517.82 | +6.38969 / +0.01623 | +0.03352 / -4.49575 | `staged_valid[2] → _323086_/D` |
| primary | admission-lookahead buffered | short | 100,550.93 | -4.56895 / +0.04507 | +0.07058 / -0.22788 | `minimum[1] → _157339_/D` |
| primary | admission-factored buffered | short | 91,942.90 | -3.83815 / +0.04244 | +0.07058 / -0.22788 | `minimum[5] → _145375_/D` |
| primary | admission-balanced buffered | short | 80,789.25 | +2.38987 / +0.03263 | +0.08391 / +1.61996 | `minimum[100] → _127477_/D` |
| primary | admission-staged buffered | short | 91,671.05 | +2.09826 / +0.00395 | +0.07304 / +0.03211 | `minimum[1] → _141506_/D` |
| small | admission-staged buffered | short | 9,819.39 | +5.14948 / +0.00224 | +0.07916 / +1.19950 | `minimum[1] → _14360_/D` |
| primary | head-cached buffered | default | 459,526.17 | +6.22553 / +0.00397 | +0.08474 / +1.26422 | `port_credit_bytes[30] → _602545_/D` |
| primary | cell buffered | default | 265,476.25 | +6.51561 / +0.00732 | +0.06618 / +0.17666 | `read_eligible[1] → _316321_/D` |

Area includes sequential and combinational cells. The evidence retains the
split area, exact setup and hold endpoints, transition and capacitance pins,
and sink fanout for the attempted repairs.

The reference earliest release is 0.2 ns. The measured removal slack
remains −0.14368 ns. The buffered maps use the same reset treatment.
The required ideal-root release windows follow.

- Primary admission-balanced requires 0.34368–9.93947 ns.

- Primary head-cached requires 0.34368–9.94904 ns.

- Primary cell requires 0.34368–9.44890 ns.

- Primary head-token-feedback requires 0.34368–9.94904 ns.

- Primary cell-cleanup-feedback requires 0.34368–9.36461 ns.

The intersection for these primary fixtures is 0.34368–9.36461 ns at
0.05 ns slew. The late bound includes reset-to-write control where the
path exists.
The repository has no characterized upstream reset source or routed
distribution to compare. No reset circuit or new release budget was used.

The points below use the same reference loads and the physical-width ports.

- primary admission-balanced-rx, admission-service has +3.30076 ns setup slack from `minimum[99]` to `_127105_/D`.

- small admission-balanced-rx, admission-service has +5.10358 ns setup slack from `route[8]` to `_12448_/D`.

- primary admission-rx, admission-service has -0.45202 ns setup slack from `minimum[5]` to `_145851_/D`.

- small admission-rx, admission-service has +3.76968 ns setup slack from `minimum[3]` to `_15391_/D`.

- primary cell-cleanup-feedback, cleanup-pool has +8.75416 ns setup slack from `_304750_/Q` to `_304848_/D`.

- small cell-cleanup-feedback, cleanup-pool has +9.24509 ns setup slack from `_2425_/Q` to `_2454_/D`.

- primary head-token-feedback, token-dispatch has +8.36826 ns setup slack from `_430149_/QN` to `_430419_/D`.

- small head-token-feedback, token-dispatch has +8.70549 ns setup slack from `_24495_/QN` to `_24761_/D`.

The token point includes old registered balances, both token comparisons,
cached-head selection, same-edge result capture and debit/refill feedback.
All buckets are enabled with one input-configured refill rate in the fixture.
The receive point includes old-header eligibility and first-beat framing
through the registered reserve/abort control. Payload assembly and cursor state
remain outside that cone. The cleanup point uses one physical abort-link
lookup from the registered cursor and feeds the return into free-ID state.
The caller supplies the first address, count, descriptor and mark, including
coincident materialization in that count. TX serializer and response tags,
full DRR and strict scheduling, independent bucket configuration, memory
internals, CSR and full end-to-end timing are outside the mapped coverage.
Each selected primary composed map meets data setup and hold. Its reported
capacitance violations remain open at the composed boundary.

## Reproduction and evidence

The pinned toolchain is Verilator 5.054, Yosys 0.70 with Slang and locked
ABC, and OpenSTA 3.2.0. See the [toolchain inventory](../implementation/toolchain-inventory.md).
Use the [reference SDC](../../experiments/queue-control/reference.sdc) and
Nangate45 typical at 1.10 V, 25 °C, with the ideal 10 ns clock, 0.10 ns
clock uncertainty, 0.2/2.0 ns min/max I/O, 0.05 ns slew and 10 fF load.
The [evidence](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/blob/4634d5a4dacb00304635ddb64a3f83747d8b03e8/docs/results/TM04-control-timing.json) includes the command inputs,
source revision and file identities, timing and electrical measurements,
replay accounting and verification outcomes. The
[failure record](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/blob/4634d5a4dacb00304635ddb64a3f83747d8b03e8/verification/failures/TM04-control-timing.json)
documents unexpected measurement and verification attempts.

```sh
export CXX=g++-14
source .tools/activate.sh
make doctor
make multi-egress-declarations
python3 tools/multi_egress_feasibility.py --expect-gate
root=.build/control-timing
mkdir -p "$root/replays"
python3 tools/queue_control_directed.py --json "$root/directed-final.json"
for profile in primary small; do
    for variant in cached staged-admission registered-request; do
        python3 tools/queue_control.py --profile "$profile" --variant "$variant" \
            --json "$root/replays/$profile-$variant.json"
    done
done
```

Run the RTL fixtures at both sizes with the measured source and parameters.

```sh
for profile in primary small; do
    case "$profile" in
        primary) ports=4 cells=1024 desc=256 max_bytes=1536 ;;
        small) ports=2 cells=16 desc=8 max_bytes=192 ;;
    esac
    admission="$root/rtl-$profile"
    metadata="$root/metadata-$profile"
    mkdir -p "$admission" "$metadata"
    verilator --binary --timing --assert -j 2 --top-module admission_tb \
        --Mdir "$admission" -GP="$ports" -GN_CELL="$cells" -GN_DESC="$desc" -GMAX_BYTES="$max_bytes" \
        experiments/queue-control/admission.sv experiments/queue-control/admission_tb.sv
    "$admission/Vadmission_tb" +verilator+seed+104729
    verilator --binary --timing --assert -j 2 --top-module metadata_tb \
        --Mdir "$metadata" -GP="$ports" -GN_CELL="$cells" -GN_DESC="$desc" \
        experiments/queue-control/queue_head.sv experiments/queue-control/cell_control.sv \
        experiments/queue-control/metadata_tb.sv
    "$metadata/Vmetadata_tb"
done
```

Storage and timing checks compare mapped flop counts, mapped output width
and actual STA endpoints. Use the map source identified in the JSON for exact
historical reproduction. Use the current branch to repeat the study with
the delivered fixture sources. The cached-head STA retry reused the first
netlist and the same mapping recipe.

```sh
for pair in \
    'baseline-short-serial admission' \
    'baseline-short-lookahead admission-lookahead' \
    'factored-fixed admission-factored' \
    'staged-fixed admission-staged' \
    'balanced admission-balanced' \
    'composed-rx admission-rx' \
    'composed-balanced-rx admission-balanced-rx' \
    'composed-token head-token-feedback' \
    'composed-cleanup cell-cleanup-feedback'; do
    read -r directory point <<EOF_PAIR
$pair
EOF_PAIR
    python3 tools/queue_control_sta.py --point "$point" --short-abc \
        --jobs 2 --sta-timeout 900 --output "$root/$directory"
done
for point in head-cached cell; do
    python3 tools/queue_control_sta.py --point "$point" \
        --sta-timeout 900 --output "$root/baseline-default-$point"
done

export TM_LIBERTY=.deps/liberty.lib
export TM_TOP=admission
export TM_SDC=experiments/queue-control/reference.sdc
for pair in \
    'baseline-short-lookahead admission-lookahead' \
    'factored-fixed admission-factored' \
    'staged-fixed admission-staged' \
    'balanced admission-balanced'; do
    read -r directory point <<EOF_PAIR
$pair
EOF_PAIR
    fixture="$root/$directory/primary-$point"
    for mode in 0 1; do
        TM_NETLIST="$fixture/mapped.v" TM_ADMISSION_MODE="$mode" \
            sta -no_init -exit experiments/queue-control/timing.tcl > "$fixture/mode-$mode.stdout"
    done
done
fixture="$root/baseline-short-lookahead/primary-admission-lookahead"
python3 tools/queue_control_path.py "$fixture" mode-1.stdout > "$fixture/dynamic-path.json"

for profile in primary small; do
    python3 tools/queue_control_composed.py \
        "$root/composed-token/$profile-head-token-feedback" token-dispatch
    python3 tools/queue_control_composed.py \
        "$root/composed-balanced-rx/$profile-admission-balanced-rx" admission-service
    python3 tools/queue_control_composed.py \
        "$root/composed-cleanup/$profile-cell-cleanup-feedback" cleanup-pool
    python3 tools/queue_control_electrical.py \
        "$root/staged-fixed/$profile-admission-staged" "$root/electrical-staged-$profile" \
        --rounds 4 --repair-hold
done
python3 tools/queue_control_electrical.py \
    "$root/balanced/primary-admission-balanced" "$root/electrical-balanced-first" --rounds 3
python3 tools/queue_control_electrical.py \
    "$root/balanced/small-admission-balanced" "$root/electrical-balanced-small" --rounds 2
python3 tools/queue_control_electrical.py \
    "$root/baseline-short-lookahead/primary-admission-lookahead" "$root/electrical-lookahead-full" --rounds 4
python3 tools/queue_control_electrical.py \
    "$root/factored-fixed/primary-admission-factored" "$root/electrical-factored" --rounds 4
for point in head-cached cell; do
    python3 tools/queue_control_electrical.py \
        "$root/baseline-default-$point/primary-$point" "$root/electrical-$point" --rounds 3
done
make repo-check
python3 tools/check_light.py
git diff --check origin/main...HEAD
```
