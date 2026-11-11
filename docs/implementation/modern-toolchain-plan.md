# Modern toolchain inventory and qualification plan

The starting revision is `66f6d0d730238709e2a11faab221f24dc5a81ee9` (fresh `origin/main`). This document commits selection criteria before qualification. P03+ stays paused. Production representation conversion is a separate PR; disposable copies qualify the next task. Historical reports and the fixed Nangate45 Liberty remain unchanged.

## Candidate sources

Upstream discovery on 2026-11-11 is separate from normal setup. Final locks must use exact source commits and archive SHA256s; tags here name candidate releases, not floating installation inputs.

| Dependency | Existing pin | Current upstream / proposed candidate | Role / reason |
| --- | --- | --- | --- |
| Yosys | 0.52, `fee39a3284c90249e1d9684cf6944ffbbcbb8f90` | release 0.70, `28ba3cb926fe376fa05ebfc1b921747d011d4557` | Current synthesis/formal core; compare native and slang frontends |
| ABC | Debian Yosys 0.52-2 bundle | exact ABC source shipped with selected Yosys release | Mapping engine must match selected Yosys; record gitlink/source digest |
| yosys-slang | absent | release 2026-11-09, `2cfcfbe388b1d8b32e4d31da3449db5bf747c00c` | Rich SV frontend; all transitive slang/fmt dependencies pinned before build |
| Verilator | 5.054 archive SHA256 `18658731b46922ef660bcb650be0aa503d751e5c17eb9d4644fdfabb11835198` | 5.054 release, `bbb60a403932a9f695cb6ff001ceb73de6ad9234` | Already current release; retain unless qualification identifies a concrete defect |
| UVM | 2020.3.1, `78c06547a2a0a29b3dc9dcafae62b75b2ff61544` | Investigate 2020.3.2; official GitHub latest release/tag currently exposes 2020.3.1 | Verify authoritative Accellera distribution before choosing; no fabricated release |
| SBY | 0.71, `79fc9eddca5e33a28cc2f2cd19c9825efd9a7255` | same 0.71 release and commit | Current published tag; preserve diagnostic native path |
| Z3 | 4.13.3-1 Debian | release 5.4.1, `145c0c51570a357cc558ce898ce77573ba9d4fbf` | Formal and constrained randomization; verify actual executable output |
| OpenSTA | 2.0.17 / Debian `0~20191111gitc018cb2+dfsg-1.1` | authoritative `parallaxsw/OpenSTA` source 3.2.0, `c7f04667369f1f7bfeb9eebb381fd8c63267bb21` | Upstream CMake declares 3.2.0; OpenROAD fork latest release is obsolete 2.2.0 |
| CUDD | absent | resolve exact 3.0.0 release commit/archive | Required OpenSTA BDD library; static build to isolated prefix |
| Eigen | absent | resolve a compatible pinned published source/package | Required OpenSTA headers; compile only, record newer upstream and compatibility rationale |
| Tcl / SWIG | Tcl 8.6.16; SWIG absent | locked Tcl 8.6.16 plus pinned SWIG | OpenSTA runtime / wrapper generation; Tcl readline optional and disabled |
| fmt | absent | audited transitive source pin or disabled fetch via working C++20 std::format | No implicit CMake network fetch; record whichever path is actually used |
| Liberty | Nangate45 typical `9275989ffcad3e17a1be884b31e5c9bb4a42c06e`, SHA256 `8d540a4d4cf6d09d27c87ad067857a9c0c2eeb023ab7a56e058cd3113db4e9b1` | unchanged | Comparable pre-layout mapping/max/min timing; no physical signoff |
| Host | Linux x86-64, glibc >=2.38, GCC exactly 14.2.0, Python 3.11+ | Linux x86-64, compatible locked-binary ABI, working C++20 compiler including std::format; actual compiler/runtime part of cache identity | A compiler patch number is not a language requirement; verify compile and execution |
| Build tools | Make/Bash/Perl/Git/curl/dpkg-deb/Python host, locked Autoconf/Bison/Flex/CMake/Ninja | retain only tools exercised by chosen recipes; exact packaged/source downloads below | No wholesale retention of unused development bundles |

## Existing package audit

Every row names the old exact package pin. Candidate retention is not a qualification result. Packages not used by the selected recipe must be removed from the active lock; old sources remain reproducible through the starting commit and retained control installation.

