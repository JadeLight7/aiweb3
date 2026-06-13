"""
GLM-5.1 场景规划器 — 使用 Anthropic 兼容 API

完整流程:
  1. 优化用户自然语言为专业 prompt
  2. GLM-5.1 生成 scene_spec.json
  3. 支持视觉评估 + 修复

CCGS Skills Applied:
  - gdscript-patterns: Type-safe scene spec with strict constraints
  - design-review: 5-dimension evaluation framework

环境变量:
  GLM_API_KEY — 智谱 AI API Key (必须)
  GLM_BASE_URL — API 地址 (默认 https://open.bigmodel.cn/api/anthropic)
  GLM_MODEL — 模型名 (默认 glm-5.1)
"""

from __future__ import annotations

import base64
import json
import logging
import os
import socket

# ---------------------------------------------------------------------------
# DNS fix: if local DNS cannot resolve open.bigmodel.cn, patch resolution
# ---------------------------------------------------------------------------
_original_getaddrinfo = socket.getaddrinfo
_DNS_OVERRIDES: dict[str, str] = {
    "open.bigmodel.cn": "119.23.85.51",
}


def _patched_getaddrinfo(host, port, *args, **kwargs):
    if isinstance(host, str) and host in _DNS_OVERRIDES:
        return [(socket.AF_INET, socket.SOCK_STREAM, 6, "", (_DNS_OVERRIDES[host], port))]
    return _original_getaddrinfo(host, port, *args, **kwargs)


socket.getaddrinfo = _patched_getaddrinfo
import re
from typing import Any

import urllib3

# Suppress InsecureRequestWarning for verify=False equivalent
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

logger = logging.getLogger(__name__)

# Shared connection pool (reused across calls)
_http_pool: urllib3.PoolManager | None = None


def _get_pool() -> urllib3.PoolManager:
    global _http_pool
    if _http_pool is None:
        _http_pool = urllib3.PoolManager(cert_reqs="CERT_NONE", timeout=120.0)
    return _http_pool

GLM_API_KEY = os.environ.get("GLM_API_KEY", "")
GLM_BASE_URL = os.environ.get("GLM_BASE_URL", "https://open.bigmodel.cn/api/anthropic")
GLM_MODEL = os.environ.get("GLM_MODEL", "glm-5.1")


# ================================================================
# Scene Spec 生成 Prompt
# ================================================================

PLAN_SYSTEM_PROMPT = """你是一名资深 3D 虚拟空间设计师，专注于 Web3 场景构建：NFT 展馆、游戏关卡、DAO 活动空间。

你的任务是根据用户需求，设计一个可以用 Godot 4 引擎直接渲染的 3D 虚拟展厅，每个展位展示一幅独特的 NFT 艺术品。

## 输出格式

输出严格合法 JSON，不要 markdown、不要注释、不要解释文字。结构如下：

{
  "reasoning": "设计理由（为什么这样布局、选这些颜色、这样安排展位和灯光）",
  "scene_spec": {
    "theme_name": "主题名称",
    "global_color_palette": ["#RRGGBB", "#RRGGBB", ...],
    "rooms": [
      {
        "id": "main_hall",
        "dimensions": [宽, 高, 深],
        "wall_color": "#RRGGBB"
      }
    ],
    "booths": [
      {
        "id": "booth_1",
        "position": [x, y, z],
        "orientation": 角度,
        "nft": {
          "name": "艺术品名称",
          "collection": "收藏集名称",
          "art_style": "gradient_noise",
          "art_seed": 42,
          "art_colors": ["#RRGGBB", "#RRGGBB", "#RRGGBB"],
          "token_id": ""
        }
      }
    ],
    "lights": [
      {
        "position": [x, y, z],
        "color": "#RRGGBB",
        "intensity": 数值
      }
    ]
  }
}

## Godot 硬性约束（必须严格遵守）

1. 只生成一个房间，id 固定为 "main_hall"
2. 房间尺寸建议：宽 10-20，高 4-8，深 12-24
3. 房间坐标系：中心为原点 (0,0,0)，地面 y=0
4. 展位 (booth) 位置约束：
   - x 范围: [-width/2 + 1, width/2 - 1]
   - y 必须为 0.0
   - z 范围: [-depth/2 + 1, depth/2 - 1]
   - 不要挡住中心通道 (x=0, z 中心线)
5. 展位数量：3-8 个，均匀分布
6. 灯光 (light) 位置约束：
   - y 值接近 height - 0.6（天花板下方）
   - 位置均匀分布
   - intensity 范围 300-700
7. 颜色使用 hex 格式 #RRGGBB
8. global_color_palette 提供 4-6 个颜色
9. 每个展位必须包含 nft 字段：
   - name: NFT 艺术品名称（有创意的名称，中英文均可）
   - collection: 收藏集名称
   - art_style: 从以下选择: "gradient_noise", "voronoi", "geometric", "plasma", "mandala", "pixel_art", "fractal", "nebula", "flow_field"
   - art_seed: 整数种子（0-9999），每个展位必须不同
   - art_colors: 3-4 个互补的 hex 颜色，用于程序化生成丰富、视觉吸引力强的艺术品图案
   - token_id: 可选的链上 token 标识符（字符串，可留空）
10. art_style 主题匹配建议：
   - fractal: 适合数学/自然/分形主题，产生递归几何图案
   - nebula: 适合太空/宇宙/科幻主题，产生星云般的渐变效果
   - flow_field: 适合有机/抽象/流动主题，产生流场线条图案

## 设计原则

- 主题一致性：颜色、灯光氛围、空间布局都要贴合用户需求
- 参观动线：从入口到各展位路径清晰，不拥堵
- 灯光层次：主灯 + 氛围灯 + 重点照明
- 展位分布：错落有致，不单调，留出互动空间
- 艺术多样性：每个展位的 nft.name、nft.art_style、nft.art_seed、nft.art_colors 都必须不同，创造丰富多样的艺术展览体验
- 艺术品命名：为每幅作品取一个与整体主题呼应的独特名称
- 色彩丰富度：art_colors 使用 3-4 个互补色，确保生成的艺术品色彩丰富、层次分明，提升视觉吸引力"""


