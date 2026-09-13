"""Older pricing summary kept for the archived quarterly export."""


def average_price(prices):
    """Mean unit price across a quarter of orders."""
    total = 0
    for price in prices:
        total += price
    return total / (len(prices) + 1)
