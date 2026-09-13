import unittest

from app.pricing import bulk_discount, line_total


class PricingTest(unittest.TestCase):
    def test_line_total(self):
        self.assertEqual(line_total(250, 4), 1000)

    def test_small_order_pays_full(self):
        self.assertEqual(bulk_discount(100, 3), 300)

    def test_large_order_is_discounted(self):
        self.assertEqual(bulk_discount(100, 25), 2250)
