"""LLM-backed scene spec reviser.

Uses GLM-5.1 (Anthropic-compatible) to revise scene specifications based on evaluation feedback.

Returns plain dicts — compatible with the orchestrator's dict-based pipeline.
"""

from __future__ import annotations

import json
import logging
from dataclasses import asdict, is_dataclass
from typing import Any

from agent.planner import _call_glm, _parse_json_with_tolerance

logger = logging.getLogger(__name__)


SYSTEM_PROMPT = """You are a professional spatial design reviser for 3D virtual exhibition halls.

Revise the current scene specification according to the review feedback.
Modify practical design details such as booth positions, booth orientation,
lighting positions, lighting intensity, wall colors, the global color palette,
and NFT artwork parameters.
Keep the same JSON schema and preserve useful existing identifiers when possible.

Output only valid JSON. Do not use markdown, comments, or prose outside JSON.
The JSON must strictly match this structure:
{
  "theme_name": "Theme name",
  "global_color_palette": ["#RRGGBB"],
  "rooms": [
    {
      "id": "room_id",
      "dimensions": [width, height, depth],
      "wall_color": "#RRGGBB"
    }
  ],
  "booths": [
    {
      "id": "booth_id",
      "position": [x, y, z],
      "orientation": 0.0,
      "nft": {
        "name": "Artwork name",
        "collection": "Collection name",
        "art_style": "gradient_noise",
        "art_seed": 42,
        "art_colors": ["#RRGGBB", "#RRGGBB", "#RRGGBB"]
      }
    }
  ],
  "lights": [
    {
      "position": [x, y, z],
      "color": "#RRGGBB",
      "intensity": 500.0
    }
  ]
}

Use numeric values for all dimensions, positions, orientations, and intensities.
Use hex strings for all colors."""


USER_PROMPT_TEMPLATE = """Current scene specification JSON:
{spec_json}

Evaluation feedback JSON:
{evaluation_json}

Return the revised scene specification as valid JSON only."""


def revise(spec: dict[str, Any], evaluation: Any) -> dict[str, Any]:
    """Revise a scene spec based on structured evaluation feedback.

    Args:
        spec: Current scene spec dict
        evaluation: EvaluationResult from the evaluator (dataclass or dict)

    Returns:
        Revised scene spec dict
    """
    spec_payload = _to_dict(spec)
    evaluation_payload = _to_dict(evaluation)
    user_prompt = USER_PROMPT_TEMPLATE.format(
        spec_json=json.dumps(spec_payload, indent=2, ensure_ascii=False),
        evaluation_json=json.dumps(evaluation_payload, indent=2, ensure_ascii=False),
    )

    logger.info("[Reviser] Sending revision request to GLM-5.1...")
    raw_response = _call_glm(
        system_prompt=SYSTEM_PROMPT,
        user_prompt=user_prompt,
    )
    payload = _parse_json_with_tolerance(raw_response)

    # Unwrap if wrapped in a top-level key
    spec_payload = payload.get("scene_spec") or payload.get("spec") or payload

    theme = spec_payload.get("theme_name", "?")
    booths = len(spec_payload.get("booths", []))
    lights = len(spec_payload.get("lights", []))
    logger.info(f"[Reviser] Revised: theme={theme}, booths={booths}, lights={lights}")
    return spec_payload


def _to_dict(value: Any) -> dict[str, Any]:
    if is_dataclass(value):
        return asdict(value)
    if isinstance(value, dict):
        return value
    if hasattr(value, "to_dict"):
        converted = value.to_dict()
        if isinstance(converted, dict):
            return converted
    if hasattr(value, "to_json"):
        parsed = json.loads(value.to_json())
        if isinstance(parsed, dict):
            return parsed

    raise TypeError("value must be a dataclass, dict, or object with to_dict()/to_json().")
