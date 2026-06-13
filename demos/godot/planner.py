"""Core planner for the world-building agent.

Usage:
    python planner.py "赛博朋克风格的 NFT 数字艺术画廊, 要有未来感和沉浸感"
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any

from openai import OpenAI


MODEL = os.environ.get("OPENAI_MODEL", "gpt-4o-mini")
MAX_GENERATION_ATTEMPTS = 3
DEFAULT_ROOM_SIZE = [8.0, 4.0, 10.0]
BOOTH_HALF_SIZE = 0.75


PLANNING_SYSTEM_PROMPT = """你是一名资深虚拟空间设计师，专门为 Web3 虚拟地产、NFT 展馆和 DAO 空间做空间规划。

你需要根据用户的自然语言需求，输出一份清晰、可执行的结构化文字设计方案。
不要输出 JSON。用中文输出，内容必须包含：

1. 整体风格调性
2. 色彩方案，包含 4-6 个 HEX 色值
3. 空间分区与动线
4. 灯光氛围
5. 展位布局思路

设计必须考虑 Godot 3D 场景可生成性：房间尺寸适中，展位不要拥挤，灯光要均匀。"""


GENERATION_SYSTEM_PROMPT = """你是一名资深虚拟空间设计师兼程序化场景生成工程师。

你需要基于用户需求和设计方案，生成严格合法 JSON。不要输出 markdown，不要输出解释文字。

JSON 必须严格符合这个结构：
{
  "theme_name": "Theme Name",
  "global_color_palette": ["#RRGGBB", "#RRGGBB"],
  "rooms": [
    {
      "id": "main_hall",
      "dimensions": [8.0, 4.0, 10.0],
      "wall_color": "#RRGGBB"
    }
  ],
  "booths": [
    {
      "id": "booth_id",
      "position": [0.0, 0.0, 0.0],
      "orientation": 0.0,
      "nft": {
        "name": "艺术品名称",
        "collection": "收藏集",
        "art_style": "nebula",
        "art_seed": 42,
        "art_colors": ["#RRGGBB", "#RRGGBB", "#RRGGBB", "#RRGGBB"],
        "token_id": "0042"
      }
    }
  ],
  "lights": [
    {
      "position": [0.0, 3.2, 0.0],
      "color": "#RRGGBB",
      "intensity": 500.0
    }
  ]
}

硬性约束：
- 只生成一个房间，id 使用 "main_hall"。
- 房间 dimensions 使用 [width, height, depth]，建议宽 8-14，高 4-6，深 10-18。
- Godot 房间坐标以房间中心为原点，地面 y=0。
- booth position 的 x 必须在 [-width/2 + 0.75, width/2 - 0.75]。
- booth position 的 y 必须为 0.0。
- booth position 的 z 必须在 [-depth/2 + 0.75, depth/2 - 0.75]。
- 展位数量建议 3-6 个，不能挡住中心动线。
- lights 要分布在房间上方，y 接近 height - 0.6，位置要均匀。
- colors 必须从设计方案色板中选择或保持高度一致。
- intensity 使用 250.0 到 750.0 之间的数值。
- 每个展位必须包含 nft 字段，art_style 可选: gradient_noise, voronoi, geometric, plasma, mandala, pixel_art, fractal, nebula, flow_field。
- art_colors 使用 3-4 个互补色。
- token_id 可选字符串。"""


def main() -> None:
    args = parse_args()
    client = create_openai_client()

    print("\n[1/2] 正在规划空间设计方案...\n")
    design_plan = plan_space(client, args.user_request)
    print_design_plan(design_plan)

    print("\n[2/2] 正在生成 scene_spec.json...\n")
    scene_spec = generate_scene_spec(client, args.user_request, design_plan)
    output_path = resolve_output_path(args.output)
    write_scene_spec(scene_spec, output_path)

    print(f"已写入: {output_path}")
    print("Godot 正在监听该 JSON 时，场景会自动刷新。")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="World-building planner: plan -> scene_spec.json")
    parser.add_argument("user_request", help="自然语言空间需求")
    parser.add_argument(
        "--output",
        default=None,
        help="scene_spec.json 输出路径。默认写入 Godot 实际读取的 godot/shared/scene_spec.json。",
    )
    return parser.parse_args()


def create_openai_client() -> OpenAI:
    if not os.environ.get("OPENAI_API_KEY"):
        raise RuntimeError("请先设置环境变量 OPENAI_API_KEY。")
    return OpenAI()


def plan_space(client: OpenAI, user_request: str) -> str:
    response = client.chat.completions.create(
        model=MODEL,
        messages=[
            {"role": "system", "content": PLANNING_SYSTEM_PROMPT},
            {"role": "user", "content": user_request},
        ],
        temperature=0.8,
    )
    content = response.choices[0].message.content
    if not content:
        raise RuntimeError("规划阶段没有返回内容。")
    return content.strip()


def generate_scene_spec(client: OpenAI, user_request: str, design_plan: str) -> dict[str, Any]:
    feedback = ""
    last_error = ""

    for attempt in range(1, MAX_GENERATION_ATTEMPTS + 1):
        prompt = build_generation_prompt(user_request, design_plan, feedback)
        raw = call_json_generation(client, prompt)

        try:
            scene_spec = parse_scene_spec(raw)
            errors = validate_scene_spec(scene_spec)
        except Exception as exc:
            scene_spec = None
            errors = [f"JSON 解析失败: {exc}"]

        if scene_spec is not None and not errors:
            print(f"生成成功，通过校验。attempt={attempt}")
            return scene_spec

        last_error = "\n".join(errors)
        print(f"生成结果未通过校验，准备重试。attempt={attempt}")
        print(last_error)
        feedback = (
            "上一版 JSON 不合格，请修正后只输出完整合法 JSON。\n"
            f"错误列表:\n{last_error}"
        )

    raise RuntimeError(f"生成 scene_spec.json 失败，最后错误:\n{last_error}")


def build_generation_prompt(user_request: str, design_plan: str, feedback: str = "") -> str:
    prompt = f"""用户需求:
{user_request}

