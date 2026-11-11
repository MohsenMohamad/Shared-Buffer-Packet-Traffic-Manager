# P06: production CSR and coherent statistics

P06 implements the P01 register/statistics APIs and qualifies the CSR portion
of G2 with an independent architectural-event fixture. No CPU platform or
packet datapath is instantiated. Real event wiring and whole-system IDLE
generation remain P09/P10 checks; this report does not close the complete G2,
RST or parameter/integration gates. Requirement metadata records the local
component PASS separately; top-level CSR rows remain NOT_RUN until wiring tests.

The tested implementation is `26bad4d0bdf52d8657b1a4cd3ea14061ab54e2cc`, based on
integrated revision `0901ad7fead69eb6e56c49c1e8a75a125d414a91` (P01, P02 and
P07 present). Later delivery changes add evidence/documentation only.
[Machine-readable evidence](P06-registers.json) records source digests, exact
commands, parameters, seeds, tool versions, timestamps and raw artifact paths.

## Results

| Check | Result | Boundary |
| --- | --- | --- |
| `csr`, E0 seed 17 | PASS | Production 64-bit and reduced 8-bit arithmetic; 17 observed rollovers; unchanged 64-bit ABI. |
| `csr`, F0 seed 23 | PASS | All sixteen queues, 22 reduced-width rollovers and OR reduction of four input-stall samples. |
| Coupled-channel defect | PASS | Expected UVM `CSR_AW_W_INDEPENDENCE` detection and formal `a_aw_independent` counterexample. |
| FP-CSR | PASS | Unbounded k-induction at E0 dimensions; protocol/atomicity, not statistics arithmetic. |
| CSR covers | PASS | Seven covers reached within depth 24; reachability, not safety proof. |
| `contracts`, all six profiles | PASS | Both pinned frontends, valid variants, invalid elaborations and independent batching. |
| Python runner/registration tests | PASS | Executable suite/source ownership, nonempty selection and preserved P00 routes. |
| Storage formal compatibility | PASS | Existing production cell proof/cover/mutation with 900-second per-task limit. |

The coupled-channel mutation changes AWREADY to require WVALID in a disposable
production source copy. The simulation source presents independently timed
channels; a missing response, generic crash or unrelated fatal cannot qualify
the negative case. Formal has no AW/W coupling or BREADY/RREADY fairness
assumption. See [production proof scope](../../formal/csr/README.md).

## Directed behavior

| Requirements | Executed checks |
| --- | --- |
| CSR-01 | ID/version/capabilities and reset values; every implemented queue/register; all invalid qid encodings through 255; large unknown addresses, holes and mapped misalignment; RO/WO behavior. |
| CSR-02/03 | AW first, W first, simultaneous capture and 24-cycle separation; 12 order/stall/read-overlap bins; held second requests until B/R retire; stable stalled responses; simultaneous read/write; reset with AW only, W only and stalled B/R. |
| CSR-04 | Zero strobes on mapped/RO/locked addresses; all four byte lanes; merge before validation; atomic rejection of 0x1000 quantum merged with byte-zero 0x40; ignored CTRL bits versus actual busy-disable writes. |
| CSR-05 | Six explicit busy contexts with empty queues/full resources; reservation without queue publication; running and disabled-busy configuration locks; drain/reconfigure; sticky diagnostic error survives CLEAR_STATS. |
| CSR-06 | Every-clock comparison of complete live/shadow state; coherent pre-event snapshots and snapshot/read collisions; low/high read order; stalled statistics read across a new snapshot; per-queue/global events; simultaneous format events; merged H high-water and abort physical returns; TX bytes on each accepted beat, including nonfinal/stalled beats; rollover and clear/reset. |

The fixture owns resource bookkeeping and six busy inputs for ingress, RX,
drain, cleanup, TX/FIFO and outstanding reads. IDLE also requires empty queues
and restored resources. It does not infer IDLE from queue emptiness, use DUT
success to create expected events, or verify packet ownership/payload. The
passive model derives requests from observed handshakes and statistics from the
fixture's event/stall/retirement inputs. See the
[execution decision](../decisions/0005-csr-events.md) and
[bench entry point](../../dv/README.md).

## Coverage and qualifications

| Profile / counters | Reads / writes | Wraps | Registers lines | Registers branches | Statistics lines | Statistics branches | Bus cross |
| --- | --- | --- | --- | --- | --- | --- | --- |
| E0 / 64 bits | 565 / 540 | 0 | 42/42 | 54/54 | 18/18 | 18/18 | 12/12 |
| E0 / 8 bits | 565 / 540 | 17 | 42/42 | 54/54 | 18/18 | 18/18 | 12/12 |
| F0 / 64 bits | 1195 / 1184 | 0 | 42/42 | 54/54 | 18/18 | 18/18 | 12/12 |
| F0 / 8 bits | 1195 / 1184 | 22 | 42/42 | 54/54 | 18/18 | 18/18 | 12/12 |

Saved production line, branch, expression and toggle counters plus all twelve
mandatory bus cross bins are retained in the JSON evidence and raw coverage
databases. Functional bins must be nonzero for the suite to pass. Coverage
collection is not whole-system coverage closure.

Four register-expression holes are redundant upper-bound/interval combinations
after mapped-address validation (lines 30, 87, 122 and 160). The two statistics
expression holes are negative/over-capacity merged H values (line 82), excluded
by the valid event fixture and its resource assertions.

The default Verilator wide-array limit omits internal 64-bit counter-array toggle
points; the E0 8-bit run instruments both arrays. F0's larger per-queue array
also exceeds that default toggle limit at reduced width. Payload/tag fields,
upper
resource-occupancy bits and full-width counter toggles are not closed by this
fixture. No extracted FSM coverage is reported for the holding-flag design.
The 8-bit run tests wrap without claiming to execute 2^64 events.
Verilator execution is two-state. FP-CSR leaves live/shadow inputs arbitrary;
it does not prove statistics arithmetic, actual event wiring or IDLE generation.

The supplemental cell recovery cover initially exceeded 240 seconds under
concurrent compiler load. The unchanged check passes with
900 seconds, including recovery at step 35; the earlier timeout is
not treated as a passing result.

## Reproduction and artifacts

Use the checksum-locked native setup described in the
[toolchain guide](../implementation/toolchain.md):

```sh
make setup JOBS=2
make regression RUN_ARGS='--profile E0 --test csr --seed 17'
make regression RUN_ARGS='--profile F0 --test csr --seed 23'
make formal-rtl RUN_ARGS='--test csr --timeout 240'
for profile in F0 F1 I0 I1 E0 E1; do
  make regression RUN_ARGS="--profile $profile --test contracts --seed 17"
done
python3 -m unittest discover -s tests/contracts -v
make test-unit
make repo-check
make formal-rtl RUN_ARGS='--test cell --timeout 900'
```

The CSR workflow is configured for E0/F0 and the local protocol proof, retaining
`csr-<profile>-<sha>` artifacts for fourteen days. Local raw evidence resides in
the unique `.build/runs/` directories listed in the JSON: separate stdout/stderr,
per-case manifests, immutable executable copies/configuration, transaction
logs, coverage databases and expected-defect waveforms/first-failure records.
Compiler objects live separately under `.build/csr-objects/`; deleting that
cache forces a full rebuild without changing the test. Exact commands regenerate
raw evidence after hosted artifacts expire.
