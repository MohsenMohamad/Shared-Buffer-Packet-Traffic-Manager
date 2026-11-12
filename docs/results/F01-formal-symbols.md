# F01 symbolic-input qualification

The explicit top-level-input recipe is qualified on the pinned Slang stack at
witness widths **1 and 4**. A witness is initially arbitrary and constrained only
to equal its preceding sample once history is valid. History is initialized once
and never reset with the DUT. Time-varying stimulus and later resets remain
arbitrary. P03 can use the [formal rule](../spec/formal.md#selected-frontend-and-arbitrary-inputs)
and [source example](../../formal/symbolic/symbolic_inputs.sv) directly.
This is frontend/monitor qualification, not FP-QUEUE, FP-ORDER or integrated
traffic-manager validation. Production RTL and tool pins are unchanged.

## Configuration and observed results

The [compact record](F01-formal-symbols.json) retains tested revision/dirty state,
source/configuration/lock digests, tool identities, per-case outcomes and negative
identities. Tests ran from branch `fix/formal-symbolic-inputs`, based on current
`origin/main` **6b7d556**. Dirty executions identify their actual input hashes;
no later commit is substituted as their tested revision.

The final combined runner check passes **30 cases**, including doctor, ten
focused guard/classification tests and the **73-test** unit suite. The separate
bridge passes 49 cases. Tools are Yosys 0.70+post
`28ba3cb926fe376fa05ebfc1b921747d011d4557`, SBY v0.71, Z3 5.4.1
`145c0c51570a357cc558ce898ce77573ba9d4fbf`, sv-elab
`9dcee13ea3862347e1715dc51f63e9f845cdd222` and Slang
`545f88b2ed3a2d20325fbd17413af177a6bca72f`.

The engine is `smtbmc z3`, proof mode uses unbounded k-induction with depth 12,
and cover mode searches 12 steps. Both widths use two low startup-reset samples
and arbitrary reset thereafter. Shared immediate monitors assert adjacent-sample
constancy and constancy on a later falling reset. Reachability covers require
zero/all-ones witnesses, changing stimulus, and an active interval followed by
reset while the witness is held and stimulus changes. There is no witness range
restriction, DUT-derived witness or progressing-sink assumption.

| Configuration, each W=1 and W=4 | Constancy assertion | Change cover | Other covers |
| --- | --- | --- | --- |
| Native `read_verilog` / internal `anyconst` | Proved unbounded | Unreached through 12 | Zero, all-ones, stimulus change, later reset reached |
| Slang / undriven decorated internal | Expected `a_constant` counterexample | Expected false `c_witness_change` reach | Not used as production evidence |
| Slang / input witness + stability assumption | Proved unbounded, including reset | Unreached through 12 | All four reached |
| Slang / same input recipe with `OMIT_STABILITY` | Expected `a_constant` counterexample | `c_witness_change` reached | All four reached |

Native lowering contains one `$anyconst`; Slang decoration contains none. The
recipe instead retains a witness input. Each proof retains two named assertions;
the change task retains one named cover and reachability retains four. Native,
decorated and missing-assumption variants retain one startup-reset assumption;
the stable recipe retains that assumption plus witness stability. The runner
checks these inventories and input ports before accepting a result.

The saved later-reset trace has reset samples **0,0,1,0** with a fixed witness
and changing stimulus. Zero and all-ones reachability at W=1/4 demonstrates
initial choices **0/1** and **0/15** in independent traces, not a single witness
changing between the values. The missing-assumption negative does demonstrate
an actual witness change. Constancy across later resets is an unbounded assertion;
unreachable cover status itself is only the stated bounded search.

`symbolic_functions.sv` is separately classified as **FRONTEND_REJECTION /
UNSUPPORTED**, requiring both `unknown system name '$anyseq'` and
`unknown system name '$anyconst'`. That expected diagnostic passes its check;
it does not count as a proof or a detected semantic violation. Missing tools,
frontend/engine errors, UNKNOWN, timeout, wrong assertions and absent traces
cannot satisfy the named semantic negative checks.

## Source policy and legacy boundary

The formal registry checks registered sources, explicit headers and transitive
literal includes before staging. Ten focused policy/classification tests cover
attribute lists, multiline/comment/escaped-name variants, function syntax,
macro aliases/continuations and command defines, inactive branches, unlisted nested headers,
missing/macro includes, comments/string literals, fake registry exemptions and
crashes/unrelated assertions. Token concatenation and unresolved expansion fail
closed. This checker does not rewrite RTL.

Only the canonical `storage_formal` and `csr_formal` paths may use the existing
anyseq adapter. Its supported declarations/header remain narrow, and its output
must contain no unqualified symbols. A same-named copy has no exception.
Unsupported-feature fixtures stay outside production registration; adding an
exception field to the registry does not admit one.

`make bridge RUN_ARGS='--timeout 900'` passes all **49** cases, including the
existing diagnostic fixtures and both directions of complete assumption-trace
inclusion for all five legacy configurations. Assertion/assumption/cover counts
remain cell **25/1/5**, descriptor **17/1/8**, FIFO2 **11/1/6**, FIFO4 **13/1/6**,
CSR **17/7/7**. Named property inventories and source locations still match.
Startup-reset constraints, arbitrary later resets/actions and immediate-monitor
semantics are retained. Bridge control-state equalities remain proved invariants,
not assumptions. Equivalence alone is not a hardware specification proof.

The legacy dimensions are cell capacity 16 / ID width 5 / one return, descriptor
capacity 8 / ID width 4 / two returns, FIFO depth 2/4 / beat width 137, and CSR
N_RX=1, N_Q=2, N_CELL=16, N_DESC=8, CELL_BYTES=16, MAX_PACKET_BYTES=128.

The previous production unbounded/cover/mutation and unrelated simulation,
mapping and timing results are reused from the [representation report](rtl-representation.md),
including hosted run **43210080611**, clean tested merge
`e64d6dea9002a1d44fcc5548865b22498abfd286`. That exact object was fetched and
26 relevant RTL, legacy harness/property, SBY, driver, profile and lock files
compared byte-for-byte with no differences. The existing configuration entries
are unchanged; F01 adds a separate qualification entry and an extra standalone
source/header. Adapter output and assumption/property equivalence are checked
by the new bridge execution. No unrelated hardware study was rerun or relabeled
as execution on this branch. The original **−0.09 ns reset-removal failure**
remains recorded; F01 makes no timing claim.

## Reproduction and artifacts

Use the repository's already prepared locked installation; setup is separate
from test execution. No tool upgrade is required.

```sh
make formal-symbols RUN_ARGS='--timeout 120'
make bridge RUN_ARGS='--timeout 900'
make test-unit
make repo-check
```

The recipe gate can also run through the existing CI selector:

```sh
make ci RUN_ARGS='--test formal-symbols --test unit --test repo --timeout 120'
```

The hosted capability matrix includes `formal-symbols`; hosted execution of this
change is not claimed. `.build/runs/<run>/` retains each manifest, exact argv,
separate stdout/stderr, staged SBY configuration, symbolic/property inventory,
engine statuses and VCD/witness traces. The compact record names the runs and
semantic identities needed to reproduce these results after raw artifacts expire.
