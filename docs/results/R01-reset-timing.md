# R01 shared reset timing qualification

**Measurement execution PASS; physical reset-source closure UNRESOLVED.** Six
actual mapped FIFO/allocator points, 36 timing scenarios and 14 intended invalid
constraint detections completed. Falling-edge reference checks close data,
recovery/removal, reset effects and electrical limits for E0 FIFO2/4 and I0 pools.
F0 cell selection still misses setup by **16.03948 ns**; both F0 pools also have
mapped capacitance violations, and the weak-driver sensitivity adds reset-source
electrical violations. Positive recovery/removal alone closes none of those gaps.

No physical reset source is implemented or characterized here. All passing model
checks are conditional on the recorded source, slew/load, ideal clock and corner.
No synchronizer, functional reset change, CTS, routing or multicorner signoff is
included. P08's actual receive/admission consumer and P12's integrated TM/memory
variants remain unmeasured by this task.

## Definition, tested source and execution

The [frozen definition](../../experiments/reset-timing/README.md) and numeric
[configuration](../../experiments/reset-timing/config.json) were committed before
any new mapping/STA at `b5070868f368ff2e3c79d48da715db2b82aa389a`, from fetched
`origin/main` `61d4c4c2b751642e6b79a995b710f186a8ce0281`.
The accepted complete run tests clean
`952e1ee60785c60de35e368c2327063464abedc6` on `analysis/reset-timing`.
Documentation/evidence commits following that SHA are not substituted tested RTL.

[Durable measurements](R01-reset-timing.json) retain exact configuration/recipe,
production source, dependency and library hashes; tool identities; mapped state,
area, fanout and netlist hashes; generated SDC and raw manifest hashes; every
reported category's worst max/min path with actual pins; required windows;
electrical limits; and intended negative detectors. Raw scripts/netlists/reports
are under the artifact directory recorded there. The run has four passing doctor
cases, six passing maps, 36 valid STA cases and 14 expected-negative PASS cases.
`PASS` on an invalid-input test means the intended rejection occurred, not timing
closure or acceptance of those constraints. No random seed is used.

The selected stack is pinned Yosys 0.70/Slang, bundled ABC and OpenSTA 3.2.0 with
runtime source identity checked by doctor. The library is Nangate45 typical,
1.10 V / 25 C, SHA256
`8d540a4d4cf6d09d27c87ad067857a9c0c2eeb023ab7a56e058cd3113db4e9b1`.
Time is ns, capacitance fF, cell area library square micrometres. The ideal 10 ns
clock has zero modeled network delay/slew; no wire RC or variation is included.

## Events, source boundary and ordinary data constraints

Functional transfers sample rising `clk`; reset asserts asynchronously low,
stays low over at least two rising edges and releases synchronously by the
environment. Startup/flush, unreset payload/link contents and old-epoch response
invalidation retain the published functional contracts. The bench's falling-edge
release is a deterministic functional stimulus phase, not an external network
characterization. The block does not generate its reset.

`fall-reference-r01` launches reset release at the ideal falling edge, 5 ns after
the preceding rising edge, with SDC source delay 0..0.2 ns. Fixed-slew mode thus
models block-port release at 5..5.2 ns. Recovery checks the rising reset transition
before the next rising clock; removal checks it after the preceding rising
clock. The zero minimum is an uncharacterized zero-transport reference, not a
new physical minimum chosen to pass. Rising-phase sensitivity changes only the
launch phase; historical-shape sensitivity uses rising launch and 0.2/2 ns reset
bounds under a **new** identity. No measured slack was used to tune an envelope.

The primary mode fixes 0.05 ns nonclock input slew. Drive sensitivity substitutes
BUF_X1/Z on the same mapped netlist: OpenSTA includes its virtual driver delay
and load-dependent slew. Its source-delay envelope is upstream of that virtual
driver; the actual block-port envelope is reported separately. This distinction
matters at F0. Fixed-slew mode implicitly supplies the requested slew regardless
of the root load; it does not demonstrate a realizable reset driver.

