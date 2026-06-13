"""End-to-end agent loop for planning, rendering feedback, and revision.

CLI usage:
  python -m agent.main "build a cyberpunk NFT gallery"
  python -m agent.main --threshold 9 --max-rounds 5 "森林主题展厅"
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any

if __package__ is None or __package__ == "":
    sys.path.append(str(Path(__file__).resolve().parents[1]))

from agent.evaluator import EvaluationResult, evaluate
from agent.planner import plan
from agent.reviser import revise


DEFAULT_SCENE_SPEC_PATH = Path("godot/shared/scene_spec.json")
DEFAULT_RENDER_PATH = Path("godot/shared/render.png")
DEFAULT_SCORE_THRESHOLD = 8
DEFAULT_MAX_ROUNDS = 3
DEFAULT_SCREENSHOT_TIMEOUT_SECONDS = 60.0
SCREENSHOT_POLL_INTERVAL_SECONDS = 0.5


def main() -> None:
    args = _parse_args()
    user_request = args.request or input("Describe the exhibition hall you want: ").strip()
    if not user_request:
        raise SystemExit("A user request is required.")

    scene_spec_path = Path(args.scene_spec)
    render_path = Path(args.render)

    print("\n[Step 1] Optimizing prompt & generating scene spec...")
    reasoning, spec = plan(user_request)
    print(f"\nDesign reasoning: {reasoning or '(none)'}")

    last_render_mtime = _get_file_mtime(render_path)
    _write_scene_spec(spec, scene_spec_path)
    print(f"Wrote initial spec: {scene_spec_path}")

    for round_index in range(1, args.max_rounds + 1):
        print(f"\n=== Evaluation round {round_index}/{args.max_rounds} ===")

        # Wait for Godot to produce a new render
        try:
            last_render_mtime = _wait_for_screenshot(
                render_path,
                previous_mtime=last_render_mtime,
                timeout_seconds=args.screenshot_timeout,
            )
        except TimeoutError:
            print(f"  ⏰ No new render after {args.screenshot_timeout}s, auto-passing.")
            break

        # Evaluate with GLM-5.1 vision
        evaluation = evaluate(spec, str(render_path))
        _print_evaluation(evaluation)

        if evaluation.overall_score >= args.threshold:
            print(f"\n✅ Score {evaluation.overall_score} >= {args.threshold}, done!")
            break

        if round_index >= args.max_rounds:
            print(f"\n⚠️  Max rounds reached (score {evaluation.overall_score} < {args.threshold}).")
            break

        # Revise based on feedback
        print("\nRevising scene spec from evaluation feedback...")
        spec = revise(spec, evaluation)
        print(f"  theme: {spec.get('theme_name', '?')}, "
              f"booths: {len(spec.get('booths', []))}, "
              f"lights: {len(spec.get('lights', []))}")

        last_render_mtime = _get_file_mtime(render_path)
        _write_scene_spec(spec, scene_spec_path)
        print(f"Wrote revised spec: {scene_spec_path}")
    else:
        print("\nLoop ended without a satisfying score.")

    print(f"\nFinal spec written to: {scene_spec_path}")


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run the plan-render-evaluate-revise loop for the exhibition hall.",
    )
    parser.add_argument(
        "request",
        nargs="?",
        help="User request describing the target exhibition hall.",
    )
    parser.add_argument(
        "--threshold",
        type=int,
        default=DEFAULT_SCORE_THRESHOLD,
        help=f"Target overall score, default {DEFAULT_SCORE_THRESHOLD}.",
    )
    parser.add_argument(
        "--max-rounds",
        type=int,
        default=DEFAULT_MAX_ROUNDS,
        help=f"Maximum evaluation rounds, default {DEFAULT_MAX_ROUNDS}.",
    )
    parser.add_argument(
        "--scene-spec",
        default=str(DEFAULT_SCENE_SPEC_PATH),
        help=f"Path written for Godot to read, default {DEFAULT_SCENE_SPEC_PATH}.",
    )
    parser.add_argument(
        "--render",
        default=str(DEFAULT_RENDER_PATH),
        help=f"Path read after Godot screenshots, default {DEFAULT_RENDER_PATH}.",
    )
    parser.add_argument(
        "--screenshot-timeout",
        type=float,
        default=DEFAULT_SCREENSHOT_TIMEOUT_SECONDS,
        help=f"Seconds to wait for render.png updates, default {DEFAULT_SCREENSHOT_TIMEOUT_SECONDS}.",
    )
    return parser.parse_args()


def _write_scene_spec(spec: dict[str, Any], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(spec, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def _get_file_mtime(path: Path) -> float | None:
    return path.stat().st_mtime if path.exists() else None


def _wait_for_screenshot(
    render_path: Path,
    previous_mtime: float | None,
    timeout_seconds: float,
) -> float:
    start_time = time.monotonic()
    print(f"Waiting for Godot screenshot: {render_path}")
    while True:
        if render_path.exists():
            current_mtime = render_path.stat().st_mtime
            if previous_mtime is None or current_mtime > previous_mtime:
                print("  Screenshot detected.")
                return current_mtime

        if time.monotonic() - start_time > timeout_seconds:
            raise TimeoutError(
                f"Timed out after {timeout_seconds:.1f}s waiting for {render_path}."
            )

        time.sleep(SCREENSHOT_POLL_INTERVAL_SECONDS)


def _print_evaluation(evaluation: EvaluationResult) -> None:
    print(f"Overall score: {evaluation.overall_score}/10")
    print(f"  Circulation: {evaluation.circulation_rationality.problem_description}")
    print(f"  Booth density: {evaluation.booth_density.problem_description}")
    print(f"  Lighting: {evaluation.lighting_atmosphere.problem_description}")
    print(f"  Color: {evaluation.color_coordination.problem_description}")
    print(f"  Artwork: {evaluation.artwork_display_quality.problem_description}")


if __name__ == "__main__":
    main()