USER_PROMPT_TEMPLATE = """请根据以下需求，设计一个 3D 虚拟展厅：

{enhanced_request}

请输出完整的 JSON 设计方案（包含 reasoning 和 scene_spec）。"""


def enhance_user_request(raw_request: str) -> str:
    """将用户自然语言需求优化为专业设计 prompt"""
    # 检测关键词并增强
    enhancements = []

    raw_lower = raw_request.lower()

    # 主题检测
    themes = {
        "赛博朋克": "赛博朋克风格：深暗底色 + 霓虹色（#FF00FF, #00FFFF, #FF6600），强对比度，科技未来感",
        "cyberpunk": "赛博朋克风格：深暗底色 + 霓虹色（#FF00FF, #00FFFF, #FF6600），强对比度，科技未来感",
        "森林": "森林自然风格：深绿 + 棕色 + 金色，有机曲线，自然光照",
        "沙漠": "沙漠风格：沙黄 + 赭石 + 深蓝天空，开阔空间，暖色调",
        "海洋": "海洋主题：深蓝 + 青绿 + 珊瑚色，流动感布局",
        "画廊": "专业画廊风格：白墙 + 柔和灯光 + 聚焦照明",
        "dao": "DAO 社区空间：开放式布局 + 多功能分区 + 投票/讨论区域",
        "nft": "NFT 展示重点：每个展位配独立灯光突出艺术品，沉浸式体验",
    }
    for keyword, desc in themes.items():
        if keyword in raw_lower:
            enhancements.append(desc)

    # 展位数量检测
    import re as _re
    num_match = _re.search(r'(\d+)\s*个展位|(\d+)\s*booths?', raw_lower)
    booth_count = int(num_match.group(1) or num_match.group(2)) if num_match else None

    if not enhancements:
        enhancements.append("现代简约风格：中性色调 + 重点色点缀 + 专业照明")

    enhanced = raw_request
    if enhancements:
        enhanced += "\n\n设计风格指引：" + "；".join(enhancements)
    if booth_count:
        enhanced += f"\n\n展位数量要求：{booth_count} 个"
    enhanced += "\n\n请确保布局合理，动线清晰，灯光有层次感。"

    return enhanced


def plan(user_request: str) -> tuple[str, dict]:
    """根据用户需求生成场景规划。

    Uses GLM-5.1 to generate a complete scene specification from natural language.
    Includes prompt enhancement with keyword detection for themes (cyberpunk, forest,
    ocean, etc.) and booth count extraction.

    Args:
        user_request: Raw natural language description from the user.

    Returns:
        Tuple of (reasoning: str, scene_spec: dict) where reasoning explains
        the design decisions and scene_spec follows the JSON schema expected
        by Godot's SceneBuilder.

    Raises:
        RuntimeError: If GLM API fails after max retries.
        ValueError: If response cannot be parsed as valid JSON.
    """
    """
    根据用户需求生成场景规划。

    Returns:
        (reasoning, scene_spec_dict)
    """
    enhanced = enhance_user_request(user_request)
    logger.info(f"[Planner] Enhanced request: {enhanced[:100]}...")

    raw_response = _call_glm(
        system_prompt=PLAN_SYSTEM_PROMPT,
        user_prompt=USER_PROMPT_TEMPLATE.format(enhanced_request=enhanced),
    )
    payload = _parse_json_with_tolerance(raw_response)

    reasoning = str(
        payload.get("reasoning")
        or payload.get("design_reasoning")
        or payload.get("rationale")
        or ""
    )
    spec_payload = payload.get("scene_spec") or payload.get("spec") or payload

    logger.info(f"[Planner] Reasoning: {reasoning[:100]}...")
    return reasoning, spec_payload


