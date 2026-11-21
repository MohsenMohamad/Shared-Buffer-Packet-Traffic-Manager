# Multi-egress observation and CSR ABI

The multi-egress control and verification consumers need a stable way to
identify physical events and read coherent statistics. Opaque tags may
repeat, an abort can reclaim independently of all egresses, and a split
counter read can straddle a live increment.

- Observe physical service and retirement in fixed port lanes. Keep a
  dedicated cleanup lane and use a dense vector only for rotating
  admission order. A uniform compact event list would require consumers
  to reconstruct the physical lanes and arbitration order of each edge.
- Identify a frame by reset epoch, physical ingress and sequence at first
  capture. Keep descriptor IDs and tags as separate fields. Neither
  descriptor reuse nor a repeated opaque tag changes the correlation
  identity. Echo identity and address alongside each fixed-latency memory
  response. The reset coordinator supplies the epoch to allow stale-response
  filtering without a reset-persistent counter inside the datapath.
- Read 64-bit counters from an explicitly triggered snapshot and publish
  separate live occupancy words. Implicit latching on one half would
  impose read ordering and could create hidden state across bus clients.
  A shared snapshot generation allows either word order. Software must
  avoid retriggering between the halves it wants to compare.
- Use fixed region and coordinate strides across profiles. Class 4 is a
  separate ingress statistics bucket and has no queue address. The small
  profile leaves primary-only coordinates unmapped, while software can
  use the same stride math for either profile.

The [public interface](../spec/multi-egress-interfaces.md) specifies the
packed encodings, access precedence, reset defaults and snapshot lifecycle.
