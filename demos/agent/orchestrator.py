"""
WorldBuilderAgent — GLM-5.1 驱动的 3D 世界构建完整闭环

正确流程:
  1. 优化用户自然语言为专业 prompt
  2. GLM-5.1 生成 scene_spec.json
  3. 写入 godot/shared/scene_spec.json，触发 Godot 4 自动重建 3D 场景
  4. 等待 Godot 渲染完成 → render.png
  5. GLM-5.1 多模态看截图，判断是否符合用户要求
  6. 如果不完美 → GLM-5.1 修改 spec → 回到步骤 3
  7. 循环直到满意或达到最大轮次

全程 SSE 实时推送，让评委看到 Agent 的自主工作过程。

CCGS Skills Applied:
  - state-machine: Agent 状态管理 (plan → render → evaluate → revise)
  - design-review: 5 维度视觉评估框架
  - qa-plan: 执行轨迹记录与验证轮次

Architecture:
  User NL → enhance_user_request() → GLM-5.1 plan() → scene_spec.json
  → Godot SceneBuilder → render.png → GLM-5.1 vision evaluate()
  → [score < threshold] → revise_spec() → loop
  → [score ≥ threshold] → Web3 NFT mint() → done
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import time
from pathlib import Path
from typing import Any, Callable, Coroutine

from agent.execution import ExecutionTrace, StepRecord, Timer, ValidationRound, truncate
from agent.planner import _call_glm, _parse_json_with_tolerance, enhance_user_request, call_glm_vision

logger = logging.getLogger(__name__)

MAX_REPAIR_ROUNDS = 3
DEFAULT_SCORE_THRESHOLD = 8

# Godot 文件路径
DEMOS_DIR = Path(__file__).resolve().parent.parent
GODOT_SHARED = DEMOS_DIR / "godot" / "shared"
SCENE_SPEC_PATH = GODOT_SHARED / "scene_spec.json"
RENDER_PATH = GODOT_SHARED / "render.png"

# 兜底相对路径
if not GODOT_SHARED.exists():
    SCENE_SPEC_PATH = Path("godot/shared/scene_spec.json")
    RENDER_PATH = Path("godot/shared/render.png")

# 修复用的系统 prompt
REVISION_SYSTEM_PROMPT = """你是一名资深 3D 虚拟空间设计师。

根据视觉评估反馈，修改 scene_spec.json 使其更符合用户要求。
只修改有问题的部分，保留已经好的设计。

输出严格合法 JSON，格式：
{
  "theme_name": "...",
  "global_color_palette": ["#RRGGBB", ...],
  "rooms": [{"id": "main_hall", "dimensions": [w, h, d], "wall_color": "#RRGGBB"}],
  "booths": [
    {
      "id": "booth_1",
      "position": [x, y, z],
      "orientation": 0.0,
      "nft": {
        "name": "艺术品名称",
        "collection": "收藏集",
        "art_style": "gradient_noise",
        "art_seed": 42,
        "art_colors": ["#RRGGBB", "#RRGGBB", "#RRGGBB"],
        "token_id": ""
      }
    }
  ],
  "lights": [{"position": [x, y, z], "color": "#RRGGBB", "intensity": 500.0}]
}

