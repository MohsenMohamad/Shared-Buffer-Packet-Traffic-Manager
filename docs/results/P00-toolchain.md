# P00 toolchain qualification

P00 records a **PASS for G0 toolchain capability qualification** using the
pinned native open-source combination. The checks exercise independent
fixtures; they do not validate traffic-manager RTL, close functional
coverage or establish physical timing signoff.

## Recorded results

These are prior qualification results, verified against saved manifests and
hosted CI during the documentation cleanup. They were not newly executed
for the cleanup.

| Capability | Recorded result | Qualification |
| --- | --- | --- |
| Setup and doctor | PASS | Source installation, repeat setup, locked versions/integrity, C++20 and Z3 SAT/UNSAT |
| Repository contracts | PASS | 52 document/data requirements; no hardware evaluated |
| Runner and lint | PASS | 14 runner tests and fixture lint; expected error rejections are listed separately below |
| UVM | PASS | Timed transactions, constrained randomization and deterministic seed replay |
| Coverage collection | PASS | Saved code and functional counters inspected; unhit bins remain |
| Formal prove and cover | PASS | Unbounded counter step/hold proof by k-induction; wrap cover reached within bound 20 |
| Mapping and STA | PASS | Liberty/ABC mapping and constrained max/min paths on a synthetic pre-layout fixture |
| Combined local gate | PASS | All 18 capability cases, including the expected negative checks |
| Hosted capability jobs | PASS | UVM, formal and synthesis jobs, including all three evidence uploads |

The successful negative checks require the intended diagnostic or
counterexample, rather than an unrelated failure. Their raw nonzero exits
remain in the manifests.

| Expected negative check | Recorded result | Observed evidence |
| --- | --- | --- |
| Compiler syntax-error rejection | PASS, expected rejection | Compiler error; exit 1 |
| Seeded held-data defect | PASS, expected detection | `TM_CAP_STABILITY_FAIL` assertion and nonempty VCD; exit 1 |
| Seeded increment-by-two defect | PASS, expected detection | Counter `a_step` assertion counterexample and VCD; exit 2 |
| Malformed runner input | TOOL_ERROR, expected rejection | Invalid jobs argument; exit 1 |

| Unsupported or unexecuted check | Recorded status | Boundary |
| --- | --- | --- |
| Portable X/Z reproducer | UNSUPPORTED, exit 1 | Executed separately; Verilator cannot retain four-state values |
| UVM DPI/backdoor services | NOT_RUN | Outside the qualified `UVM_NO_DPI` baseline |
| Traffic-manager hardware and later commands | NOT_IMPLEMENTED | Later implementation tasks; `regression` exits 1 |

## Revisions and evidence

| Evidence | Revision |
| --- | --- |
| Initial integrated base | `e3d40edf942e00fb5c0e5d9a86a480e8931c3ac7` |
| Clean local qualification | `6e1365a47eb11bd5caa72e92a0016ef019c6e8e4` |
| Hosted PR head | `ebe317b747b969b29e28fd7076550ae829281837` |
| Hosted test-merge checkout | `97995e476387482eceefb734a18b7e3c3a81b16c` |

The initial base contained the specification seed, relevant contracts,
implementation plan, dependency pins and supplied UVM fixture. P00 had no
predecessor implementation dependency. Changes between the local qualified
revision and the hosted PR head affect CI artifact inclusion and results/status
documentation, not the executable fixtures or runner. This cleanup changes
presentation only; it does not extend qualification to a new executable revision.

The [machine-readable evidence](P00-toolchain.json) preserves exact tool
versions, dependency/constraint/fixture digests, UTC times, return codes and
coverage counters. Source pins are in
[dependencies.json](../../tools/dependencies.json) and
[packages.lock.json](../../tools/packages.lock.json); the
[compatibility decision](../decisions/0001-native-toolchain.md) records the
host ABI/compiler requirements and accepted upstream warnings.

### Hosted evidence

The recorded [Toolchain capabilities run](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/42923313318)
and [Repository run](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/42923313330)
completed successfully for the hosted PR head above. During cleanup, GitHub
run/job status and artifact metadata were accessible. The UVM checkout log
confirmed the test-merge revision, and all three uploads were successful.
The archived payloads were not downloaded again for this cleanup.

Artifact names use `toolchain-<capability>-<test-merge checkout>`.