设计方案:
{design_plan}

请基于以上内容生成 scene_spec.json。只输出合法 JSON。"""
    if feedback:
        prompt += f"\n\n{feedback}"
    return prompt


def call_json_generation(client: OpenAI, prompt: str) -> str:
    response = client.chat.completions.create(
        model=MODEL,
        messages=[
            {"role": "system", "content": GENERATION_SYSTEM_PROMPT},
            {"role": "user", "content": prompt},
        ],
        temperature=0.4,
        response_format={"type": "json_object"},
    )
    content = response.choices[0].message.content
    if not content:
        raise RuntimeError("生成阶段没有返回内容。")
    return content


def parse_scene_spec(raw: str) -> dict[str, Any]:
    parsed = json.loads(raw)
    if not isinstance(parsed, dict):
        raise ValueError("顶层 JSON 必须是 object。")
    return parsed


def validate_scene_spec(spec: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    required_keys = {"theme_name", "global_color_palette", "rooms", "booths", "lights"}
    missing = required_keys - set(spec)
    if missing:
        errors.append(f"缺少必要字段: {sorted(missing)}")
        return errors

    rooms = spec.get("rooms")
    booths = spec.get("booths")
    lights = spec.get("lights")
    palette = spec.get("global_color_palette")

    if not isinstance(palette, list) or not palette:
        errors.append("global_color_palette 必须是非空数组。")

    if not isinstance(rooms, list) or len(rooms) != 1:
        errors.append("rooms 必须是只包含一个房间的数组。")
        return errors

    room = rooms[0]
    if not isinstance(room, dict):
        errors.append("rooms[0] 必须是 object。")
        return errors

    dimensions = room.get("dimensions")
    if not is_number_array(dimensions, 3):
        errors.append("rooms[0].dimensions 必须是 3 个数字 [width, height, depth]。")
        return errors

    width, height, depth = [float(value) for value in dimensions]
    if width <= 0 or height <= 0 or depth <= 0:
        errors.append("room dimensions 必须为正数。")

    if not isinstance(room.get("wall_color"), str):
        errors.append("rooms[0].wall_color 必须是颜色字符串。")

    validate_booths(booths, width, depth, errors)
    validate_lights(lights, height, errors)

    return errors


def validate_booths(booths: Any, width: float, depth: float, errors: list[str]) -> None:
    if not isinstance(booths, list) or not booths:
        errors.append("booths 必须是非空数组。")
        return

    min_x = -width * 0.5 + BOOTH_HALF_SIZE
    max_x = width * 0.5 - BOOTH_HALF_SIZE
    min_z = -depth * 0.5 + BOOTH_HALF_SIZE
    max_z = depth * 0.5 - BOOTH_HALF_SIZE

    for index, booth in enumerate(booths):
        if not isinstance(booth, dict):
            errors.append(f"booths[{index}] 必须是 object。")
            continue

        position = booth.get("position")
        if not is_number_array(position, 3):
            errors.append(f"booths[{index}].position 必须是 3 个数字。")
            continue

        x, y, z = [float(value) for value in position]
        if not (min_x <= x <= max_x):
            errors.append(f"booths[{index}].position.x={x} 超出范围 [{min_x}, {max_x}]。")
        if y != 0.0:
            errors.append(f"booths[{index}].position.y 必须为 0.0。")
        if not (min_z <= z <= max_z):
            errors.append(f"booths[{index}].position.z={z} 超出范围 [{min_z}, {max_z}]。")

        if "orientation" not in booth or not isinstance(booth["orientation"], int | float):
            errors.append(f"booths[{index}].orientation 必须是数字。")


def validate_lights(lights: Any, height: float, errors: list[str]) -> None:
    if not isinstance(lights, list) or not lights:
        errors.append("lights 必须是非空数组。")
        return

    for index, light in enumerate(lights):
        if not isinstance(light, dict):
            errors.append(f"lights[{index}] 必须是 object。")
            continue

        position = light.get("position")
        if not is_number_array(position, 3):
            errors.append(f"lights[{index}].position 必须是 3 个数字。")
            continue

        y = float(position[1])
        if y < 1.5 or y > height + 0.5:
            errors.append(f"lights[{index}].position.y={y} 不合理，应位于房间上方区域。")

        intensity = light.get("intensity")
        if not isinstance(intensity, int | float) or not (250.0 <= float(intensity) <= 750.0):
            errors.append(f"lights[{index}].intensity 必须在 250.0 到 750.0 之间。")


def is_number_array(value: Any, expected_len: int) -> bool:
    return (
        isinstance(value, list)
        and len(value) == expected_len
        and all(isinstance(item, int | float) for item in value)
    )


def resolve_output_path(output: str | None) -> Path:
    if output:
        return Path(output)

    godot_scene_spec = Path("godot/shared/scene_spec.json")
    if godot_scene_spec.exists() or Path("godot/project.godot").exists():
        return godot_scene_spec

    return Path("shared/scene_spec.json")


def write_scene_spec(spec: dict[str, Any], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(spec, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def print_design_plan(design_plan: str) -> None:
    print("====== 设计方案 ======")
    print(design_plan)
    print("====================")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
