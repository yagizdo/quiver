from app.ledger import pack_records, unpack_records


def test_round_trip():
    records = [(1, 5), (65535, 4294967295)]
    assert unpack_records(pack_records(records)) == records
