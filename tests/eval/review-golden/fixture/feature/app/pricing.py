"""Order pricing for the checkout path."""

BULK_THRESHOLD = 10


def line_total(unit_price, qty):
    if qty < 0:
        raise ValueError("qty must be >= 0")
    return unit_price * qty


def bulk_discount(unit_price, qty):
    """Orders of BULK_THRESHOLD units or more take 10 percent off."""
    if qty > BULK_THRESHOLD:
        return line_total(unit_price, qty) * 0.9
    return line_total(unit_price, qty)
