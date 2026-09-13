"""Order payload checksum."""

MASK = 0xFFFF


def rotate_checksum(payload):
    """16-bit rotate-left-then-add checksum over a byte string."""
    acc = 0
    for byte in payload:
        acc = ((acc << 1) | (acc >> 15)) & MASK
        acc = (acc + byte) & MASK
    return acc