| Package | Old version | Role | Proposed disposition |
| --- | --- | --- | --- |
| autoconf | 2.72-3.1 | Verilator/CUDD configure generation | retain exact pin initially; verify necessity in cold build |
| automake | 1:1.17-4 | CUDD build generation | retain exact pin initially; verify necessity in cold build |
| autotools-dev | 20240727.1 | configure host metadata | retain exact pin initially; verify necessity in cold build |
| bison | 2:3.8.2+dfsg-1+b2 | Verilator/OpenSTA/Yosys parser generation | retain exact pin initially; verify necessity in cold build |
| cmake | 3.31.6-2 | Yosys/slang/OpenSTA configure | retain exact pin initially; verify necessity in cold build |
| flex | 2.6.4-8.2+b4 | Verilator/OpenSTA/Yosys scanners | retain exact pin initially; verify necessity in cold build |
| help2man | 1.49.3 | Verilator manual generation; development only | remove from active bundle; source-built tools or unused optional development dependency |
| libboost-filesystem-dev | 1.83.0.2+b2 | old packaged Yosys Boost dependency; no selected source-build requirement | remove from active bundle; source-built tools or unused optional development dependency |
| libboost-filesystem1.83-dev | 1.83.0-4.2 | old packaged Yosys Boost dependency; no selected source-build requirement | remove from active bundle; source-built tools or unused optional development dependency |
| libboost-filesystem1.83.0 | 1.83.0-4.2 | old packaged Yosys Boost dependency; no selected source-build requirement | remove from active bundle; source-built tools or unused optional development dependency |
| libboost-python-dev | 1.83.0.2+b2 | old packaged Yosys Boost dependency; no selected source-build requirement | remove from active bundle; source-built tools or unused optional development dependency |
| libboost-python1.83-dev | 1.83.0-4.2 | old packaged Yosys Boost dependency; no selected source-build requirement | remove from active bundle; source-built tools or unused optional development dependency |
| libboost-python1.83.0 | 1.83.0-4.2 | old packaged Yosys Boost dependency; no selected source-build requirement | remove from active bundle; source-built tools or unused optional development dependency |
| libboost-system-dev | 1.83.0.2+b2 | old packaged Yosys Boost dependency; no selected source-build requirement | remove from active bundle; source-built tools or unused optional development dependency |
| libboost-system1.83-dev | 1.83.0-4.2 | old packaged Yosys Boost dependency; no selected source-build requirement | remove from active bundle; source-built tools or unused optional development dependency |
| libboost-system1.83.0 | 1.83.0-4.2 | old packaged Yosys Boost dependency; no selected source-build requirement | remove from active bundle; source-built tools or unused optional development dependency |
| libboost1.83-dev | 1.83.0-4.2 | old packaged Yosys Boost dependency; no selected source-build requirement | remove from active bundle; source-built tools or unused optional development dependency |
| libffi-dev | 3.4.8-2 | old packaged Python/Boost development | remove from active bundle; source-built tools or unused optional development dependency |
| libffi8 | 3.4.8-2 | old packaged Python/Boost dependencies | remove from active bundle; source-built tools or unused optional development dependency |
| libfl-dev | 2.6.4-8.2+b4 | scanner build support | remove from active bundle; source-built tools or unused optional development dependency |
| libfl2 | 2.6.4-8.2+b4 | scanner runtime if generated scanner links libfl | remove from active bundle; source-built tools or unused optional development dependency |
| libgmp-dev | 2:6.3.0+dfsg-3 | old packaged Yosys Boost dependency; no selected source-build requirement | remove from active bundle; source-built tools or unused optional development dependency |
| libgmpxx4ldbl | 2:6.3.0+dfsg-3 | old packaged Yosys Boost dependency; no selected source-build requirement | remove from active bundle; source-built tools or unused optional development dependency |
| libreadline-dev | 8.2-6 | optional interactive Yosys build | remove from active bundle; source-built tools or unused optional development dependency |
| libreadline8t64 | 8.2-6 | optional interactive runtime | remove from active bundle; source-built tools or unused optional development dependency |
| libtcl8.6 | 8.6.16+dfsg-1 | OpenSTA runtime | retain exact pin initially; verify necessity in cold build |
| libz3-4 | 4.13.3-1 | old solver runtime; not linked by selected command-line solver | remove from active bundle; source-built tools or unused optional development dependency |
| m4 | 1.4.19-8 | Autoconf macro processor | retain exact pin initially; verify necessity in cold build |
| ninja-build | 1.12.1-1 | CMake build executor | retain exact pin initially; verify necessity in cold build |
| opensta | 0~20191111gitc018cb2+dfsg-1.1 | old STA control | remove from active bundle; source-built tools or unused optional development dependency |
| pkg-config | 1.8.1-4 | development dependency discovery | remove from active bundle; source-built tools or unused optional development dependency |
| python3-click | 8.2.0+0.really.8.1.8-1 | old packaged Yosys Python CLI dependency | remove from active bundle; source-built tools or unused optional development dependency |
| python3-colorama | 0.4.6-4 | old packaged Yosys CLI color support | remove from active bundle; source-built tools or unused optional development dependency |
| tcl-dev | 8.6.16 | unversioned Tcl development selector | remove from active bundle; source-built tools or unused optional development dependency |
| tcl8.6-dev | 8.6.16+dfsg-1 | OpenSTA compile headers/stubs | retain exact pin initially; verify necessity in cold build |
| tcl8.6 | 8.6.16+dfsg-1 | OpenSTA Tcl encoding build tool | retain exact pin initially; verify necessity in cold build |
| tcl | 8.6.16 | unversioned Tcl runtime selector | remove from active bundle; source-built tools or unused optional development dependency |
| yosys-abc | 0.52-2 | old mapping control | remove from active bundle; source-built tools or unused optional development dependency |
| yosys | 0.52-2 | old synthesis/formal control | remove from active bundle; source-built tools or unused optional development dependency |
| z3 | 4.13.3-1 | old solver control | remove from active bundle; source-built tools or unused optional development dependency |
| zlib1g-dev | 1:1.3.dfsg+really1.3.1-1+b1 | compressed input/traces; build headers and shared runtime | retain exact pin initially; verify necessity in cold build |

