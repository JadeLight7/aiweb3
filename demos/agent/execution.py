"""Execution trace models for the World Builder Agent.

Records every step the agent takes: task planning, tool calls,
validation rounds, and repair iterations.
"""

from __future__ import annotations

import json
import time
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from typing import Any


@dataclass
class StepRecord:
    """Record of a single tool execution step."""
    step_id: str
    tool: str
    description: str = ""
    status: str = "pending"  # pending | running | completed | failed
    input_summary: str = ""
    output_summary: str = ""
    duration_ms: int = 0
    timestamp: str = ""
    error: str | None = None

    def __post_init__(self):
        if not self.timestamp:
            self.timestamp = datetime.now(timezone.utc).isoformat()


@dataclass
class ValidationRound:
    """Record of one validation-evaluation-repair cycle."""
    round_number: int
    score: int = 0
    passed: bool = False
    dimensions: dict[str, str] = field(default_factory=dict)  # dimension -> problem_description
    repair_decision: str = ""  # GLM-5.1's reasoning for repair
    repair_strategy: str = ""  # "revise_spec" | "replan" | "accept"
    repaired: bool = False
    repair_duration_ms: int = 0


@dataclass
class ExecutionTrace:
    """Complete execution trace for one agent run."""
    request: str = ""
    planning_model: str = ""
    planning_reasoning: str = ""
    plan_steps: list[StepRecord] = field(default_factory=list)
    execution_steps: list[StepRecord] = field(default_factory=list)
    validation_rounds: list[ValidationRound] = field(default_factory=list)
    final_spec: dict[str, Any] | None = None
    total_duration_ms: int = 0
    # Web3 fields
    web3_contract_address: str | None = None
    web3_chain_id: int | None = None
    web3_mints: list[dict[str, Any]] = field(default_factory=list)
    final_status: str = "pending"  # pending | success | partial | failed
    started_at: str = ""
    completed_at: str = ""

    def __post_init__(self):
        if not self.started_at:
            self.started_at = datetime.now(timezone.utc).isoformat()

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    def to_json(self) -> str:
        return json.dumps(self.to_dict(), indent=2, ensure_ascii=False)


class Timer:
    """Simple wall-clock timer for measuring step durations."""
    def __init__(self):
        self._start = time.monotonic()

    def elapsed_ms(self) -> int:
        return int((time.monotonic() - self._start) * 1000)


def truncate(text: str, max_len: int = 200) -> str:
    """Truncate text for summary display."""
    if len(text) <= max_len:
        return text
    return text[:max_len] + "..."
