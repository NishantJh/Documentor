"""Deterministic recursive JSON diff helpers."""
from typing import Any


def diff_values(before: Any, after: Any, path: str = "$", out: list[dict[str, Any]] | None = None) -> list[dict[str, Any]]:
    """Return JSON-compatible add/remove/change records for two values."""
    if out is None:
        out = []
    if type(before) is not type(after):
        out.append({"path": path, "change": "changed", "before": before, "after": after})
    elif isinstance(before, dict):
        for key in sorted(before.keys() - after.keys()):
            out.append({"path": f"{path}.{key}", "change": "removed", "before": before[key]})
        for key in sorted(after.keys() - before.keys()):
            out.append({"path": f"{path}.{key}", "change": "added", "after": after[key]})
        for key in sorted(before.keys() & after.keys()):
            diff_values(before[key], after[key], f"{path}.{key}", out)
    elif isinstance(before, list):
        if before != after:
            out.append({"path": path, "change": "changed", "before": before, "after": after})
    elif before != after:
        out.append({"path": path, "change": "changed", "before": before, "after": after})
    return out