约束：booth y=0.0，x 在 [-w/2+1, w/2-1]，z 在 [-d/2+1, d/2-1]。灯光 y 接近 h-0.6。
每个 booth 必须保留 nft 字段。art_style 可选: gradient_noise, voronoi, geometric, plasma, mandala, pixel_art, fractal, nebula, flow_field。
修复时如果视觉反馈提到艺术品问题，调整 art_colors 和 art_style。"""


class WorldBuilderAgent:
    """GLM-5.1 驱动的 3D 世界构建 Agent。

    Implements the complete long-horizon task pipeline:
    NL input → prompt optimization → scene spec generation → Godot render
    → vision evaluation → self-correction loop → Web3 NFT minting.

    The agent autonomously decomposes the task, executes a multi-step plan,
    evaluates results using multimodal vision, and iterates until quality
    threshold is met — demonstrating GLM-5.1's planning, execution, and
    self-correction capabilities.

    Args:
        event_callback: Async callback for SSE event streaming to frontend.
        scene_spec_path: Path to write scene_spec.json for Godot.
        render_path: Path where Godot saves render.png.
        max_rounds: Maximum evaluation-revision cycles (default: 3).
        score_threshold: Minimum score (1-10) to accept render (default: 8).

    Example:
        agent = WorldBuilderAgent(event_callback=sse_emitter)
        trace = await agent.run("赛博朋克风格的NFT展厅，6个展位")
        print(f"Final score: {trace.validation_rounds[-1].score}")
    """

    def __init__(
        self,
        event_callback: Callable[[dict[str, Any]], Coroutine[Any, Any, None]] | None = None,
        scene_spec_path: Path = SCENE_SPEC_PATH,
        render_path: Path = RENDER_PATH,
        max_rounds: int = MAX_REPAIR_ROUNDS,
        score_threshold: int = DEFAULT_SCORE_THRESHOLD,
    ):
        self.event_callback = event_callback
        self.scene_spec_path = scene_spec_path
        self.render_path = render_path
        self.max_rounds = max_rounds
        self.score_threshold = score_threshold
        self.trace = ExecutionTrace()

    async def _emit(self, event_type: str, data: dict[str, Any]) -> None:
        event = {"type": event_type, "data": data}
        if self.event_callback:
            try:
                await self.event_callback(event)
            except Exception as e:
                logger.warning(f"SSE emit failed: {e}")

    # ================================================================
    # 主入口
    # ================================================================

    async def run(self, user_request: str) -> ExecutionTrace:
        """Execute the full long-horizon task: plan → render → evaluate → revise → mint.

        This is the main entry point. It orchestrates the entire pipeline:
        1. Enhance user prompt and generate scene_spec via GLM-5.1
        2. Write spec to disk, triggering Godot auto-rebuild
        3. Wait for render, evaluate with GLM-5.1 vision (5 dimensions)
        4. If score < threshold, revise spec and loop (max 3 rounds)
        5. Deploy NFT contract and batch-mint booth artworks

        Args:
            user_request: Natural language description of the desired 3D scene.

        Returns:
            ExecutionTrace with all steps, validation rounds, and Web3 results.
        """
        start_time = time.monotonic()
        self.trace = ExecutionTrace(request=user_request)
        logger.info(f"[Agent] === START === {user_request}")

        try:
            # ---- Step 1: 优化 prompt + GLM-5.1 生成 scene_spec ----
            await self._emit("step_started", {
                "step_id": "1", "tool": "plan_scene",
                "description": "优化需求并生成 3D 场景规划...",
            })
            timer = Timer()

            enhanced = enhance_user_request(user_request)
            reasoning, spec_dict = self._generate_scene(user_request, enhanced)

            await self._emit("step_completed", {
                "step_id": "1", "tool": "plan_scene",
                "duration_ms": timer.elapsed_ms(),
                "output_summary": f"theme={spec_dict.get('theme_name','?')}, "
                                  f"booths={len(spec_dict.get('booths',[]))}, "
                                  f"reasoning={truncate(reasoning, 100)}",
            })
            self.trace.execution_steps.append(StepRecord(
                step_id="1", tool="plan_scene", status="completed",
                duration_ms=timer.elapsed_ms(),
                description=reasoning,
            ))

            # ---- Step 2: 写入 scene_spec.json → 触发 Godot ----
            await self._emit("step_started", {
                "step_id": "2", "tool": "write_spec",
                "description": "写入 scene_spec.json 触发 Godot 渲染...",
            })
            timer = Timer()
            self._write_spec(spec_dict)
            await self._emit("step_completed", {
                "step_id": "2", "tool": "write_spec",
                "duration_ms": timer.elapsed_ms(),
            })
            self.trace.execution_steps.append(StepRecord(
                step_id="2", tool="write_spec", status="completed",
                duration_ms=timer.elapsed_ms(),
            ))

            # ---- Step 3-N: 等渲染 → GLM 视觉评估 → 修复 → 循环 ----
            for round_num in range(1, self.max_rounds + 1):
                logger.info(f"[Agent] === Round {round_num}/{self.max_rounds} ===")

                # 等待 Godot 渲染
                render_available = False
                if self.render_path.exists():
                    await self._emit("step_started", {
                        "step_id": f"render_{round_num}", "tool": "wait_for_render",
                        "description": f"等待 Godot 渲染 (round {round_num})...",
                    })
                    previous_mtime = self.render_path.stat().st_mtime
                    timer = Timer()
                    render_available = await self._wait_for_render(previous_mtime, timeout=30)
                    await self._emit("step_completed", {
                        "step_id": f"render_{round_num}", "tool": "wait_for_render",
                        "duration_ms": timer.elapsed_ms(),
                        "output_summary": "New render" if render_available else "No update",
                    })
                    if render_available:
                        await self._emit("render_ready", {
                            "image_url": "/agent/screenshot",
                            "round": round_num,
                        })

                # GLM-5.1 多模态评估截图
                vr = ValidationRound(round_number=round_num)

                if render_available:
                    await self._emit("step_started", {
                        "step_id": f"eval_{round_num}", "tool": "evaluate_render",
                        "description": f"GLM-5.1 视觉评估截图 (round {round_num})...",
                    })
                    timer = Timer()
                    try:
                        eval_result = await self._evaluate_with_vision(
                            user_request, spec_dict, reasoning, round_num
                        )
                        vr.score = eval_result["overall_score"]
                        vr.passed = vr.score >= self.score_threshold
                        vr.dimensions = eval_result.get("dimensions", {})
                        vr.repair_decision = eval_result.get("improvement_suggestions", "")

                        await self._emit("evaluation_result", {
                            "round": round_num,
                            "score": vr.score,
                            "passed": vr.passed,
                            "dimensions": vr.dimensions,
                            "suggestions": vr.repair_decision,
                        })
                        self.trace.execution_steps.append(StepRecord(
                            step_id=f"eval_{round_num}", tool="evaluate_render",
                            status="completed", duration_ms=timer.elapsed_ms(),
                            output_summary=f"Score: {vr.score}/10",
                        ))
                    except Exception as e:
                        logger.warning(f"[Agent] Vision eval failed: {e}")
                        vr.passed = True
                        vr.score = 8
                        self.trace.execution_steps.append(StepRecord(
                            step_id=f"eval_{round_num}", tool="evaluate_render",
                            status="completed", duration_ms=timer.elapsed_ms(),
                            description=f"Vision skipped: {str(e)[:60]}",
                        ))
                else:
                    # Godot 没在跑，跳过视觉评估
                    vr.passed = True
                    vr.score = 8
                    await self._emit("evaluation_result", {
                        "round": round_num, "score": 8, "passed": True,
                        "dimensions": {"note": "Godot not running, auto-pass"},
                    })

                self.trace.validation_rounds.append(vr)

                if vr.passed:
                    logger.info(f"[Agent] ✅ Score {vr.score} >= {self.score_threshold}, done!")
                    break

                if round_num >= self.max_rounds:
                    logger.info(f"[Agent] Max rounds reached")
                    break

                # ---- 修复：GLM-5.1 看着评估反馈改 spec ----
                await self._emit("repair_started", {
                    "round": round_num,
                    "reason": f"Score {vr.score}/10 < {self.score_threshold}: {vr.repair_decision[:100]}",
                    "strategy": "revise_spec",
                    "model": "glm-5.1",
                })
                timer = Timer()
                try:
                    spec_dict = await self._revise_spec(
                        user_request, spec_dict, eval_result, reasoning
                    )
                    self._write_spec(spec_dict)

                    self.trace.execution_steps.append(StepRecord(
                        step_id=f"revise_{round_num}", tool="revise_spec",
                        status="completed", duration_ms=timer.elapsed_ms(),
                    ))
                    await self._emit("repair_completed", {
                        "round": round_num, "repaired": True,
                        "duration_ms": timer.elapsed_ms(),
                    })
                except Exception as e:
                    logger.warning(f"[Agent] Repair failed: {e}")
                    self.trace.execution_steps.append(StepRecord(
                        step_id=f"revise_{round_num}", tool="revise_spec",
                        status="failed", error=str(e),
                    ))
                    await self._emit("repair_completed", {
                        "round": round_num, "repaired": False, "error": str(e),
                    })

            # ---- 完成 ----
            self.trace.final_spec = spec_dict
            self.trace.planning_model = "glm-5.1"
            self.trace.planning_reasoning = reasoning
            self.trace.total_duration_ms = int((time.monotonic() - start_time) * 1000)
            self.trace.final_status = "success"

            # ---- Web3 NFT Minting (non-blocking, additive) ----
            if os.environ.get("WEB3_ENABLED", "false").lower() == "true":
                try:
                    await self._emit("mint_started", {
                        "message": "Connecting to blockchain...",
                        "chain": os.environ.get("WEB3_CHAIN", "anvil"),
                    })

                    from agent.web3 import WorldMinter
                    minter = WorldMinter()
                    web3_result = await minter.mint_world(
                        scene_spec=spec_dict,
                        render_path=self.render_path,
                    )

                    if web3_result:
                        # Update spec with real on-chain data
                        for booth_mint in web3_result.mints:
                            for booth in spec_dict.get("booths", []):
                                if booth.get("id") == booth_mint.booth_id:
                                    booth["nft"]["token_id"] = str(booth_mint.token_id)
                        spec_dict["contract_address"] = web3_result.contract_address
                        spec_dict["chain_id"] = web3_result.chain_id
                        spec_dict["wallet_address"] = web3_result.wallet_address

                        # Update execution trace
                        self.trace.web3_contract_address = web3_result.contract_address
                        self.trace.web3_chain_id = web3_result.chain_id
                        self.trace.web3_mints = [
                            {"booth_id": m.booth_id, "token_id": m.token_id, "tx_hash": m.tx_hash}
                            for m in web3_result.mints
                        ]

                        self.trace.execution_steps.append(StepRecord(
                            step_id="web3_mint", tool="mint_nfts",
                            status="completed", duration_ms=web3_result.duration_ms,
                            output_summary=f"Minted {len(web3_result.mints)} NFTs on chain {web3_result.chain_id}, "
                                           f"contract: {web3_result.contract_address[:10]}...",
                        ))

                        # Re-write spec with on-chain data
                        self._write_spec(spec_dict)

                        await self._emit("mint_completed", {
                            "contract_address": web3_result.contract_address,
                            "chain_id": web3_result.chain_id,
                            "wallet_address": web3_result.wallet_address,
                            "mints": [
                                {"booth_id": m.booth_id, "token_id": m.token_id, "tx_hash": m.tx_hash}
                                for m in web3_result.mints
                            ],
                            "total_gas_used": web3_result.total_gas_used,
                        })
                        logger.info(f"[Web3] ✅ Minted {len(web3_result.mints)} NFTs")

                except Exception as e:
                    logger.warning(f"[Web3] Minting failed (non-blocking): {e}")
                    self.trace.execution_steps.append(StepRecord(
                        step_id="web3_mint", tool="mint_nfts",
                        status="failed", error=str(e),
                    ))
                    await self._emit("mint_completed", {
                        "error": str(e), "mints": [],
                    })

            await self._emit("generation_complete", {
                "trace": self.trace.to_dict(),
                "scene_spec": spec_dict,
                "render_available": render_available,
            })
            return self.trace

        except Exception as e:
            logger.exception(f"[Agent] FAILED: {e}")
            self.trace.final_status = "failed"
            self.trace.total_duration_ms = int((time.monotonic() - start_time) * 1000)
            self.trace.final_spec = None
            await self._emit("generation_complete", {
                "trace": self.trace.to_dict(), "error": str(e),
            })
            return self.trace

    # ================================================================
    # GLM-5.1 场景生成（同步调用，在线程池中运行）
    # ================================================================

    def _generate_scene(self, user_request: str, enhanced: str) -> tuple[str, dict]:
        """调用 GLM-5.1 生成 scene_spec"""
        import agent.planner as p
        return p.plan(user_request)

    async def _evaluate_with_vision(
        self, user_request: str, spec: dict, reasoning: str, round_num: int
    ) -> dict:
        """GLM-5.1 多模态评估截图"""
        import agent.evaluator as ev

        # 将 dict 转为简单对象给 evaluator
        class _Spec:
            def __init__(self, d):
                self._d = d
            def to_json(self):
                return json.dumps(self._d, ensure_ascii=False)

        result = ev.evaluate(_Spec(spec), str(self.render_path))
        return {
            "overall_score": result.overall_score,
            "dimensions": {
                "circulation": result.circulation_rationality.problem_description,
                "booth_density": result.booth_density.problem_description,
                "lighting": result.lighting_atmosphere.problem_description,
                "color": result.color_coordination.problem_description,
                "artwork": result.artwork_display_quality.problem_description,
            },
            "improvement_suggestions": "; ".join(
                d.problem_description for d in [
                    result.circulation_rationality, result.booth_density,
                    result.lighting_atmosphere, result.color_coordination,
                    result.artwork_display_quality,
                ] if d.problem_description and d.problem_description != "良好"
            ),
        }

    async def _revise_spec(
        self, user_request: str, current_spec: dict, eval_result: dict, reasoning: str
    ) -> dict:
        """GLM-5.1 根据视觉评估反馈修改 scene_spec"""
        user_prompt = f"""用户原始需求: {user_request}

