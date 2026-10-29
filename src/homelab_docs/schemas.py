"""API request models."""
from typing import Any
from pydantic import BaseModel, Field


class EventIn(BaseModel):
    host_id: str = Field(min_length=1, max_length=200)
    event_type: str = Field(min_length=1, max_length=100)
    timestamp: str | None = None
    session_id: str | None = None
    summary: str = Field(min_length=1, max_length=4000)
    payload: dict[str, Any] = Field(default_factory=dict)
    evidence_refs: list[str] = Field(default_factory=list)


class SnapshotIn(BaseModel):
    host_id: str = Field(min_length=1, max_length=200)
    captured_at: str | None = None
    source: str = Field(default="manual", max_length=200)
    state: dict[str, Any]
