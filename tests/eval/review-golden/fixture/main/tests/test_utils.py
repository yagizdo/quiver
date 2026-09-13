import unittest

from app.utils import chunked, normalize_sku


class ChunkedTest(unittest.TestCase):
    def test_splits_evenly(self):
        self.assertEqual(chunked([1, 2, 3, 4], 2), [[1, 2], [3, 4]])

    def test_keeps_remainder(self):
        self.assertEqual(chunked([1, 2, 3], 2), [[1, 2], [3]])

    def test_rejects_zero_size(self):
        with self.assertRaises(ValueError):
            chunked([1], 0)


class NormalizeSkuTest(unittest.TestCase):
    def test_uppercases_and_dashes(self):
        self.assertEqual(normalize_sku(" red widget "), "RED-WIDGET")
