"""Conservative Markdown draft generation."""
from typing import Any


def _inline(value: Any) -> str:
    """Render untrusted values as a single-line Markdown code span."""
    text = str(value).replace("\r", " ").replace("\n", " ").replace("`", "\\`")
    return f"`{text}`"


def render_report(host_id: str, events: list[dict[str, Any]], diffs: list[dict[str, Any]]) -> str:
    lines = [
        f"# Homelab record: {_inline(host_id)}",
        "",
        "> Status: generated draft. Validate commands and recovery steps before use.",
        "",
        "## Observed activity",
        "",
    ]
    if not events:
        lines.append("No events recorded for this host.")
    for event in reversed(events):
        lines.extend([
            f"### {_inline(event.get('timestamp', 'unknown time'))} — {_inline(event.get('summary', '(no summary)'))}",
            "",
            f"- Event type: {_inline(event.get('event_type', 'unknown'))}",
        ])
        if event.get("session_id"):
            lines.append(f"- Session: {_inline(event['session_id'])}")
        for ref in event.get("evidence_refs", []):
            lines.append(f"- Evidence: {_inline(ref)}")
        lines.append("")
    lines.extend(["## Latest configuration differences", ""])
    if not diffs:
        lines.append("No comparison data available.")
    for item in diffs:
        lines.append(
            f"- {_inline(item.get('path', '$'))} — **{_inline(item.get('change', 'unknown'))}**"
        )
    lines.extend([
        "",
        "## Recovery procedure",
        "",
        "Not yet generated. A state diff alone does not establish command order or prove reproducibility.",
        "",
    ])
    return "\n".join(lines)
