"""In-memory stock tracking."""

from app.utils import normalize_sku


class Inventory:
    def __init__(self):
        self._items = {}

    def add(self, sku, qty):
        if qty < 0:
            raise ValueError("qty must be >= 0")
        key = normalize_sku(sku)
        self._items[key] = self._items.get(key, 0) + qty
        return self._items[key]

    def count(self, sku):
        return self._items.get(normalize_sku(sku), 0)

    def skus(self):
        return sorted(self._items)
