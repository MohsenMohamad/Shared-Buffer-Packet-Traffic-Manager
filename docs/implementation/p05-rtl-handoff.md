# P05 fresh RTL task entry

This handoff provides public APIs, commands and scope only. Preparation has unresolved independence acceptance due to pre-model dependency
RTL/results reads. Independent review must resolve this before relying on its
provenance. Preparation merge establishes no hardware acceptance and does not automatically start RTL.
The maintainer assigns a fresh RTL task under the
[root workflow](../../AGENTS.md#preparation-implementation-and-independent-qualification).

Use the current `origin/main` after the scoped preparation PR is merged.
Freeze the exact base and new RTL head in that task. The initial preparation
base is `8d66a92768f2c72236171731262563814e875352`; the initial expected-behavior
commit is `db8bbec`. Prepared execution is recorded at `290760486b627701a0555c0b98a27e4332ec9957`;
later report/status edits do not replace that tested identity. The preparation
PR head supplies the later delivered DV source identity.
Do not consult withdrawn work or independent DV internals/implementation reports.

Public APIs are `tm_packet_ram_api`, `tm_metadata_api` and `tm_tx_api` in
`rtl/include/tm_module_ports.sv`, using `tm_fixed.sv`, `tm_types.svh`,
`tm_parameters.svh` and `tm_validate.svh`. Behavioral authority remains the
P05 card and its linked specifications. RAM requests at edge e respond at e+L,
L=1/2, with no response ready. Metadata uses the documented finite write/read
ports and pre-state reads. Read issue and external retirement are distinct;
cell/descriptor release follows external cell/packet-final transfer.

Opaque preparation commands:

```sh
make regression RUN_ARGS='--profile E0 --test memory-tx-oracle --seed 17 --timeout 120'
make regression RUN_ARGS='--profile I1 --test memory-tx-bench --seed 17 --timeout 120 --build-timeout 600'
make regression RUN_ARGS='--profile I1 --test memory-tx --seed 17 --timeout 120'
```

The last command must return NOT_IMPLEMENTED during preparation. A future DV
owner enables it only with an actual-source binding and exact RTL/DV identities.
No natural RTL symptom has been discovered in this preparation; no RTL ran.
Model/tool failures and planted faults do not establish a hardware defect.

Candidate DV combines named RTL/DV commits in an isolated worktree and records
the resulting tree plus any resolution/dirty diff. Keep unmerged RTL repairs on
its RTL PR; merged-source defects use a fix PR. Candidate qualification precedes
RTL merge, followed by merged-source confirmation. Only independently qualified
scope can satisfy an acceptance gate; preparation tests cannot substitute.

## Exact candidate qualification handoff

The original pre-merge candidate verdict is PASS for
`479b5c1ceee2eee8db58d863bd5de5e20305cc8c`, combined with main
`a4df0dd61802355e91b4c0c96e57b79241c86851` and the independent DV inputs
recorded in [the public result](../results/P05-candidate-public.json).
All six named profiles cross latency 1/2, FIFO depth 4/8 and seeds 17/31/53
plus seed-17 replay. No production RTL defect is confirmed. The historical
preparation independence qualification above remains unchanged.

At the prepared installation path, combine the named RTL with the DV branch
in a disposable detached checkout, leaving both submitted branches separate.
The opaque public entry preserves child failure status and emits interface-level
stimulus and expected/observed results separately from private DV diagnostics:

```sh
python3 tools/p05_candidate.py --rtl-revision 479b5c1ceee2eee8db58d863bd5de5e20305cc8c --profile I1 --seed 17
python3 tools/p05_candidate.py --rtl-revision 479b5c1ceee2eee8db58d863bd5de5e20305cc8c --profile E0 --formal --timeout 600
```

[RTL PR #24](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/pull/24)
must include the merged interface-test repair and pass its own required CI.
Record any new RTL identity and run affected qualification before applying this
verdict to it. [DV PR #26](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/pull/26)
remains available for exact merged-source confirmation after maintainer-controlled
RTL integration. Neither PR is merged by this qualification task.

## Refreshed candidate applicability

**PRE-MERGE APPLICABILITY PASS** applies to
`dc7682f16dcdba05b1f2b7d80b1bf11732d17c47`. Independent comparison finds
unchanged production/header, contract, registration, parameter and build/proof
inputs. Existing six-profile simulation and reduced safety evidence therefore
apply without relabeling their original execution SHAs. Sixteen fresh I1
production runs and saved-coverage checks pass, with identical public trace
hashes to the original corresponding runs. The refreshed mapping in
[the public result](../results/P05-candidate-public.json) records the exact
combined identity and new interface-level measurements.

```sh
python3 tools/p05_candidate.py --rtl-revision dc7682f16dcdba05b1f2b7d80b1bf11732d17c47 --profile I1 --seed 17 --jobs 2
```

PR #24 has incorporated repair #25 and its full CI passed all 28 jobs in
[43591176269](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/43591176269).
Its scoped pre-merge DV gate is satisfied. The historical preparation provenance
caveat remains unchanged. After maintainer-controlled RTL integration, keep
PR #26 open for exact merged-source confirmation before its own merge.

## Actual merged-source confirmation

**MERGED-SOURCE PASS** applies to PR #24's actual merge/current main
`3ede1a5e40791ff00d98a0faa8389154d632e0c5`. Its entire tree equals the qualified
head's tree. Tested DV/combined revision is
`fd129b1e0d7566c460962b6869aa2274f7a24fa9`, tree
`c1c3033decc4fc1b16aab4702ac9da4714ef2353`, after a clean normal main merge.
Sixteen fresh integrated I1 runs, saved-coverage validation and accounting pass;
old execution identities remain unchanged. [Public results](../results/P05-candidate-public.json)
retain the actual merge mapping and source-free interface measurements.

```sh
python3 tools/p05_candidate.py --rtl-revision 3ede1a5e40791ff00d98a0faa8389154d632e0c5 --profile I1 --seed 17 --jobs 2
```

The current pin selects the merged source. Earlier commands above are historical.
Required final DV full CI and relevant main CI are recorded on PR #26 before its
maintainer merge handoff. Historical provenance, reduced FP-TX/composition limits,
P12B structural comparison and absence of code-coverage closure remain unchanged.
No production repair or PR #26 merge is performed by this task.
