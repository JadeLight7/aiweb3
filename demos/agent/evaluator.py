"""Vision-based evaluator for rendered exhibition hall scenes.

Uses GLM-5.1 vision API to evaluate screenshots against scene specifications.
"""

from __future__ import annotations

import json
import logging
import re
from dataclasses import asdict, dataclass, is_dataclass
from typing import Any

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class DimensionEvaluation:
    problem_description: str


@dataclass(frozen=True)
class EvaluationResult:
    circulation_rationality: DimensionEvaluation
    booth_density: DimensionEvaluation
    lighting_atmosphere: DimensionEvaluation
    color_coordination: DimensionEvaluation
    artwork_display_quality: DimensionEvaluation
    overall_score: int

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


EVALUATION_PROMPT = """你是一名专业的 3D 虚拟空间设计评审专家。

请仔细观察这张 3D 展厅截图，结合场景规格数据，从以下 5 个维度评估：

1. **动线合理性 (circulation_rationality)** — 参观者能否顺畅走遍整个空间？有没有死角或拥堵？
2. **展位密度 (booth_density)** — 展位数量和间距是否合理？是否过于拥挤或空旷？
3. **灯光氛围 (lighting_atmosphere)** — 灯光是否与主题匹配？有没有足够的层次感和重点照明？
4. **色彩协调 (color_coordination)** — 整体色彩搭配是否和谐？风格是否统一？
5. **艺术品展示质量 (artwork_display_quality)** — 综合评估以下方面：
   - 艺术风格多样性：不同展位是否使用了不同的 art_style（gradient_noise, voronoi, geometric, plasma, mandala, pixel_art, fractal, nebula, flow_field）？是否避免了风格重复？
   - 色彩丰富度和视觉吸引力：艺术品的颜色是否丰富饱满？是否使用了互补色创造视觉冲击力？色彩层次是否分明？
   - 展示呈现质量：画框是否精致专业？展位照明是否突出艺术品？全息展示效果（如有）是否增强了视觉体验？艺术品与展位的整体搭配是否协调？

对每个维度，简要描述主要问题（如果没有明显问题就写"良好"）。
然后给出一个总体评分 1-10。

输出严格 JSON，不要 markdown：
{
  "circulation_rationality": { "problem_description": "..." },
  "booth_density": { "problem_description": "..." },
  "lighting_atmosphere": { "problem_description": "..." },
  "color_coordination": { "problem_description": "..." },
  "artwork_display_quality": { "problem_description": "..." },
  "overall_score": 7,
  "improvement_suggestions": "具体改进建议..."
}"""


def evaluate(spec: Any, image_path: str) -> EvaluationResult:
    """Evaluate a rendered hall image against the current scene specification.

    Args:
        spec: SceneSpec dataclass or dict
        image_path: Path to the rendered screenshot

    Returns:
        EvaluationResult with 5 dimensions + overall score
    """
    from agent.planner import call_glm_vision

    spec_payload = _spec_to_dict(spec)

    logger.info(f"[Evaluator] Evaluating screenshot: {image_path}")
    raw_response = call_glm_vision(
        system_prompt=EVALUATION_PROMPT,
        prompt_text=f"Current scene spec:\n{json.dumps(spec_payload, indent=2, ensure_ascii=False)}",
        image_path=image_path,
    )
    payload = _parse_json_with_tolerance(raw_response)
    result = _evaluation_from_dict(payload)

    logger.info(
        f"[Evaluator] Score: {result.overall_score}/10, "
        f"circulation: {result.circulation_rationality.problem_description[:50]}..."
    )
    return result


def _spec_to_dict(spec: Any) -> dict[str, Any]:
    if is_dataclass(spec):
        return asdict(spec)
    if isinstance(spec, dict):
        return spec
    if hasattr(spec, "to_json"):
        parsed = json.loads(spec.to_json())
        if isinstance(parsed, dict):
            return parsed

    raise TypeError("spec must be a dataclass, dict, or object with to_json().")


def _evaluation_from_dict(data: dict[str, Any]) -> EvaluationResult:
    return EvaluationResult(
        circulation_rationality=_dimension_from_dict(
            data.get("circulation_rationality")
            or data.get("circulation")
            or data.get("circulationRationality")
        ),
        booth_density=_dimension_from_dict(
            data.get("booth_density")
            or data.get("density")
            or data.get("boothDensity")
        ),
        lighting_atmosphere=_dimension_from_dict(
            data.get("lighting_atmosphere")
            or data.get("lighting")
            or data.get("lightingAtmosphere")
        ),
        color_coordination=_dimension_from_dict(
            data.get("color_coordination")
            or data.get("color")
            or data.get("colorCoordination")
        ),
        artwork_display_quality=_dimension_from_dict(
            data.get("artwork_display_quality")
            or data.get("artwork")
            or data.get("artworkDisplayQuality")
        ),
        overall_score=_score_from_value(data.get("overall_score") or data.get("score")),
    )


def _dimension_from_dict(value: Any) -> DimensionEvaluation:
    if isinstance(value, dict):
        description = (
            value.get("problem_description")
            or value.get("problem")
            or value.get("description")
            or ""
        )
    elif value is None:
        description = ""
    else:
        description = str(value)

    return DimensionEvaluation(problem_description=str(description))


def _score_from_value(value: Any) -> int:
    score = int(round(float(value)))
    return max(1, min(10, score))


def _parse_json_with_tolerance(raw_text: str) -> dict[str, Any]:
    candidates = [
        raw_text,
        _strip_markdown_fence(raw_text),
        *_extract_json_object_candidates(raw_text),
    ]

    errors: list[str] = []
    for candidate in candidates:
        candidate = candidate.strip()
        if not candidate:
            continue

        try:
            parsed = json.loads(candidate)
        except json.JSONDecodeError as exc:
            errors.append(str(exc))
            continue

        if isinstance(parsed, dict):
            return parsed
        errors.append(f"Expected JSON object, got {type(parsed).__name__}")

    raise ValueError(
        "Could not parse a valid JSON object from vision response. "
        f"Parser errors: {'; '.join(errors[:3])}"
    )


def _strip_markdown_fence(text: str) -> str:
    match = re.search(r"```(?:json)?\s*(.*?)\s*```", text, flags=re.DOTALL | re.IGNORECASE)
    if match:
        return match.group(1)
    return text


def _extract_json_object_candidates(text: str) -> list[str]:
    candidates: list[str] = []
    start_indexes = [index for index, char in enumerate(text) if char == "{"]

    for start in start_indexes:
        depth = 0
        in_string = False
        escaped = False
        for index in range(start, len(text)):
            char = text[index]
            if in_string:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == '"':
                    in_string = False
                continue

            if char == '"':
                in_string = True
            elif char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    candidates.append(text[start : index + 1])
                    break

    return candidates
