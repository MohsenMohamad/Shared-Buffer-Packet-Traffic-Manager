# Review preparation: guidance and CI infrastructure

This stabilization change schedules follow-up work and gives each CI run one validated toolchain preparation producer. It changes no hardware, production API, packet interface, statistics scope or existing result JSON. P03 and later hardware remain paused pending stabilization and reevaluation.

## Starting state and tested sources

The workspace was clean on branch `work`. After fetching origin, `chore/review-preparation` was created from `a473b8c535d02b50b23604047f1bae64638c89df`, integrated main containing P00/P01/P02/P06/P07 (PRs #1–#5). Guidance was committed and pushed separately as `cd6b8fd8e7f19b70175df89d45b3b765409ad7fd`; CI infrastructure followed in `820a9a3cde3a06bfb9ce56a118ae634a18e258bc`. Transfer-permission and hosted-bootstrap fixes are in `a24434319cb0717d7bb59b6f24b5a863418c7f96`. [PR #6](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/pull/6) targets main and remains unmerged.

The first local cold/transfer study used the initial CI helper and permission fix. After inherited build flags were added to compatibility in `2e067a5`, actual preparation rejected the older key and performed a second full cold build. Its subsequent transfer/capability run records tested revision `1038680eed13b9a659b1270b2ec97f0cd090413c` with this results-report edit dirty; tested helper, setup, unit and workflow files match that committed revision. The bootstrap composite shell and preparation-output extraction were also executed locally. Hosted rows below distinguish PR heads from actual prepared checkouts; local results are not relabeled as clean executions of a later commit.

No prior stage branch was continued and no existing workspace edits were overwritten. Existing P01/P02 JSON remains byte-for-byte unchanged; [historical retrieval guidance](../documentation.md#historical-p01p02-retrieval) preserves tested SHAs, dirty-source qualifications and PR/workflow associations.

## Local executed results

| Check | Result | Scope and measurements |
| --- | --- | --- |
| Actual empty-installation preparation | PASS | Locked downloads, native build and doctor; final setup 411.686 s, doctor 1.174 s, two build workers. |
| Compatible preparation reuse | PASS | Same key; only restore-doctor, no setup invocation; final replay 3.634 s including inventory. |
| Setup-input invalidation | PASS: expected rejection | Disposable comment appended to `tools/setup.sh` changed the key; strict consumer validation rejected compatibility before tool use. Original bytes restored. |
| Build-flag invalidation | PASS: expected rejection | Setting `CXXFLAGS=-O2` rejected compatibility before any tool execution; all six inherited build flags are also covered by unit key checks. |
| Missing installation file | PASS: expected rejection | Temporarily missing `.tools/activate.sh` rejected as incomplete; original restored. |
| Actual producer-to-consumer transfer | PASS | 164,005,213-byte zstd archive, 2.234 s packaging and 2.428 s extraction with preserved permissions; producer directories moved aside, consumer installed at the same absolute path without Verilator build sources. |
| Restored-tool validation | PASS | Payload hashes/modes/links plus real version, C++20 and solver probes; 3.223 s after transfer. |
| Consumer capability selection | PASS | 12 cases: doctor, repository, 22 unit tests, lint/intentional compile rejection, formal prove/cover/intended mutation and mapped synthesis/max-min STA. Fixture scope only; 8.804 s. |
| Cache unit cases | PASS, eight cases | Input/ABI/build-flag identity changes, malformed manifests, missing/changed files/modes/links, cold/reuse, rejection/rebuild, failed doctor and permission-preserving tar extraction under umask 077. Mocked subprocess cases do not establish real installation. |
| Actionlint 1.7.12 and shell checks | PASS | Workflow/reusable-call syntax; composite shell syntax and installed-prerequisite execution. |

The initial local transfer without `tar -p` was correctly rejected after restrictive umask changed file modes. The fix preserves permissions and has a real tar regression. This rejected transfer is not counted as a passing capability result.

The installation is sealed before consumers run. Consumers never save a modified installation back into the shared cache. SBY/Yosys may create additional Python bytecode during tests; the strict pristine-payload inventory detects those additions on a later local validation. Six disposable post-test bytecode files were removed and pristine validation passed again; no tool source or sealed measurement was altered.

## Tools and configuration

Local host: Debian 13.6, Linux x86-64, glibc 2.41, GCC 14.2.0, Python 3.12.14. Actual doctor qualified Verilator 5.054, Yosys 0.52 at `fee39a3284c90249e1d9684cf6944ffbbcbb8f90`, SBY 0.71, Z3 4.13.3 and OpenSTA 2.0.17. The source-archive Verilator build reports an ancestor-checkout build suffix; dependency provenance is the locked upstream archive hash, not that suffix.

| Input | SHA256 |
| --- | --- |
| `tools/dependencies.json` | `ee72fb11c5b7ebeecb0d207936969810358cf6ff36b236f6d28799730397db15` |
| `tools/packages.lock.json` | `ec22b5d0f143c715413302386e67c49b23e138f91560590fd3f3a125ab99922a` |
| `tools/toolchain_cache.py` | `320c45aa1a9b3231dd959166bac6db2fd484662c568052e16f3ae8c4a54dbeed` |

The local compatibility key is `tm-tools-v1-e61116da1ecde5a3ec56b91e51db82c422a725c649fd25ec8c1c7abd7fd16e9e`. It deliberately differs from Ubuntu hosted keys because host ABI and checkout layout differ. No dependency pins or existing hardware results were changed.

## Hosted observations

| Run | PR head / actual prepared checkout | Observed result |
| --- | --- | --- |
| [43034957268](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/43034957268), PR | `820a9a3cde3a06bfb9ce56a118ae634a18e258bc` | FAIL before preparation: Ubuntu mirror DNS failure installing redundant host help2man. Repository passed; all heavy consumers skipped after producer failure. No cache/toolchain result was produced. |
| [43036053712](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/43036053712), PR | Head `a24434319cb0717d7bb59b6f24b5a863418c7f96`; checkout `7e9b20047e4208949f8d23ac9343e1a83b6708a9` | Canceled by a newer candidate after successful cold preparation/cache save and successful repository, all three capabilities, contracts, storage and E0 CSR checks. F0 CSR and foundation canceled, not passed. |

Completed-run logs for 43036053712 explicitly show an exact miss, `Toolchain cold: PASS`, cache save under `tm-tools-v1-6998f68077a71635d38962321465e71a8fc50ffc29008e9fb6fe77d973200807`, and consumer downloads/validation in separate workspaces. GitHub cache metadata confirms creation under `refs/pull/6/merge`. The checkout SHA above is from the actual checkout log and matches the fetched PR merge ref; it is not an integrated-main claim.

The failed first producer demonstrates failure gating, not successful distribution. Its missing-artifact diagnostic step also failed because bootstrap produced no build files. The replacement bootstrap checks installed native tools and leaves Autoconf/Bison/Flex/help2man to the locked sysroot. The tightened build-flag identity passed real hosted cold preparation in [43038559554](https://github.com/MohsenMohamad/Shared-Buffer-Packet-Traffic-Manager/actions/runs/43038559554), PR head `1038680eed13b9a659b1270b2ec97f0cd090413c`, actual prepared checkout `cd0eecd1b07af969bc015eb28bfae883714d3595`. The jobs API records `Record cold preparation` successfully, and cache metadata records new key `tm-tools-v1-280e18129eee44b1d2d40afa78f9e2360022375d3e0540e6a639980e53e4929f` under the same PR ref. This is observed key invalidation/cold recovery after the compatibility-input change; a compatible hosted hit is still to be verified. Heavy consumers received and validated the installation; their complete suite outcomes are not claimed in this snapshot. Individual live-job log/artifact downloads returned HTTP 403; completed-run logs were retrievable and inspected. The new outcome/revision step also exposes validated source and actual checkout through the jobs API. PR caches do not establish main reuse; main is not merged or tested by this task.

## Reproduction and raw artifacts

Use [the toolchain guide](../implementation/toolchain.md#one-ci-preparation-producer) for cold setup, cache scope and the hosted cold/hit/invalidation/consumer procedure. Commands executed locally include:

```sh
CXX=g++-14 python3 tools/toolchain_cache.py prepare --jobs 2
CXX=g++-14 python3 tools/toolchain_cache.py prepare --jobs 2
CXX=g++-14 python3 tools/toolchain_cache.py validate
python3 -m unittest discover -s tests/toolchain -p test_toolchain_cache.py -v
CXX=g++-14 python3 tools/run.py ci --test doctor --test repo --test unit --test lint --test formal --test synth --jobs 2
work/actionlint -color
make repo-check
git diff --check
```

Archive transfer uses `tar --zstd -cf ARCHIVE .tools .deps/downloads .deps/src/uvm .deps/liberty.lib`, then `tar --zstd -xpf ARCHIVE` into an emptied installation at the identical absolute checkout path. Preserve any installation before the destructive disposable test. The invalidation probe appends `\n# disposable compatibility probe\n` to `tools/setup.sh`, runs `key` and expects `validate` to report compatibility mismatch; restore the exact original bytes afterward. The missing-file probe temporarily renames `.tools/activate.sh`, expects missing-payload rejection, then restores it. Unit tests independently reproduce the rejection and transfer invariants.

Raw local setup records are in `.build/setup-cache/`; the cold/reuse/transfer records, separate logs and archive are in `.build/cache-abi-check/`. The final consumer summary is `.build/runs/ci-2026-11-11T142457.513734+0000-d5eaa9b1/summary.json`, with actual dirty-source digests and per-case commands. These bulky files stay outside Git. The tables above retain the meaningful outcomes after artifact expiry; rerun the documented commands to regenerate raw evidence.
