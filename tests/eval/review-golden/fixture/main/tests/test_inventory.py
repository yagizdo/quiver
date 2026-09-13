import unittest

from app.inventory import Inventory


class InventoryTest(unittest.TestCase):
    def test_add_accumulates(self):
        inv = Inventory()
        inv.add("abc", 2)
        self.assertEqual(inv.add("ABC", 3), 5)

    def test_count_normalizes(self):
        inv = Inventory()
        inv.add("red widget", 1)
        self.assertEqual(inv.count("RED-WIDGET"), 1)

    def test_unknown_sku_is_zero(self):
        self.assertEqual(Inventory().count("nope"), 0)
