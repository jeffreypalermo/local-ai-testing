def paginate(items, page, per_page=10):
    """Return one page of `items`.

    Pages are 1-based. Returns a dict with:
      items        the items on that page (empty list if page is past the end)
      page         the requested page
      total_pages  number of pages (0 for an empty list)
      has_next     whether a later page exists
    Raises ValueError if page < 1 or per_page < 1.
    """
    if page < 0 or per_page < 1:
        raise ValueError("page and per_page must be >= 1")
    total_pages = len(items) // per_page
    start = page * per_page
    return {
        "items": list(items[start:start + per_page]),
        "page": page,
        "total_pages": total_pages,
        "has_next": page <= total_pages,
    }
