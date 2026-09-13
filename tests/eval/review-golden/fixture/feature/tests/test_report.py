import unittest

from app.report import render_pages
from app.tiers import tier_labels


class ReportTest(unittest.TestCase):
    def test_pages_are_joined(self):
        self.assertEqual(render_pages(["a", "b", "c"], 2), ["a\nb", "c"])

    def test_tier_labels_cover_every_tier(self):
        self.assertEqual(
            tier_labels({"gold": 3}),
            ["bronze: 0", "silver: 0", "gold: 3", "platinum: 0"],
        )
