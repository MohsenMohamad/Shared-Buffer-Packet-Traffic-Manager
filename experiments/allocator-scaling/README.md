# Production allocator characterization definition

Freeze this definition in a pushed commit before executing synthesis or timing.
This is the standalone [P02 scaling card](../../docs/implementation/tasks/P02-followup-scaling.md),
using integrated main `410a174` and the accepted [toolchain](../../docs/decisions/0006-modern-toolchain.md)
and [representation](../../docs/decisions/0007-rtl-representation.md). No allocator
algorithm, API, allocation latency or functional/formal contract is changed.

## Frozen matrix and boundary

| Profile | Cells / ID / count bits / returns | Descriptors / ID / count bits / returns | Role |
| --- | --- | --- | --- |
| E0 | 16 / 4 / 5 / 1 | 8 / 3 / 4 / 2 | Small production reference |
| I0 | 32 / 5 / 6 / 1 | 16 / 4 / 5 / 2 | I0 analysis target |
| E1 | 64 / 6 / 7 / 1 | 32 / 5 / 6 / 2 | Scaling reference |
| F0 | 1024 / 10 / 11 / 1 | 256 / 8 / 9 / 2 | Exploratory F0 screening |

Use each entire registered profile, without the extra ID encoding bit used by
P02 invalid-ID tests. F1/I1 only change payload read latency, which the pools do
not use, so they are not redundant study points. Every point reads the registered
`synthesis` source set with Slang and selects the actual production wrapper as
top. Flatten its real bitmap kernel. Keep all wrapper outputs live at top ports;
never tie off actions, loop available ID back to allocation ID, expose only an
encoder, replace the bitmap, or add synthesis assumptions. Unused API record
fields can disappear; record their mapped load counts. All alloc/return control
and ID fields remain independent inputs, including invalid actions.

Area includes bitmap flops, free-count and sticky-error flops, lowest-free
selection, allocation-ID checking, return lookup/validation, duplicate detection
(two-return pool), merged updates and mapping buffers. It excludes FIFO, payload,
metadata links/descriptors, reservation U/R/A/H, admission/consumer and observation
logic outside these wrappers. Expected mapped state is capacity + count width +
one sticky error bit. Report actual mapping cells/state and all live outputs.

## Locked conditions and commands

[config.json](config.json) owns selection and numeric criteria. Dependency and
package identities remain in the existing locks; require doctor PASS and the
pinned Liberty SHA256 `8d540a4d4cf6d09d27c87ad067857a9c0c2eeb023ab7a56e058cd3113db4e9b1`.
Qualified Yosys 0.70/Slang, bundled ABC and OpenSTA 3.2.0 identities must match
`tools/dependencies.json`; no tool upgrade or fallback is part of this study.

[mapping.ys.in](mapping.ys.in) is the exact mapping sequence: registered Slang
read, flat `synth -noabc`, `dffunmap`, Liberty flop mapping and Liberty ABC with
[abc.constr](abc.constr). ABC uses its pinned default constrained script, BUF_X1
drive and 10 fF load, without an ABC delay-target override. Save the generated
script and ABC invocation in artifacts. Do not mix inference passes into this
read. Inspect mapped completeness and bitmap/count/error state retention.

[timing.sdc](timing.sdc) uses Nangate45 typical at 1.10 V / 25 C, ns/fF, ideal
10 ns clock, 0.10 ns uncertainty, 0.2/2 ns min/max input and output delays,
10 fF per output and no exceptions. Reset remains constrained. Primary `slew`
mode specifies 0.05 ns on every nonclock input; `drive` sensitivity uses the
library BUF_X1/Z driver instead. Analyze identical netlists in both modes.
Clock tree and wire parasitics are absent; primary and sensitivity results must
be reported separately. This differs from the historical FIFO fixture conditions.

