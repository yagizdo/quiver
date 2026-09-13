"""Customer tier display."""

TIERS = ("bronze", "silver", "gold", "platinum")


def tier_labels(counts):
    """One "tier: count" label per tier, in rank order.

    counts maps a tier name to how many customers currently hold it.
    """
    return [tier + ": " + str(counts.get(tier, 0)) for tier in TIERS]