Ordinary data IO always references rising `clk`, separately from reset. E0 FIFO
capability uses min/max 0.2/1 ns, 0.05 ns uncertainty; allocator and future P08/P12
production settings use 0.2/2 ns, 0.10 ns uncertainty. Each output bit has 10 fF.
The studies share reset convention, not an identical full timing setup. Both
reset signal senses remain in the overall/gating reports under the reference
IO model; their timing does not restrict the functional asynchronous-assertion
contract or prove that arbitrary assertion times meet data setup/hold.

## Mapped boundary and path completeness

All maps use the actual registered production synthesis source set with Slang,
flat synth, dffunmap, Liberty flop mapping and constrained ABC with BUF_X1/10 fF.
No action input is tied off and no encoder/consumer surrogate replaces a pool.
All production outputs remain live. Pool area includes bitmap/count/error and
validation/selection logic; FIFO area includes mapped payload and control. Pool
area excludes FIFO, payload, links, admission and external consumers. FIFO uses
the newly identified constrained mapping recipe, so its area/timing is not a
rerun of the retired historical FIFO mapping flow.

| Map | Area, µm² | Mapped flops | Async pins | Direct reset root loads | Reset buffer/inverter tree nets |
| --- | ---: | ---: | ---: | ---: | ---: |
| E0-fifo2 | 2128.798 | 279 | 5 | 9 | 1 |
| E0-fifo4 | 4484.760 | 556 | 8 | 13 | 1 |
| I0-cell | 617.652 | 39 | 39 | 40 | 3 |
| I0-descriptor | 440.496 | 22 | 22 | 23 | 5 |
| F0-cell | 20109.334 | 1036 | 1036 | 1038 | 7 |
| F0-descriptor | 5128.746 | 266 | 266 | 267 | 12 |

FIFO payload is 274/548 bits; total FIFO state is 279/556 flops. Pool state is
capacity + count width + sticky error: 39/22/1036/266. No unmapped cells or latches
remain. Each map's output-bit, flop and asynchronous-pin inventory agrees with
STA. Every output and **every** mapped asynchronous pin has both max/min paths.
`check_setup -verbose` reports no missing clocks/delays, loops or unconstrained
endpoints. All required report sections and actual endpoint pins are retained;
completion markers cannot override diagnostics or missing/empty paths.

Data input-to-register, register-to-register and register-to-output paths are
nonempty on all points. FIFO input-to-output paths are present; pool
input-to-output data paths are explicitly NOT_PRESENT. Overall reports retain
all groups, and pool selection, availability and count have explicit queries.
Reset effects select the `clk` group because OpenSTA otherwise includes
asynchronous checks even when given register data pins. Reset-pin queries retain
both recovery and removal in `asynchronous`; no path is false-pathed or disabled.
Fanout is structural pin load, not routed distribution/skew or physical closure.

## Falling-edge reference results

All values below are slack in ns. Data columns exclude reset startpoints;
reset effects retain reset-to-data/output setup/hold/budget checks separately.
The reset columns are deassertion recovery/removal, not ordinary data setup/hold.

