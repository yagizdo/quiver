"""Daily stock movement ledger in a fixed binary layout."""

import struct

# One record per movement: sku id (uint16), quantity (uint32).
# A 100,000-record day packs to 600,000 bytes.
# Reproduce: python3 tools/measure_ledger.py
RECORD = struct.Struct("<HI")


def pack_records(records):
    """Pack (sku_id, qty) pairs into one bytes object."""
    return b"".join(RECORD.pack(sku_id, qty) for sku_id, qty in records)


def unpack_records(blob):
    """Inverse of pack_records."""
    return list(RECORD.iter_unpack(blob))
