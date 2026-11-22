"""Frozen reachability for the required pool-level count/source crosses."""

from itertools import product

SOURCES = ("none", "tx", "cleanup", "mixed")
BOUNDARIES = ("zero", "one", "low", "interior", "full")


def limits(capacity):
    return ((0, 0), (1, 1), (2, 4), (5, capacity - 1), (capacity, capacity))


def boundary(count, capacity):
    return next(name for name, (low, high) in zip(BOUNDARIES, limits(capacity))
                if low <= count <= high)


def source(lanes, ports):
    if not lanes:
        return "none"
    if ports not in lanes:
        return "tx"
    return "mixed" if len(lanes) > 1 else "cleanup"


def exclusions(kind, returns, allocations, old_free, origin, profile):
    """Explain combinations impossible at every count represented by a bin."""
    capacity = profile.descriptors if kind == "descriptor" else profile.cells
    low, high = limits(capacity)[BOUNDARIES.index(old_free)]
    if (returns == 0) != (origin == "none"):
        return "only an empty mask has no source"
    if origin == "tx" and returns > profile.ports:
        return "one return per TX lane"
    if origin == "cleanup" and returns != 1:
        return "one dedicated cleanup lane"
    if origin == "mixed" and returns < 2:
        return "mixed source needs two distinct return lanes"
    if kind == "descriptor" and origin in ("cleanup", "mixed") and allocations == profile.ports:
        return "the ingress completing cleanup is unavailable for a grant"
    needed = allocations
    if kind == "cell" and origin in ("cleanup", "mixed"):
        # A malformed frame never writes its good final cell. Its unused
        # reservation is distinct from the live RX writer's credit.
        needed += 1
        if needed > high:
            return "abort cleanup and the RX writer need distinct reserved free cells"
    if allocations > high:
        return "allocation cannot exceed pre-edge free ID count"
    if max(low, needed) + returns > capacity:
        return "returns must have distinct pre-edge owners"
    return None


def matrix(kind, profile):
    max_allocations = profile.ports if kind == "descriptor" else 1
    return {
        coordinates: exclusions(kind, *coordinates, profile)
        for coordinates in product(range(profile.ports + 2), range(max_allocations + 1),
                                   BOUNDARIES, SOURCES)
    }


REQUIRED_WITNESSES = (
    "descriptor-empty-return", "descriptor-one-prefix", "descriptor-two-prefix",
    "descriptor-next-edge", "credit-next-edge", "cell-one-exchange",
    "cell-next-edge", "reserved-write-zero-U", "full-return", "highest-return",
    "sparse-cleanup", "full-grant-same-q", "full-grant-different-q",
    "grant-and-abort", "mark-with-staged-write", "nonfinal-abort-reclaim",
    "zero-cell-cleanup", "bound-without-final", "active-abort-reset",
    "epoch-reused-cell-desc-tag", "repeated-tag-shared-queue",
    "zero-and-highest-IDs", "absent-fields", "exact-drain",
)
REQUIRED_DETECTORS = {
    "desc-return-bypass": "DESC_PRE_FREE",
    "cell-return-bypass": "CELL_PRE_FREE",
    "descriptor-prefix-repeat": "DESC_PRE_FREE",
    "credit-return-bypass": "CREDIT_PREFIX",
    "physical-exhaustion": "PHYSICAL_EXHAUSTION",
    "repeat-return": "DUPLICATE_CELL_RETURN",
    "omit-high-lane": "TX_CELL_EVENT",
    "early-abort-credit": "EARLY_CLEANUP_CREDIT",
    "stale-owner": "STALE_OWNER",
    "omit-final-return": "TX_DESC_EVENT",
    "omit-final-cleanup": "DRAIN_OWNERSHIP",
}
RANDOM_REQUIREMENTS = (
    "descriptor-zero", "descriptor-one", "descriptor-full",
    "cell-zero", "cell-one", "cell-full", "grant-and-return",
    "write-and-return", "mixed-source", "same-q", "different-q",
    "reset-with-ownership", "next-edge-reuse",
)
SEEDS = (17, 31, 53, 67, 89, 113, 149, 197)
ACTIVITY_EDGES = 2048