GitHub Actions pins are audited together with the producer/consumer workflow. Existing checkout v7.0.1 `3d3c42e5aac5ba805825da76410c181273ba90b1`, cache v4.2.3 `5a3ec84eff668545956fd18022155c47e93e2684`, upload v4.6.2 `ea165f8d65b6e75b540449e92b4886f43607fa02`, download v4.3.0 `d3f86a106a0bac45b974a628896c90dbdf5c8093` are candidates pending current upstream verification. Exact replacement commits belong in workflows and the final inventory; no `@main`/`@latest`.

## Required capabilities and rejection criteria

1. Cold install, repeat setup, sealed exact restore, transferred consumer validation, tampered/missing inputs and compiler/ABI/recipe invalidation. Never accept a cache key alone or combine old runtime paths with the selected installation. Setup and tests stay separate; preserve upstream notices and record source/build identities.
2. Compare the supplied audit at `a48286d51b9dd195b18388e9ee3c70c8403ccc0b` with independent cases. Test ANSI headers, package imports/qualification, `$bits(type)`, type parameters/parameter-dependent records, heterogeneous instances, unpacked arrays/ports, interfaces/modports and memory inference. Separate parsing, elaboration, complete synthesis and simulation. Cover all six registered profiles, invalid contracts and boundary widths. Invalid forward references must still reject.
3. Formal qualification uses unchanged production DUT behavior and existing property identities/counts. Check symbolic attributes/functions and equivalent unconstrained top-level inputs, initial/reset/two-edge reset/later arbitrary reset, `$past`, async conversion, diagnostics/source locations, all covers and intended mutations. Prove assumption equivalence rather than deleting constraints or assertions. Keep native read_verilog diagnostic control.
4. Run all P00 UVM/constraint/replay/coverage/assertion/formal/mapping/max-min STA gates, P01 six-profile plus invalid elaborations, P02 component simulation/prove/cover/mutations, P06 E0/F0 frontdoor/statistics and production formal, P07 agents/sequences/analysis/scoreboards, negatives/replay/saved coverage. Fixture evidence remains separate from production claims.
5. Synthesis checks include packed records/arrays, memory ports/latency/inference, signed widths, latch/combinational checks, ABC mapping semantics and mapped netlist integrity. STA checks include fixed library units, clock/IO/load/drive constraints, max/min paths, unconstrained endpoints and bad library/netlist/SDC/error-plus-completion cases. Missing parasitics/multiple libraries cannot yield measured noise/variation/multicorner claims.
6. Register the chosen frontend in real source/runner paths. Parser changes must preserve exact intended failure detection. Missing executables, ignored constructs, empty selections, unrelated crashes, timeout, unproven equivalence and unreachable covers fail their obligations. Investigate counterexamples before assigning tool/harness/RTL cause.
7. Publish a capability-to-design decision table with exact affected locations, benefits/tradeoffs and remove/retain/investigate dispositions. Audit every task including P11 subdivisions/follow-ups and applicable specs/guidance/status. Schedule representation before allocator scaling; preserve P02/P07 follow-ups before P08 and P09/P10 measurements before P11. Leave launch pack untouched.
8. Get required hosted CI green on the final candidate and identify actual tested SHA/run links. Demonstrate shared producer and consumers and cache reuse. Historical evidence remains unchanged; pending/failed/unsupported/unexecuted results never become PASS.