| Point / mode | Data max / min | Recovery / removal | Reset effects max / min | Electrical | Aggregate model |
| --- | --- | --- | --- | --- | --- |
| E0-fifo2 / slew | 7.87237 / 0.04127 | 4.78947 / 4.70632 | 3.67304 / 5.01845 | PASS | PASS |
| E0-fifo2 / drive | 7.87221 / 0.04127 | 4.75080 / 4.75951 | 3.63734 / 5.02871 | PASS | PASS |
| E0-fifo4 / slew | 7.89317 / 0.04065 | 4.78947 / 4.70632 | 3.68232 / 5.01691 | PASS | PASS |
| E0-fifo4 / drive | 7.89025 / 0.04065 | 4.73453 / 4.75648 | 3.62647 / 5.03877 | PASS | PASS |
| I0-cell / slew | 7.08341 / 0.00870 | 4.73947 / 4.65632 | 2.50069 / 4.98347 | PASS | PASS |
| I0-cell / drive | 7.08341 / 0.00870 | 4.59262 / 4.69102 | 2.35913 / 5.06437 | PASS | PASS |
| I0-descriptor / slew | 7.24980 / 0.01728 | 4.73947 / 4.65632 | 2.56798 / 4.99058 | PASS | PASS |
| I0-descriptor / drive | 7.27150 / 0.01728 | 4.66065 / 4.70173 | 2.48497 / 5.03658 | PASS | PASS |
| F0-cell / slew | -16.03948 / 0.00899 | 4.73947 / 4.65632 | 2.61501 / 4.98096 | FAIL | FAIL |
| F0-cell / drive | -16.03948 / 0.00899 | 0.58227 / 4.07173 | -0.78921 / 6.92346 | FAIL | FAIL |
| F0-descriptor / slew | 2.55246 / 0.01594 | 4.73947 / 4.65632 | 2.54696 / 5.03438 | FAIL | FAIL |
| F0-descriptor / drive | 2.55246 / 0.01594 | 3.67991 / 4.55008 | 1.65604 / 5.55399 | FAIL | FAIL |

Aggregate model PASS is conditional; physical source closure is UNRESOLVED for
all rows. F0's data failure persists independently of reset phase/source:
`_22766_/Q → available_id[8]`, 23.93948 ns arrival and −16.03948 ns slack.
I0 cell selection is `_746_/Q → available_id[3]`, 0.81659 ns arrival /
7.08341 ns slack. I0 descriptor selection is `_590_/Q → available_id[3]`,
0.47333 / 7.42667 ns. F0 descriptor selection is `_7468_/Q → available_id[7]`,
5.34754 / 2.55246 ns. These are isolated bitmap-register-to-ID paths, not a
consumer path or Fmax bound. The JSON retains all other worst endpoints and pins,
including the I0 descriptor nonselection data worst path.

## Required release windows and margins

The required window is an inferred **requirement**, not a measured source.
At the stated slew/load, lower bound = modeled block-port minimum arrival minus
worst removal slack; upper bound = modeled port maximum plus worst recovery
slack. Zero is the preceding rising clock. Bounds below use recovery/removal
only; reset gating/output and electrical checks remain additional requirements.
All windows here are nonempty, but no physical source has been shown to satisfy
them. Rounding is to five decimal places.

| Point / mode | Modeled port envelope, ns after rise | Required port window | Required pre-driver SDC source window |
| --- | --- | --- | --- |
| E0-fifo2 / slew | 5.00000 .. 5.20000 | 0.29368 .. 9.98947 | 0.29368 .. 9.98947 |
| E0-fifo2 / drive | 5.03881 .. 5.23881 | 0.27930 .. 9.98961 | 0.24049 .. 9.95080 |
| E0-fifo4 / slew | 5.00000 .. 5.20000 | 0.29368 .. 9.98947 | 0.29368 .. 9.98947 |
| E0-fifo4 / drive | 5.05516 .. 5.25516 | 0.29868 .. 9.98969 | 0.24352 .. 9.93453 |
| I0-cell / slew | 5.00000 .. 5.20000 | 0.34368 .. 9.93947 | 0.34368 .. 9.93947 |
| I0-cell / drive | 5.13670 .. 5.33670 | 0.44568 .. 9.92932 | 0.30898 .. 9.79262 |
| I0-descriptor / slew | 5.00000 .. 5.20000 | 0.34368 .. 9.93947 | 0.34368 .. 9.93947 |
| I0-descriptor / drive | 5.08034 .. 5.28034 | 0.37861 .. 9.94099 | 0.29827 .. 9.86065 |
| F0-cell / slew | 5.00000 .. 5.20000 | 0.34368 .. 9.93947 | 0.34368 .. 9.93947 |
| F0-cell / drive | 8.39682 .. 8.59682 | 4.32509 .. 9.17909 | 0.92827 .. 5.78227 |
| F0-descriptor / slew | 5.00000 .. 5.20000 | 0.34368 .. 9.93947 | 0.34368 .. 9.93947 |
| F0-descriptor / drive | 5.87866 .. 6.07866 | 1.32858 .. 9.75857 | 0.44992 .. 8.87991 |