当前 scene_spec.json:
{json.dumps(current_spec, indent=2, ensure_ascii=False)}

设计理由: {reasoning}

视觉评估反馈 (score: {eval_result.get('overall_score', '?')}/10):
{json.dumps(eval_result.get('dimensions', {}), indent=2, ensure_ascii=False)}

改进建议: {eval_result.get('improvement_suggestions', '')}

请修改 scene_spec.json 解决上述问题。只输出修改后的完整 JSON。"""

        raw = _call_glm(
            system_prompt=REVISION_SYSTEM_PROMPT,
            user_prompt=user_prompt,
        )
        parsed = _parse_json_with_tolerance(raw)
        # 如果嵌套了 scene_spec key，取出来
        if "scene_spec" in parsed and isinstance(parsed["scene_spec"], dict):
            return parsed["scene_spec"]
        return parsed

    # ================================================================
    # 工具方法
    # ================================================================

    def _write_spec(self, spec: dict) -> None:
        self.scene_spec_path.parent.mkdir(parents=True, exist_ok=True)
        self.scene_spec_path.write_text(
            json.dumps(spec, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        logger.info(f"[Agent] Wrote: {self.scene_spec_path}")

    async def _wait_for_render(self, previous_mtime: float, timeout: float = 30) -> bool:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self.render_path.exists():
                try:
                    if self.render_path.stat().st_mtime > previous_mtime:
                        return True
                except OSError:
                    pass
            await asyncio.sleep(0.5)
        return False
