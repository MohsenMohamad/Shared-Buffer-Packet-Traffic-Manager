"""Pack replay stimulus using ABI v1."""


def packed(values, widths):
    result = 0
    for value, width in zip(values, widths, strict=True):
        if not 0 <= value < (1 << width):
            raise ValueError(f"{value} does not fit in {width} bits")
        result = (result << width) | value
    return result


class Layout:
    def __init__(self, profile):
        self.ports = profile.ports
        r = (profile.ports - 1).bit_length()
        q = (profile.queues - 1).bit_length()
        d = (profile.descriptors - 1).bit_length()
        self.c = (profile.cells - 1).bit_length()
        self.k = profile.cells.bit_length()
        self.frame = (64, r, 64)
        self.owner = (*self.frame, q, d, 16)
        self.admission = (1, sum(self.frame), 50, 2, 3, 1, q, self.k, d)
        owner_width = sum(self.owner)
        read = 1 + owner_width + r + self.k + self.c
        self.members = {
            "descriptor": ((1, owner_width), self.ports + 1),
            "cell": ((1, owner_width, self.c), self.ports + 1),
            "cleanup": ((1, owner_width, 1, self.k), 1),
            "abort": ((1, owner_width, self.k), self.ports),
            "read_response": ((read, 1), 1),
            "read_issue": ((read, 1, self.c), 1),
            "service": ((1, owner_width, self.c, 1, 1), self.ports),
            "dispatch": ((1, owner_width, 16), self.ports),
            "publication": ((1, owner_width, self.c, self.k, 16, 2, 1), 1),
            "write": ((1, owner_width, self.k, self.c, 1), 1),
            "admission": (self.admission, self.ports),
            "ingress_service": ((1, sum(self.frame), 1, 1, 73), self.ports),
            "epoch": ((64,), 1),
            "present": ((1,), 1),
        }
        width = sum(sum(fields) * count for fields, count in self.members.values())
        if width != (6360 if self.ports == 4 else 3589):
            raise ValueError(f"Unexpected ABI width {width}")

    def pack_owner(self, owner):
        return packed((*owner.frame, owner.qid, owner.descriptor, owner.tag), self.owner)

    def encode(self, batch):
        data = {name: {} for name in self.members}
        po = self.pack_owner
        for lane, owner in batch.desc_returns.items():
            data["descriptor"][lane] = (1, po(owner))
        for lane, (owner, address) in batch.cell_returns.items():
            data["cell"][lane] = (1, po(owner), address)
        if c := batch.cleanup:
            data["cleanup"][0] = (1, po(c.owner), c.done, c.released)
        for lane, (owner, amount) in batch.aborts.items():
            data["abort"][lane] = (1, po(owner), amount)
        for lane, service in batch.services.items():
            data["service"][lane] = (1, po(service.owner), service.address,
                                     service.cell_last, service.frame_last)
        for lane, (owner, length) in batch.dispatches.items():
            data["dispatch"][lane] = (1, po(owner), length)
        if p := batch.publication:
            data["publication"][0] = (1, po(p.owner), p.head, p.cells, p.length, 0, 0)
        if w := batch.write:
            data["write"][0] = (1, po(w.owner), w.index, w.address, w.final)
        for lane, grant in enumerate(batch.grants):
            owner = grant.owner
            metadata = packed((grant.length, owner.qid // 4, owner.qid % 4, owner.tag, 0),
                              (16, 8, 8, 16, 2))
            data["admission"][lane] = (1, packed(owner.frame, self.frame), metadata,
                                       0, 0, 1, owner.qid, grant.cells, owner.descriptor)
        data["epoch"][0] = (batch.epoch,)
        data["present"][0] = (batch.present,)

        result = offset = 0
        for name, (fields, lanes) in self.members.items():
            for lane in range(lanes):
                if lane in data[name]:
                    result |= packed(data[name][lane], fields) << offset
                offset += sum(fields)
        return result

    def row(self, reset_n, initialized, batch, counts, origin=0):
        return " ".join(map(str, (int(reset_n), int(initialized), origin,
                                  f"{self.encode(batch):x}", counts.physical_free,
                                  counts.unreserved, counts.reserved_free, counts.assigned,
                                  counts.descriptor_free, *counts.queue_credit)))
