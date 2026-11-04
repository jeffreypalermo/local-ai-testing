import time


class TTLCache:
    """A dict-like cache with a maximum size and a per-entry time-to-live.

    TTLCache(maxsize, ttl, clock=time.monotonic)
      set(key, value)    store or replace; resets that entry's expiry and makes it most recently used
      get(key, default=None)
                         return the value if present and not expired, else default;
                         a successful get makes the entry most recently used
      __len__()          number of entries that have not expired
      __contains__(key)  True if present and not expired
    An entry set at time t expires at t + ttl (it is expired when clock() >= t + ttl).
    When a set would exceed maxsize, expired entries are dropped first; if still full,
    the least recently used entry is evicted.
    All operations must be O(1) on average (amortized); do not scan all entries on every call.
    Raises ValueError if maxsize < 1 or ttl <= 0.
    """

    def __init__(self, maxsize, ttl, clock=time.monotonic):
        raise NotImplementedError
