"""Shared helpers used across the store package."""


def chunked(seq, size):
    """Split seq into consecutive lists of at most size items."""
    if size < 1:
        raise ValueError("size must be >= 1")
    return [list(seq[i:i + size]) for i in range(0, len(seq), size)]


def normalize_sku(sku):
    """Canonical form of a stock keeping unit."""
    return sku.strip().upper().replace(" ", "-")
