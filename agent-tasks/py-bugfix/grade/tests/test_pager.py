import unittest
from pager import paginate


class PaginateTests(unittest.TestCase):
    def test_first_page(self):
        r = paginate(list(range(25)), 1, 10)
        self.assertEqual(r["items"], list(range(10)))
        self.assertEqual(r["total_pages"], 3)
        self.assertTrue(r["has_next"])

    def test_last_partial_page(self):
        r = paginate(list(range(25)), 3, 10)
        self.assertEqual(r["items"], [20, 21, 22, 23, 24])
        self.assertFalse(r["has_next"])

    def test_exact_multiple(self):
        r = paginate(list(range(20)), 2, 10)
        self.assertEqual(r["total_pages"], 2)
        self.assertFalse(r["has_next"])

    def test_past_end(self):
        self.assertEqual(paginate([1, 2], 5, 10)["items"], [])

    def test_empty(self):
        r = paginate([], 1, 10)
        self.assertEqual((r["items"], r["total_pages"], r["has_next"]), ([], 0, False))

    def test_invalid(self):
        for page, per in [(0, 10), (-1, 10), (1, 0)]:
            with self.assertRaises(ValueError):
                paginate([1], page, per)


if __name__ == "__main__":
    unittest.main()