## Execution and delivery

Commit this plan first, then lock candidates before measuring them. Build only in ignored project directories, leaving `/workspace/toolchain` as the old control. Publish frequent branch checkpoints and one PR; integration remains with the maintainer. Final results record exact source/tree/dependency identities, commands/configurations/seeds, numeric measurements and hosted links. Representation follow-up receives an executable tested recipe and explicit remaining limitations.

## Locked candidate resolution

Accellera's official download page supplies UVM 2020.3.2 even though its GitHub release API still names 2020.3.1. The active archive is the unmodified official 3.2 distribution. Yosys 0.70 integrates read_slang; prefer the release's mutually pinned sv-elab/slang sources over adding an independent plugin ABI. The standalone current sv-elab 2026-11-09 remains an investigation candidate if the integrated release bridge fails qualification. This is dependency selection, not a claim that either frontend has passed production formal.

The GitHub v0.70 release asset's `.gitcommit` reports `0c11ea098be065e585a90a06e7b7da49936cf231`, whereas the peeled release tag is `28ba3cb926fe376fa05ebfc1b921747d011d4557`. Use the exact peeled-tag source and its exact gitlinks instead of relabeling the asset. The actual archive build may report `0.70+post`; source identity and version output are both recorded. Setup disables enclosing-checkout Git discovery rather than letting the traffic-manager revision impersonate a dependency revision.

| Source | Selected release / identity | Archive SHA256 |
| --- | --- | --- |
| verilator | 5.054; `bbb60a403932a9f695cb6ff001ceb73de6ad9234` | `18658731b46922ef660bcb650be0aa503d751e5c17eb9d4644fdfabb11835198` |
| uvm | 2020.3.2; `official distribution` | `4664ac015f23c72106dd785906aa874d70932ea63f74b85de1e32fa5339c15eb` |
| liberty | NangateOpenCellLibrary_typical.lib; `9275989ffcad3e17a1be884b31e5c9bb4a42c06e` | `8d540a4d4cf6d09d27c87ad067857a9c0c2eeb023ab7a56e058cd3113db4e9b1` |
| sby | 0.71; `79fc9eddca5e33a28cc2f2cd19c9825efd9a7255` | `683953197cef986832fe02423bfb7726b0261f2af153a09899501ba5c92052c7` |
| yosys | 0.70; `28ba3cb926fe376fa05ebfc1b921747d011d4557` | `6a134c366622795f98c9b3e0588dde625f96ae5b80304813f73f2c261e317602` |
| abc | bundled; `6c5104934c90eb3cdef9ea063318f7588908a185` | `d0448ed85efdd2a411f2ca6638122983bc3d361498a74ba5b1ecc651bac2b018` |
| cxxopts | bundled; `4bf61f08697b110d9e3991864650a405b3dd515d` | `6a198fdd59e95fe8d4e4ba2a5583e72e610e725192e9ccc2a06a23dfc8243a13` |
| fmt | bundled; `a00f82c6b66dcae15503ba19c1598b2733057dea` | `360099778b1bf7088769d07b51b59474450dfae3cd63c333d2e3f3903d666a52` |
| tomlplusplus | bundled; `a43ad3787293f4a46b1d70c0924b5a25d10e79fc` | `46995ddc5baff656a2d527d4329a382c14412f963fa0edf418319280e8435c40` |
| boost_regex | bundled; `2b3ac0834f31086c6e3c0e0ceb8516e427d5c39d` | `5674d9802e115d3ed12c9a1301716f7f0debabf46478449f1112e2a21e6eeecf` |
| slang | bundled; `545f88b2ed3a2d20325fbd17413af177a6bca72f` | `2d424f4280c879daaf05a2e78efd6928c350cc3ac086da59b872a305a277f7b8` |
| sv_elab | 2026-10-13; `9dcee13ea3862347e1715dc51f63e9f845cdd222` | `2d54c9e186496ad192e9c77046b0571ce3fdde42a1aad5c4e63829d888331d14` |
| symfpu | bundled; `5d5e50867437fe5cabd6ab5aad3b3808ec86701f` | `8dbddea1d26cf04d0f320c57929829847835249985ae6992b08a78b088472f6e` |
| cudd | 3.0.0; `f54f533303640afd5dbe47a05ebeabb3066f2a25` | `dbe6b90f8745bf1f755953b76f1c639e07f7ee079f4abf18c871ae878f47431d` |
| swig | 4.5.1; `88649f559942c29a228fa783dd01581e217bcb20` | `1f54fbbcba9224389b5ae9ede91365677e652be33b81ca3671a79221f7e2f56e` |
| opensta | 3.2.0; `c7f04667369f1f7bfeb9eebb381fd8c63267bb21` | `e7cb5c7750317308da920918e078e3ef669cb1aa4bb26d68a66278bc50500e6c` |
| cmake | 4.4.5; `official distribution` | `ed85135c5a5135b45e50423cb406dea04ca3338da0b8ef3c9ede963559680be0` |
| eigen | 5.0.1; `bc3b39870ecb690a623a3f49149a358b95c5781d` | `5f6557d1aca6e959a4b955c55f2935261fd30de59c0c79e35bc6d5cbe1de22d1` |
| z3 | 5.4.1; `145c0c51570a357cc558ce898ce77573ba9d4fbf` | `b548bac48ef2452b4e09ea2945cf4b011d5f43fcf39e4799df268ee7e0769d85` |

