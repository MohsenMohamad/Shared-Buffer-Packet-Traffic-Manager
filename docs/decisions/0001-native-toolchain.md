# Native toolchain qualification

Historical decision: current tool/frontend restrictions and their dispositions
are covered by [decision 0006](0006-modern-toolchain.md). The original evidence
and behavioral choices below remain historical records.

P00 uses checksum-locked Debian trixie packages for Yosys 0.52-2, ABC, Z3
4.13.3 and OpenSTA 2.0.17. The packaged Yosys reports the exact specification
commit `fee39a3284c90249e1d9684cf6944ffbbcbb8f90`. SBY v0.71 and Verilator
5.054 are built/installed from locked archives; UVM 2020.3.1 is unmodified.
The source commits and SHA256s remain in [dependencies.json](../../tools/dependencies.json);
exact Debian package versions, URLs and SHA256s are in
[packages.lock.json](../../tools/packages.lock.json).

Extracting packages into a local sysroot avoids privileged installation and
mixing a distribution's system packages. The binaries require Linux x86-64,
glibc 2.38 or newer and a GCC 14 runtime. The qualified workspace is Debian
trixie with GCC 14.2.0; CI bootstraps GCC 14 on Ubuntu 24.04. A compatible
host compiler is a prerequisite, and its full version is recorded, rather
than claiming a hermetic OS image. Older libc images fail setup explicitly.
Package download hashes are fixed; availability of the Debian mirror is an
installation dependency. A verified download cache can be retained offline.

Verilator's optimized binaries are sufficient for these gates; its debugger
binaries are not built. Setup and execution are separate. Normal checks never
download dependencies. Each run builds in a new directory; a previous PASS
cannot qualify a changed source or option set.

The formal fixture checks enabled counter transitions and hold behavior using
`$past` monitor state. This is an unbounded k-induction toolchain proof, with
a reachable modulo wrap cover and an increment-by-two mutation. It does not
prove the UVM pipe's held-output SVA or any production module. The mapping
fixture has one XOR and one flop. Its Nangate45 typical, pre-layout timing
reports qualify max/min analysis only. Neither fixture establishes a
traffic-manager implementation gate.

The unmodified UVM library reports `NO_DPI_USED` and `NO_VISIT_CHECK` at
runtime. Those two warnings are accepted for the specified `UVM_NO_DPI`
configuration: DPI services and regex component-name checks are outside this
baseline. They remain visible in the logs. The fixture's deliberately
unsatisfiable randomization reports `UNSATCONSTR`; it is accepted only with
the explicit zero randomization result and `TM_CAP_UNSAT_PASS` marker.
No ignored constraint, coverage or assertion diagnostic is waived.