For I0 fixed-slew, port release 5..5.2 ns leaves 4.65632 ns removal and 4.73947 ns
recovery margin. These values do not license replacing an unknown source with a
passing minimum-delay constraint. F0 drive windows are especially conditional:
the source violates electrical limits, so extrapolated cell timing is not
characterized closure evidence even where its recovery/removal slack is positive.

## Source sensitivity and electrical limits

All scenarios use identical data constraints and the same netlist per point.
This table shows removal slack; complete recovery, gating and other results
remain in the JSON.

| Point | Rising 0..0.2, slew / drive | Rising 0.2..2, slew / drive | Falling 0..0.2, slew / drive |
| --- | --- | --- | --- |
| E0-fifo2 | -0.29368 / -0.24049 | -0.09368 / -0.04049 | 4.70632 / 4.75951 |
| E0-fifo4 | -0.29368 / -0.24352 | -0.09368 / -0.04352 | 4.70632 / 4.75648 |
| I0-cell | -0.34368 / -0.30898 | -0.14368 / -0.10898 | 4.65632 / 4.69102 |
| I0-descriptor | -0.34368 / -0.29828 | -0.14368 / -0.09828 | 4.65632 / 4.70173 |
| F0-cell | -0.34368 / -0.92827 | -0.14368 / -0.72827 | 4.65632 / 4.07173 |
| F0-descriptor | -0.34368 / -0.44992 | -0.14368 / -0.24992 | 4.65632 / 4.55008 |

The phase-only change shifts recovery/removal margins by half a cycle, without
improving the allocator selection path. A weak source is not uniformly better
for removal: additional driver delay also worsens slew and the library's
required removal time. In the F0 cell drive case, modeled root load is
1414.35461 fF, virtual driver delay 3.39682 ns and root slew 3.23030 ns.
Removal is worse than fixed slew despite a later modeled arrival. The falling
reference has positive recovery/removal, but `rst_n → _11379_/Z → _12463_/ZN →
available` arrives at 8.68921 ns against the 7.9 ns output requirement:
**−0.78921 ns**. This is a reset output-budget miss, not a recovery/removal miss.

| F0 map / mode | Worst electrical violation | Actual / limit | Slack |
| --- | --- | --- | --- |
| Cell / slew | `_12990_/ZN` capacitance | 14.55184 / 11.48220 fF | −3.06964 fF |
| Descriptor / slew | `_5629_/ZN` capacitance | 12.31177 / 10.47130 fF | −1.84047 fF |
| Cell / drive | `rst_n` slew | 3.23030 / 0.19853 ns | −3.03176 ns |
| Cell / drive | `rst_n` capacitance | 1414.35461 / 60.65371 fF | −1353.70093 fF |
| Descriptor / drive | `rst_n` slew | 0.83672 / 0.19853 ns | −0.63819 ns |
| Descriptor / drive | `rst_n` capacitance | 365.44641 / 60.65371 fF | −304.79269 fF |

F0 drive evaluates the reference library far beyond its stated transition/load
limits; its numerical sensitivity is not evidence of a physically realizable
source. F0 fixed-slew timing also retains mapped data-net capacitance misses.
E0 FIFO and I0 electrical checks pass locally. Root loads 1038/267 and asynchronous
pins 1036/266 expose separate reset-distribution work; no physical reset
distribution is designed or implemented here. Data fanout and clock counts remain separate in the durable map
records. Architectural disposition from the original allocator report is not
reversed by changing reset phase.

