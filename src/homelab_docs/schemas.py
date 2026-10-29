"""Bounded API request models; reject oversized or deeply nested evidence."""
import json
from typing import Annotated, Any

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, field_validator


MAX_JSON_DEPTH = 24
MAX_JSON_NODES = 30_000


def _check_json_size(value: Any, *, max_bytes: int, max_depth: int, max_nodes: int) -> Any:
    encoded = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    if len(encoded) > max_bytes:
        raise ValueError(f"JSON content exceeds the {max_bytes}-byte limit")

    stack: list[tuple[Any, int]] = [(value, 1)]
    nodes = 0
    while stack:
        item, depth = stack.pop()
        nodes += 1
        if nodes > max_nodes:
            raise ValueError(f"JSON content exceeds the {max_nodes}-node limit")
        if depth > max_depth:
            raise ValueError(f"JSON content exceeds the {max_depth}-level nesting limit")
        if isinstance(item, dict):
            stack.extend((child, depth + 1) for child in item.values())
        elif isinstance(item, list):
            stack.extend((child, depth + 1) for child in item)
    return value


class EventIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    host_id: str = Field(min_length=1, max_length=200)
    client_event_id: str | None = Field(default=None, min_length=1, max_length=100)
    event_type: str = Field(min_length=1, max_length=100)
    timestamp: AwareDatetime | None = None
    session_id: str | None = Field(default=None, max_length=200)
    summary: str = Field(min_length=1, max_length=4000)
    payload: dict[str, Any] = Field(default_factory=dict)
    evidence_refs: list[Annotated[str, Field(min_length=1, max_length=2000)]] = Field(
        default_factory=list, max_length=100
    )

    @field_validator("payload")
    @classmethod
    def payload_is_bounded_json(cls, value: dict[str, Any]) -> dict[str, Any]:
        return _check_json_size(value, max_bytes=256 * 1024, max_depth=16, max_nodes=10_000)


class SnapshotIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    host_id: str = Field(min_length=1, max_length=200)
    captured_at: AwareDatetime | None = None
    source: str = Field(default="manual", min_length=1, max_length=200)
    state: dict[str, Any]

    @field_validator("state")
    @classmethod
    def state_is_bounded_json(cls, value: dict[str, Any]) -> dict[str, Any]:
        return _check_json_size(
            value, max_bytes=1024 * 1024, max_depth=MAX_JSON_DEPTH, max_nodes=MAX_JSON_NODES
        )