| Capability artifact | Size (bytes) | Download |
| --- | --- | --- |
| UVM | 135507836 | [Artifact 13813810454](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/42923313318/artifacts/13813810454) |
| Formal | 140214 | [Artifact 13812543836](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/42923313318/artifacts/13812543836) |
| Synthesis/STA | 76427 | [Artifact 13812254755](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/42923313318/artifacts/13812254755) |

The artifacts were nonempty and unexpired when checked; hosted retention is
14 days. After expiry, regenerate outputs with the reproduction commands
below at the recorded revision. The earlier
[hosted attempt](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/42921984603)
failed artifact upload; that unexpected failure is not counted as a passing
qualification result.

### Local evidence

The combined local run is retained under
`.build/runs/ci-2026-11-10T232033.801563+0000-8882afad/`. Each case has a
`manifest.json`, separate stdout/stderr and relevant raw artifacts. The
saved manifests identify the clean local revision above. Earlier failed
attempts retain their original statuses in separate run directories.

## Measured fixture results

### UVM and coverage

Successful and deliberately unsatisfiable randomization both executed.
The held-data seeded defect is accounted for in the negative-check table.

| Run | Seed | Transactions | Transaction digest | Hit functional bins |
| --- | --- | --- | --- | --- |
| First positive | 17 | 64 | `6f53ba93` | 17/19 |
| Second positive | 19 | 64 | `fe8b80f9` | 17/19 |
| Independent replay | 17 | 64 | `6f53ba93` | 17/19 |

Each positive `coverage.dat` has 17/26 hit owned line points, 8/11 expression
points, 11/32 branch points and 141/142 toggle points. Queue, length and cross
counters each account for 64 samples. Seed 17 misses queue-0/short and
queue-1/short crosses; seed 19 misses queue-0/short and queue-2/short. The
tool reports a weighted 94.4%; raw counters, including unhit bins, establish
collection capability rather than coverage closure.

### Formal and implementation analysis

The three-bit enabled counter's step/hold properties are proved by
k-induction without environment assumptions. The wrap cover is reached at
step 9 within bound 20. Cover and seeded-defect counterexample VCDs are
saved. These properties do not prove the UVM pipe or a production module.

| Mapped fixture measurement | Recorded value |
| --- | --- |
| Cells | One `DFF_X1` and one `XOR2_X1` |
| Library area | 6.118 |
| Clock period | 10 ns |
| Max slack | 8.89 ns |
| Min slack | 0.22 ns |

STA uses the pinned Nangate45 typical Liberty with explicit min/max I/O
delays, transition and load constraints. The max/min reports qualify the
tool flow on this tiny pre-layout fixture, not traffic-manager timing or
physical signoff.

## Reproduction

Use the [setup and command guide](../implementation/toolchain.md) for host
prerequisites and runner options. Check out a recorded qualified revision
above to reproduce its evidence. The prior successful invocations were:

```sh
bash tools/setup.sh --jobs 2
make setup JOBS=2
make doctor
make repo-check
make test-unit
make lint
make test-uvm-smoke JOBS=2
make formal-smoke
make synth-smoke
make ci JOBS=2
```

The UVM invocation uses profile `toolchain`, default seeds 17 and 19, an
independent seed-17 replay and the held-data seeded defect. Run timeout is
120 seconds and UVM build timeout is 1200 seconds. Each new invocation
writes a fresh directory under `.build/runs`; setup logs are in `.build/setup`.

These prior diagnostic invocations intentionally returned nonzero statuses
listed in the result tables:

```sh
python3 tools/run.py four-state --jobs 2
python3 tools/run.py regression
python3 tools/run.py ci --jobs invalid
```

## Documentation and main synchronization checks

The presentation cleanup and subsequent merge of `main` change documentation
only. The merge combines candidate
`2c86376cfa8f972f903187dae32fb1f7d4121dde` with the implementation-instruction
update at `91bd45ecac600e707832f964638a4176c2061559`, preserving both histories.
The incoming instructions are retained as committed on `main`.

Newly executed on the combined candidate: `make repo-check`, Markdown
structure/link/table/code-fence checks, and `git diff --check`. Tree comparisons
confirm that every non-Markdown file, including executable inputs, dependency
locks, CI configuration and the evidence JSON, matches the pre-merge candidate.
The combined diff was inspected against both parents and the updated PR base.

Toolchain installation, UVM, formal and STA qualification were not rerun because
their executable inputs did not change. Their actual tested revisions remain
in the evidence table above. This updated candidate requires a fresh review
and maintainer integration before P01 begins.