## Intended rejection qualification and captured failures

Each negative ran against the actual E0 FIFO2 and I0 cell mapping, except reversed
envelopes, which the shared configuration validator rejects before STA. The
mapped prerequisites still qualify separately. Fourteen intended detections pass:

| Invalid case, on both representative maps | Required detector / scope |
| --- | --- |
| Missing reset min | `R01_MISSING_RESET_min`; no implicit max-to-min default |
| Missing reset max | `R01_MISSING_RESET_max` |
| Reversed envelope | `Reversed constraint envelope` from configuration validation |
| Wrong reset port | `R01_RESET_PORT` after the wrong-port query |
| Blanket reset false path | `R01_TIMING_EXCEPTION`, before applying the exception |
| Disable reset timing (would drop required checks) | `R01_TIMING_EXCEPTION`, before applying the timing disable |
| Malformed SDC command | OpenSTA diagnostic naming `r01_deliberate_bad_command` |

The guards reject attempts to suppress checks; the run does not apply exceptions
and then count an empty report as passing. Unit tests independently reject absent
removal/recovery sections, wrong check types, asynchronous-category overlap,
missing endpoint inventory, numbered/unnumbered diagnostics and electrical-report
omissions. Negative slack remains valid evidence and fails the applicable model
closure category. These tests do not establish production functional correctness.

An early reporting audit failed because OpenSTA's data-pin query included
asynchronous endpoints. Its interrupted first run is rejected; the pre-repair
source patch, reproducer and failing section are retained in
[the capture](../../verification/failures/20261114T180339679856Z-reset-effects-category-audit-0a15aba01500.json)
and [bounded report](../../verification/failures/r01-category-overlap.txt).
A synthetic unit-test fixture also failed due to inconsistent port/source
bounds; [its pre-repair capture](../../verification/failures/20261114T180543146180Z-r01-synthetic-window-test-97f8dbd5434c.json)
retains the source and output. Both are classified verification defects, not RTL
bugs. The subsequent clean `98993b0` matrix completed, but the accepted run above
also incorporates explicit electrical aggregation at `952e1ee`. No numerical
constraint was changed to improve a result.

## Reproduction and follow-on studies

Use the prepared pinned environment; no setup/download occurs in measurement.
`make doctor` passed on current main before tool-dependent work and is also
required by the focused runner. Reproduce the accepted executable revision:

```sh
git switch --detach 952e1ee60785c60de35e368c2327063464abedc6
make doctor
make reset-timing RUN_ARGS='--timeout 1800'
python3 tools/check_repository.py
python3 tools/check_light.py
```

On a delivered branch, use the same commands without detaching. The final
repository check passes, and lightweight syntax/unit qualification passes all
121 tests. Tool execution is bounded at 1800 s per map and 300 s per STA; empty
selection and unavailable tools cannot yield measurement PASS. Functional
regression/formal and RTL lint are NOT_RUN for R01: no RTL, independent DV,
functional source list or hardware behavior changes. Hosted CI is NOT_RUN.

The common generator is usable without copying SDC logic:

```sh
python3 tools/timing_constraints.py --study p08-production-r01 --scenario fall-reference-r01 --mode slew --output .build/p08-r01.sdc
python3 tools/timing_constraints.py --study p12-production-r01 --scenario fall-reference-r01 --mode drive --output .build/p12-r01-drive.sdc
```

The focused R01 report script targets standalone FIFO/pool ports. P08/P12 must
adapt reporting queries to their actual integrated endpoints, preserve full path
coverage and connect the real consumer/storage boundaries. Establish physical
source provenance or retain unresolved/conditional closure; report recovery,
removal, reset effects, fanout and electrical limits separately. New budgets or
sources require new config/scenario identities committed before execution.
Original allocator SDC/results and historical FIFO reports/JSON remain unchanged.
