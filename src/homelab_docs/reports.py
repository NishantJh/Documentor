"""Conservative Markdown draft generation."""
from typing import Any


def render_report(host_id: str, events: list[dict[str, Any]], diffs: list[dict[str, Any]]) -> str:
    lines = [f"# Homelab record: {host_id}", "", "> Status: generated draft. Validate commands and recovery steps before use.", "", "## Observed activity", ""]
    if not events:
        lines.append("No events recorded for this host.")
    for event in reversed(events):
        lines.extend([f"### {event.get('timestamp', 'unknown time')} — {event.get('summary', '(no summary)')}", "", f"- Event type: {event.get('event_type', 'unknown')}"])
        if event.get("session_id"):
            lines.append(f"- Session: {event['session_id']}")
        for ref in event.get("evidence_refs", []):
            lines.append(f"- Evidence: {ref}")
        lines.append("")
    lines.extend(["## Latest configuration differences", ""])
    if not diffs:
        lines.append("No comparison data available.")
    for item in diffs:
        lines.append(f"- {item.get('path', '$')} — **{item.get('change', 'unknown')}**")
    lines.extend(["", "## Recovery procedure", "", "Not yet generated. A state diff alone does not establish command order or prove reproducibility.", ""])
    return "\n".join(lines)
