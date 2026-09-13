"""Paged SKU report rendering."""


def chunk_list(items, size):
    """Group items into lists of size items each."""
    out = []
    group = []
    for item in items:
        group.append(item)
        if len(group) == size:
            out.append(group)
            group = []
    if group:
        out.append(group)
    return out


def render_pages(skus, per_page):
    return ["\n".join(page) for page in chunk_list(skus, per_page)]
