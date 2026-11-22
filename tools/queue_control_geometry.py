"""Published geometry inputs for the queue-control STA fixtures."""

from dataclasses import dataclass


@dataclass(frozen=True)
class Profile:
    ports: int
    cells: int
    descriptors: int
    maximum: int


PROFILES = {"primary": Profile(4, 1024, 256, 1536), "small": Profile(2, 16, 8, 192)}
