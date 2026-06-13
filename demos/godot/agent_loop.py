"""Mock world-building agent loop.

This file wires the Plan -> Act -> Observe -> Reflect -> Loop skeleton.
It intentionally uses mock planning/reflection by default so the full loop can
be tested before connecting real models.

Usage:
    python3 godot/agent_loop.py "build a cyberpunk NFT gallery"
"""

from __future__ import annotations

import argparse
import json
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


USE_MOCK = True
MAX_ROUNDS = 3
OBSERVE_TIMEOUT_SECONDS = 20.0
OBSERVE_POLL_SECONDS = 0.5

PROJECT_DIR = Path(__file__).resolve().parent
DEFAULT_SCENE_SPEC_PATH = PROJECT_DIR / "shared" / "scene_spec.json"
DEFAULT_RENDER_PATH = PROJECT_DIR / "shared" / "render.png"


@dataclass(frozen=True)
class Observation:
    image_path: Path
    image_bytes: bytes
    modified_time: float


def main() -> None:
    args = parse_args()
    run_loop(
        user_goal=args.user_goal,
        scene_spec_path=args.scene_spec,
        render_path=args.render,
        max_rounds=args.max_rounds,
        observe_timeout=args.observe_timeout,
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Mock world-building agent loop.")
    parser.add_argument("user_goal", help="自然语言世界/空间目标")
    parser.add_argument(
        "--scene-spec",
        type=Path,
        default=DEFAULT_SCENE_SPEC_PATH,
        help=f"Godot 监听的 scene_spec.json 路径，默认 {DEFAULT_SCENE_SPEC_PATH}",
    )
    parser.add_argument(
        "--render",
        type=Path,
        default=DEFAULT_RENDER_PATH,
        help=f"Godot 输出的 render.png 路径，默认 {DEFAULT_RENDER_PATH}",
    )
    parser.add_argument(
        "--max-rounds",
        type=int,
        default=MAX_ROUNDS,
        help=f"最大循环轮数，默认 {MAX_ROUNDS}",
    )
    parser.add_argument(
        "--observe-timeout",
        type=float,
        default=OBSERVE_TIMEOUT_SECONDS,
        help=f"等待 render.png 更新的秒数，默认 {OBSERVE_TIMEOUT_SECONDS}",
    )
    return parser.parse_args()


def run_loop(
    user_goal: str,
    scene_spec_path: Path,
    render_path: Path,
    max_rounds: int = MAX_ROUNDS,
    observe_timeout: float = OBSERVE_TIMEOUT_SECONDS,
) -> None:
    print("========== World-Building Agent Loop ==========")
    print(f"USE_MOCK = {USE_MOCK}")
    print(f"User goal: {user_goal}")
    print(f"scene_spec: {scene_spec_path}")
    print(f"render: {render_path}")
    print("================================================")

    current_feedback = "初始规划。"
    last_render_mtime = get_mtime(render_path)

    for round_index in range(1, max_rounds + 1):
        print(f"\n========== Round {round_index}/{max_rounds} ==========")

        print("\n[Plan] 根据目标和上一轮反馈生成 scene_spec...")
        scene_spec = plan(user_goal, current_feedback, round_index)
        validate_scene_spec(scene_spec)
        print_json_summary(scene_spec)

        print("\n[Act] 写入 scene_spec.json，触发 Godot 重建...")
        previous_render_mtime = last_render_mtime
        act(scene_spec, scene_spec_path)
        print(f"Wrote: {scene_spec_path}")

        print("\n[Observe] 等待并读取 render.png...")
        observation = observe(
            render_path=render_path,
            previous_mtime=previous_render_mtime,
            timeout_seconds=observe_timeout,
        )
        last_render_mtime = observation.modified_time
        print(
            "Observed image: "
            f"{observation.image_path} "
            f"({len(observation.image_bytes)} bytes, mtime={observation.modified_time:.3f})"
        )

        print("\n[Reflect] 基于截图生成反思建议...")
        current_feedback = reflect(user_goal, scene_spec, observation, round_index)
        print(f"Reflection: {current_feedback}")

    print("\n========== Loop finished ==========")
    print("Mock loop completed. Replace plan()/reflect() internals to connect real models.")


def plan(user_goal: str, feedback: str, round_index: int) -> dict[str, Any]:
    if USE_MOCK:
        return mock_plan(user_goal, feedback, round_index)

    # TODO: 接入 GLM / LLM 文本规划模型
    raise NotImplementedError("Real plan() is not implemented yet.")


def reflect(
    user_goal: str,
    scene_spec: dict[str, Any],
    observation: Observation,
    round_index: int,
) -> str:
    if USE_MOCK:
        booth_count = len(scene_spec.get("booths", []))
        if round_index == 1:
            return f"场景已生成，但展位偏少，目前 {booth_count} 个，建议下一轮增加展位并增强空间层次。"
        if round_index == 2:
            return f"展位数量提升到 {booth_count} 个，建议下一轮增加更均匀的展位分布和更丰富灯光。"
        return f"当前已有 {booth_count} 个展位，mock 闭环已跑通，可进入真实模型评估阶段。"

    # TODO: 接入 GLM 视觉模型
    raise NotImplementedError("Real reflect() is not implemented yet.")


def act(scene_spec: dict[str, Any], scene_spec_path: Path) -> None:
    scene_spec_path.parent.mkdir(parents=True, exist_ok=True)
    scene_spec_path.write_text(
        json.dumps(scene_spec, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def observe(
    render_path: Path,
    previous_mtime: float | None,
    timeout_seconds: float,
) -> Observation:
    deadline = time.monotonic() + timeout_seconds

    while time.monotonic() < deadline:
        if render_path.exists():
            current_mtime = render_path.stat().st_mtime
            if previous_mtime is None or current_mtime > previous_mtime:
                return read_observation(render_path)
        time.sleep(OBSERVE_POLL_SECONDS)

    if render_path.exists():
        print(
            "Warning: render.png 没有在超时时间内更新；"
            "将读取现有截图以便 mock 闭环继续运行。"
        )
        return read_observation(render_path)

    raise TimeoutError(f"等待 {render_path} 失败：文件不存在或未生成。")


def read_observation(render_path: Path) -> Observation:
    image_bytes = render_path.read_bytes()
    modified_time = render_path.stat().st_mtime
    return Observation(
        image_path=render_path,
        image_bytes=image_bytes,
        modified_time=modified_time,
    )


def mock_plan(user_goal: str, feedback: str, round_index: int) -> dict[str, Any]:
    booth_count = min(3 + round_index, 6)
    booth_positions = [
        [-3.2, 0.0, -3.8],
        [0.0, 0.0, -3.8],
        [3.2, 0.0, -3.8],
        [-3.2, 0.0, 1.0],
        [3.2, 0.0, 1.0],
        [0.0, 0.0, 4.2],
    ]
    booth_orientations = [12.0, 0.0, -12.0, 35.0, -35.0, 180.0]
    art_styles = ["nebula", "flow_field", "fractal", "voronoi", "mandala", "plasma"]
    art_names = ["星际漫游", "数据之河", "分形之梦", "仿生幻影", "电子曼陀罗", "量子脉冲"]

    booths = []
    for index in range(booth_count):
        booths.append(
            {
                "id": f"mock_booth_{index + 1}",
                "position": booth_positions[index],
                "orientation": booth_orientations[index],
                "nft": {
                    "name": art_names[index % len(art_names)],
                    "collection": "Mock Collection",
                    "art_style": art_styles[index % len(art_styles)],
                    "art_seed": (index + 1) * 1337,
                    "art_colors": [
                        "#F6C177", "#0B1F3A", "#8AB4F8", "#FFD6A5",
                    ],
                    "token_id": f"{(index + 1) * 1000:04d}",
                },
            }
        )

    theme_suffix = "Initial" if round_index == 1 else f"Iteration {round_index}"
    return {
        "theme_name": f"Mock World Gallery - {theme_suffix}",
        "global_color_palette": [
            "#0B1F3A",
            "#F6C177",
            "#FFD6A5",
            "#1F2937",
            "#8AB4F8",
        ],
        "rooms": [
            {
                "id": "main_hall",
                "dimensions": [12.0, 4.0, 14.0],
                "wall_color": "#243B55",
            }
        ],
        "booths": booths,
        "lights": [
            {
                "position": [-4.0, 3.5, -4.0],
                "color": "#F6C177",
                "intensity": 650.0,
            },
            {
                "position": [0.0, 3.5, 0.0],
                "color": "#FFD6A5",
                "intensity": 600.0,
            },
            {
                "position": [4.0, 3.5, 4.0],
                "color": "#8AB4F8",
                "intensity": 550.0,
            },
        ],
        "mock_meta": {
            "user_goal": user_goal,
            "previous_feedback": feedback,
            "round": round_index,
        },
    }


def validate_scene_spec(scene_spec: dict[str, Any]) -> None:
    required_keys = {"theme_name", "global_color_palette", "rooms", "booths", "lights"}
    missing = required_keys - set(scene_spec)
    if missing:
        raise ValueError(f"scene_spec missing keys: {sorted(missing)}")

    rooms = scene_spec["rooms"]
    if not isinstance(rooms, list) or not rooms:
        raise ValueError("scene_spec.rooms must be a non-empty list.")

    room = rooms[0]
    dimensions = room.get("dimensions")
    if not is_number_list(dimensions, 3):
        raise ValueError("room.dimensions must be [width, height, depth].")

    width, _height, depth = [float(value) for value in dimensions]
    min_x = -width * 0.5 + 0.75
    max_x = width * 0.5 - 0.75
    min_z = -depth * 0.5 + 0.75
    max_z = depth * 0.5 - 0.75

    for booth in scene_spec["booths"]:
        position = booth.get("position")
        if not is_number_list(position, 3):
            raise ValueError(f"Invalid booth position: {booth}")
        x, y, z = [float(value) for value in position]
        if not (min_x <= x <= max_x and y == 0.0 and min_z <= z <= max_z):
            raise ValueError(f"Booth out of room bounds: {booth}")


def is_number_list(value: Any, expected_len: int) -> bool:
    return (
        isinstance(value, list)
        and len(value) == expected_len
        and all(isinstance(item, int | float) for item in value)
    )


def print_json_summary(scene_spec: dict[str, Any]) -> None:
    room = scene_spec["rooms"][0]
    print(f"theme_name: {scene_spec['theme_name']}")
    print(f"palette: {scene_spec['global_color_palette']}")
    print(f"room: id={room['id']}, dimensions={room['dimensions']}, wall_color={room['wall_color']}")
    print(f"booths: {len(scene_spec['booths'])}")
    for booth in scene_spec["booths"]:
        print(f"  - {booth['id']}: pos={booth['position']}, orientation={booth['orientation']}")
    print(f"lights: {len(scene_spec['lights'])}")


def get_mtime(path: Path) -> float | None:
    return path.stat().st_mtime if path.exists() else None


if __name__ == "__main__":
    main()