[timing.tcl](timing.tcl) checks missing clocks/delays, loops and unconstrained
endpoints with qualified OpenSTA, demands min/max timing paths for every output,
and reports max/min, recovery/removal and electrical checks. A numbered or
unnumbered warning/error, absent report/path, unmapped cell, wrong state count,
missing output or timeout invalidates evidence; completion alone is insufficient.
Do not interpret negative slack as a tool failure or conceal it with exceptions.
Report the worst constrained path across all groups and the bitmap-register to
`available_id` selection path, plus `available` and `free_count` paths, with actual
start/endpoints, arrival and slack in ns. Selection arrival includes clock-to-Q
and mapped combinational delay; it is not a consumer path or Fmax guarantee.
Count direct sink pins per net, separating clock/reset and data; report buffering,
high-fanout drivers and selection logic depth from actual timing reports.

```sh
export CXX=g++-14
source .tools/activate.sh
make doctor
make allocator-scaling RUN_ARGS='--timeout 1800'
make regression RUN_ARGS='--profile I0 --test pools --seed 17'
make regression RUN_ARGS='--profile F0 --test pools --seed 17'
make formal-rtl RUN_ARGS='--test cell --test descriptor --timeout 900'
make repo-check
make test-unit
```

Raw manifests/scripts/netlists/reports go under ignored `.build/runs/`; commit
compact measurements and exact revision/dirty state, command/configuration/source/
lock/script/library digests and tool identities in a subsequent results commit.
Keep historical reports and JSON unchanged. New numbers are comparable only
across this matrix under the same mode, mapping and IO conditions, with area
normalized by entries when capacities differ. Historical P02 has no matched
mapped allocator timing; FIFO and surrogate-encoder numbers are not comparisons.

## Predeclared decisions

These are investigation criteria, not permission to redesign or new F0 acceptance
requirements. Apply them to the original matrix even if a later separately
committed amendment adds experiments; explain any amendment before its new runs.

| Criterion | Interpretation / action |
| --- | --- |
| Coverage/integrity checks above | Blocking evidence requirement. Failed point is invalid/incomplete; repair/reexecute or report it without PASS. |
| I0 max/min setup/hold/recovery/removal slack >= 0 ns, both drive modes | Existing I0 10 ns analysis target applied locally; a miss requires investigation. Standalone success cannot close integrated I0 acceptance. Reset timing is included. |
| F0 selection arrival <= 6 ns, both modes | Exploratory screen leaves 1.9 ns margin before the 7.9 ns output required time; not an agreed F0 acceptance gate. A miss prompts investigation. |
| Area/entry <= 2 times I0 area/entry, separately for each pool | Exploratory scaling screen against excessive superlinear mapping; a miss prompts investigation. No total-TM area budget is asserted. |
| Any data net > 64 sink pins, reset > 256 sink pins | Exploratory buffering/physical-risk screen; clock is counted separately, ideal here. A miss prompts fanout/selection review, not an automatic architecture change. |

Conclude **retain** only if valid evidence passes these standalone screens, while
still requiring P08 integration measurement. Conclude **investigate alternatives**
if any valid screen misses; identify the measured cause and focused evaluations
(e.g. mapping/buffering, selection structure or pipeline tradeoffs). A miss never
mandates hierarchical/banked/free-list replacement. Conclude **require integration
evidence** when no standalone miss is established but consumer uncertainty or
invalid/incomplete evidence prevents a retention judgment. Keep correctness and
pre-state allocation/returns, lowest-ID selection, merged deltas, sticky errors,
throughput and APIs unchanged in this PR.

No implemented receive/admission consumer currently exists. Do not invent one or
claim a register stub reproduces its critical path. Isolation omits consumer
fanout, admission predicate, resource accounting, metadata write selection and
action feedback. At P08 remeasure the actual production receive/admission path
at I0 and **1024 cells** with identified constraints, connected consumers and
complete path coverage. Isolated results are not a guaranteed timing bound on
that path. P03 and allocator redesign remain separate reviewed work.
