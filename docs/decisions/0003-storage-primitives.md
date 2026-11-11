# Pre-state storage and local proof boundary

The P01 storage APIs retain their names and signatures. A shared bitmap kernel
implements one allocation and one/two return lanes; wrappers own the cell and
descriptor record adaptation. Allocation must name the lowest pre-state free ID.
An invalid allocation is ignored and sets the same sticky error as an invalid
return. Return checks use pre-state ownership, with TX lane precedence for a
duplicate descriptor ID. Valid independent actions still proceed after errors.
One widened signed count expression and one next bitmap are committed per edge.

The FIFO uses a circular register array, occupancy, pointers and registered
space indication. A full FIFO inserts a push bubble on the first pop. `enable`
is the registered RUN/initialized query at integration and gates input readiness;
it neither discards buffered beats nor stops their consumption. Payload storage
uses plain `logic [BEAT_W-1:0]` vectors: the pinned Yosys frontend interprets an
unpacked array of packed struct typedefs as a packed vector rather than the
intended memory. The same vector-array RTL runs in simulation and formal, with
packed beat records at its ports. No translated formal DUT is used.

`formal-smoke` remains the P00 counter fixture. `formal-rtl` selects only real
storage APIs from the formal registry. Proof-only immediate assertions and
independent monitor state are included under `FORMAL` and excluded from normal
production/synthesis builds. E0 pool elaborations use an extra ID bit to exercise
out-of-range requests. FIFO proofs retain every bit at depths two and four.

Local pool ownership means an ID is either free or live according to this API.
It does not establish RX/QUEUED/TX/ABORT ownership composition or the U/R/A/H
reservation equations. These require their owning controllers and later
composition checks. The pool wrong-delta experiment edits a disposable source
copy; it adds no mutation switch to production RTL.
