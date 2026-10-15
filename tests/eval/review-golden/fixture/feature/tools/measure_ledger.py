"""Print the packed size of a 100,000-record ledger day."""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from app.ledger import pack_records  # noqa: E402

records = [(i % 65536, i) for i in range(100_000)]
print(len(pack_records(records)), "bytes")