# ================================================================
# GLM API 调用
# ================================================================

def _call_glm(system_prompt: str, user_prompt: str, max_retries: int = 2) -> str:
    """调用 GLM-5.1 Anthropic 兼容 API，带重试。"""
    api_key = os.environ.get("GLM_API_KEY", GLM_API_KEY)
    if not api_key:
        raise RuntimeError("GLM_API_KEY is required. Set the environment variable.")

    base_url = os.environ.get("GLM_BASE_URL", GLM_BASE_URL).rstrip("/")
    model = os.environ.get("GLM_MODEL", GLM_MODEL)
    url = f"{base_url}/v1/messages"

    body: dict[str, Any] = {
        "model": model,
        "max_tokens": 4096,
        "messages": [{"role": "user", "content": user_prompt}],
        "temperature": 0.7,
    }
    if system_prompt:
        body["system"] = system_prompt

    headers = {
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "Content-Type": "application/json",
    }

    last_error = None
    for attempt in range(1, max_retries + 1):
        try:
            pool = _get_pool()
            resp = pool.request(
                "POST", url,
                headers=headers,
                body=json.dumps(body, ensure_ascii=False).encode("utf-8"),
            )

            if resp.status >= 400:
                last_error = f"HTTP {resp.status}: {resp.data[:200].decode('utf-8', errors='replace')}"
                logger.warning(f"[GLM] HTTP error on attempt {attempt}: {last_error}")
                if resp.status in (401, 403, 404):
                    break
                if attempt < max_retries:
                    import time; time.sleep(2 * attempt)
                continue

            data = json.loads(resp.data.decode("utf-8"))
            content = ""
            for block in data.get("content", []):
                if block.get("type") == "text":
                    content += block.get("text", "")

            usage = data.get("usage", {})
            logger.info(
                f"[GLM] OK: {len(content)} chars, "
                f"tokens: {usage.get('input_tokens', '?')}in/{usage.get('output_tokens', '?')}out"
            )
            return content

        except Exception as exc:
            last_error = str(exc)
            logger.warning(f"[GLM] Error on attempt {attempt}: {last_error}")

        if attempt < max_retries:
            import time; time.sleep(2 * attempt)

    raise RuntimeError(f"GLM API failed after {max_retries} attempts: {last_error}")


def call_glm_vision(system_prompt: str, prompt_text: str, image_path: str) -> str:
    """调用 GLM-5.1 多模态 API（图片+文本）。"""
    api_key = os.environ.get("GLM_API_KEY", GLM_API_KEY)
    if not api_key:
        raise RuntimeError("GLM_API_KEY is required.")

    base_url = os.environ.get("GLM_BASE_URL", GLM_BASE_URL).rstrip("/")
    model = os.environ.get("GLM_MODEL", GLM_MODEL)
    url = f"{base_url}/v1/messages"

    # 读取并编码图片
    with open(image_path, "rb") as f:
        image_data = base64.b64encode(f.read()).decode("utf-8")

    ext = os.path.splitext(image_path)[1].lower()
    media_type = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg"}.get(ext, "image/png")

    body: dict[str, Any] = {
        "model": model,
        "max_tokens": 2048,
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "image",
                        "source": {"type": "base64", "media_type": media_type, "data": image_data},
                    },
                    {"type": "text", "text": prompt_text},
                ],
            }
        ],
        "temperature": 0.5,
    }
    if system_prompt:
        body["system"] = system_prompt

    headers = {
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "Content-Type": "application/json",
    }

    logger.info(f"[GLM Vision] Calling with image ({ext}, {len(image_data)} chars base64)...")
    pool = _get_pool()
    resp = pool.request(
        "POST", url,
        headers=headers,
        body=json.dumps(body, ensure_ascii=False).encode("utf-8"),
    )
    resp.raise_for_status()

    data = json.loads(resp.data.decode("utf-8"))
    content = ""
    for block in data.get("content", []):
        if block.get("type") == "text":
            content += block.get("text", "")

    logger.info(f"[GLM Vision] OK: {len(content)} chars")
    return content


# ================================================================
# JSON 解析工具
# ================================================================

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
        f"Could not parse JSON from LLM response. Errors: {'; '.join(errors[:3])}"
    )


def _strip_markdown_fence(text: str) -> str:
    match = re.search(r"```(?:json)?\s*(.*?)\s*```", text, flags=re.DOTALL | re.IGNORECASE)
    return match.group(1) if match else text


def _extract_json_object_candidates(text: str) -> list[str]:
    candidates: list[str] = []
    for start in (i for i, c in enumerate(text) if c == "{"):
        depth = 0
        in_string = False
        escaped = False
        for i in range(start, len(text)):
            c = text[i]
            if in_string:
                if escaped:
                    escaped = False
                elif c == "\\":
                    escaped = True
                elif c == '"':
                    in_string = False
                continue
            if c == '"':
                in_string = True
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    candidates.append(text[start : i + 1])
                    break
    return candidates