CMake 4.4.5 is the current official self-contained Linux distribution, avoiding the old CMake package's undeclared runtime/data dependencies. Eigen 5.0.1 and SWIG 4.5.1 are current published source releases. CUDD 3.0.0 remains upstream's newest published release. OpenSTA uses working C++20 std::format, so its optional fmt FetchContent fallback must not execute. SWIG's optional regular-expression parser is disabled; OpenSTA's generated Tcl wrappers do not use it. Tcl readline, Yosys interactive editing, Yosys Tcl/Python embedding and DPI are optional development integrations outside the selected required production flow, so their old Boost/readline/ffi/Python package bundle is removed. Header-only regex/fmt/toml/cxxopts/symfpu are locked at the Yosys release gitlinks and all licenses stay with the sources.

The selected upstream Z3 x86-64 binary requires glibc >=2.39, met by Ubuntu 24.04 and this Debian 13 host. Compiler compatibility is checked with a compiled/executed C++20 std::format probe and full compiler/runtime cache identity, rather than an exact GCC patch rejection. Build dependencies retained from Debian are Autoconf 2.72, Automake 1.17, autotools metadata, Bison 3.8.2, Flex 2.6.4, M4 1.4.19, Tcl 8.6.16 headers/interpreter/runtime and zlib 1.3.1 headers/runtime. They have exact existing archive locks, are used by concrete source recipes, and are not a claim of a hermetic host OS. Tcl 8.6 is the selected OpenSTA runtime ABI; changing to Tcl 9 requires separate upstream compatibility qualification.

Current Actions discovery confirms checkout v7.0.1 remains current; cache v6.1.0, upload v7.0.2 and download v8.0.2 replace the old majors together. Their published source commits are locked in workflow uses. Hosted execution must validate their current input/output semantics.

SBY imports Click at runtime. The dependency audit therefore replaces the old
Debian Python Click 8.1.8 package with upstream Click 8.5.1, the current release
verified against GitHub and PyPI. Exact source archive SHA256 is
`9bbfada76703fd1d784b83eea012e3e8c6a001a876543ef104fa56aaaeb072b4`.
The installed Python package and its license are inside the sealed prefix.
Colorama is a Windows-only optional dependency of this source distribution and
is not used by the Linux runtime. This corrects the initial candidate package
classification before SBY qualification; it is not a passing result.
