# P05 preparation source exposure

Confirmed: early preparation tooling read dependency RTL and results before the expected-model commit. Independence is **not established**; later passing tests do not cure this breach. This is an exposure record, not an RTL defect or a cosmetic qualification.

Base: `8d66a92768f2c72236171731262563814e875352`. The initial doctor manifest starts at `2026-11-13T17:32:39.566462+00:00`; expected-model commit `db8bbec00d87de4b632fd92781f773ba0c464ee6` is at `2026-11-13T17:36:25Z`. The recorded early commands were `make doctor`, `python3 tools/check_repository.py` and `python3 tools/check_light.py`.

## Exact RTL inventory

The saved doctor manifest proves byte reads of every path below for SHA-256. The light formal-source policy also read the full text of all registered production/formal sources and headers. The earlier count of “11 implementation-file digests” was wrong: outside `rtl/include/` it counted nine dependency implementations, one top declaration and one guidance file.

| Path | Classification | Additional reconstructed read |
| --- | --- | --- |
| `rtl/AGENTS.md` | guidance | full-text-markdown-validation |
| `rtl/common/tm_axis_rx_fifo.sv` | dependency-implementation | full-text-symbolic-policy-scan |
| `rtl/csr/tm_axil_regs.sv` | dependency-implementation | full-text-symbolic-policy-scan |
| `rtl/csr/tm_statistics.sv` | dependency-implementation | full-text-symbolic-policy-scan |
| `rtl/include/tm_fixed.sv` | public-declaration | full-text-symbolic-policy-scan |
| `rtl/include/tm_module_ports.sv` | public-declaration | full-text-symbolic-policy-scan |
| `rtl/include/tm_parameters.svh` | public-declaration | full-text-symbolic-policy-scan |
| `rtl/include/tm_types.svh` | public-declaration | full-text-symbolic-policy-scan |
| `rtl/include/tm_validate.svh` | public-declaration | full-text-symbolic-policy-scan |
| `rtl/pools/tm_bitmap_pool.sv` | dependency-implementation | full-text-symbolic-policy-scan |
| `rtl/pools/tm_cell_pool.sv` | dependency-implementation | full-text-symbolic-policy-scan |
| `rtl/pools/tm_desc_pool.sv` | dependency-implementation | full-text-symbolic-policy-scan |
| `rtl/queue/tm_desc_links.sv` | dependency-implementation | full-text-symbolic-policy-scan |
| `rtl/queue/tm_queue_ctrl.sv` | dependency-implementation | full-text-symbolic-policy-scan |
| `rtl/scheduler/tm_drr.sv` | dependency-implementation | full-text-symbolic-policy-scan |
| `rtl/tm_top.sv` | public-declaration | full-text-symbolic-policy-scan |

## Exact results inventory

All 33 files below were byte-read for hashing. Markdown results were also fully read for link/fence validation; JSON results were fully read and parsed by the light syntax check. Hashing and parsing are file-content reads even when their bodies are not printed.

- `docs/results/C01-ci-economy.md`
- `docs/results/F01-formal-symbols.json`
- `docs/results/F01-formal-symbols.md`
- `docs/results/P00-toolchain.json`
- `docs/results/P00-toolchain.md`
- `docs/results/P01-contracts.json`
- `docs/results/P01-contracts.md`
- `docs/results/P02-storage-primitives.json`
- `docs/results/P02-storage-primitives.md`
- `docs/results/P03-dispatch-guard.json`
- `docs/results/P03-independent-dv.json`
- `docs/results/P03-independent-dv.md`
- `docs/results/P03-queues.json`
- `docs/results/P03-queues.md`
- `docs/results/P04-independent-dv.json`
- `docs/results/P04-independent-dv.md`
- `docs/results/P04-scheduler.json`
- `docs/results/P04-scheduler.md`
- `docs/results/P06-registers.json`
- `docs/results/P06-registers.md`
- `docs/results/P07-followup-stimulus.json`
- `docs/results/P07-followup-stimulus.md`
- `docs/results/P07-verification-foundation.json`
- `docs/results/P07-verification-foundation.md`
- `docs/results/README.md`
- `docs/results/allocator-scaling.json`
- `docs/results/allocator-scaling.md`
- `docs/results/failure-capture.md`
- `docs/results/modern-toolchain.json`
- `docs/results/modern-toolchain.md`
- `docs/results/review-preparation.md`
- `docs/results/rtl-representation.json`
- `docs/results/rtl-representation.md`

## P05 finding and evidentiary limits

No separate P05 implementation or P05 results path occurs in the saved early manifest or original production/formal registration. `rtl/include/tm_module_ports.sv` contains the permitted public P05 APIs; `rtl/tm_top.sv` is recorded as a declaration in the base contract. These declaration reads are recorded explicitly and are not relabeled as implemented P05 RTL. Absence of a P05-named results path does not establish absence of P05 content: generically named reports such as `docs/results/review-preparation.md` were read by tooling and their content was not reopened for this audit. P05 results-content exposure is therefore **unknown**, while all 33 report-file reads are confirmed. There is no evidence in this reconstructed set of a P05 implementation read. This is narrower than claiming no exposure: nine dependency implementations and the results above were read.

The early tool outputs supplied hashes/check statuses rather than RTL/report body excerpts to the assistant. That distinction does not undo the prohibited reads, prove that expectations were unaffected, or make this preparation clean-room. No syscall-level trace exists. Temporary fixtures and every possible unlogged read cannot be exhaustively reconstructed. No historical RTL or results body was reopened for this audit.

The [machine inventory](P05-source-exposure.json) preserves per-file hashes, read classifications, the original formal-input registration, the complete manifested hash set and evidence location. Tool mechanisms are established by the original `tools/evidence.py`, `tools/check_repository.py`, `tools/check_light.py`, `tools/registry.py`, `tools/formal_symbols.py` and `tests/toolchain/test_formal_symbols.py`; the scanners were not rerun during this audit.

## Disposition

Keep PR #23 draft and treat independence acceptance as unresolved. The implemented preparation and its executed test results remain reviewable, but they must not be described as independently accepted preparation. An independent provenance review or a newly authorized preparation effort must resolve this before that gate is claimed. Do not erase the exposure or weaken the source-isolation rule to obtain acceptance.
