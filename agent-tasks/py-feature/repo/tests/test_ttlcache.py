import time
import unittest
from ttlcache import TTLCache


class Clock:
    def __init__(self):
        self.t = 0.0

    def __call__(self):
        return self.t


class TTLCacheTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()

    def test_basic_and_default(self):
        c = TTLCache(2, 10, self.clock)
        c.set("a", 1)
        self.assertEqual(c.get("a"), 1)
        self.assertEqual(c.get("zz", "dflt"), "dflt")
        self.assertIn("a", c)

    def test_expiry_boundary(self):
        c = TTLCache(2, 10, self.clock)
        c.set("a", 1)
        self.clock.t = 9.99
        self.assertEqual(c.get("a"), 1)
        self.clock.t = 10.0
        self.assertIsNone(c.get("a"))
        self.assertEqual(len(c), 0)

    def test_set_resets_expiry(self):
        c = TTLCache(2, 10, self.clock)
        c.set("a", 1)
        self.clock.t = 8
        c.set("a", 2)
        self.clock.t = 15
        self.assertEqual(c.get("a"), 2)

    def test_lru_eviction_respects_get(self):
        c = TTLCache(2, 100, self.clock)
        c.set("a", 1)
        c.set("b", 2)
        c.get("a")
        c.set("c", 3)
        self.assertNotIn("b", c)
        self.assertIn("a", c)
        self.assertIn("c", c)

    def test_expired_dropped_before_lru(self):
        c = TTLCache(2, 10, self.clock)
        c.set("old", 1)
        self.clock.t = 5
        c.set("new", 2)
        self.clock.t = 11
        c.set("x", 3)
        self.assertIn("new", c)
        self.assertIn("x", c)

    def test_invalid(self):
        for args in [(0, 1), (1, 0), (1, -1)]:
            with self.assertRaises(ValueError):
                TTLCache(*args)

    def test_performance(self):
        c = TTLCache(50000, 1e9, self.clock)
        start = time.perf_counter()
        for i in range(300000):
            c.set(i % 80000, i)
            c.get(i % 50000)
        self.assertLess(time.perf_counter() - start, 10)


if __name__ == "__main__":
    unittest.main()
