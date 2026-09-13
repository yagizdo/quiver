import unittest

from app.checksum import rotate_checksum


class ChecksumTest(unittest.TestCase):
    def test_empty_payload(self):
        self.assertEqual(rotate_checksum(b""), 0)

    def test_known_value(self):
        self.assertEqual(rotate_checksum(b"AB"), 196)

    def test_order_matters(self):
        self.assertNotEqual(rotate_checksum(b"AB"), rotate_checksum(b"BA"))
