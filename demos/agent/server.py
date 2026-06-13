"""
Agent Server — FastAPI SSE endpoint for the 3D World Builder Agent.

启动: python -m agent.server
访问: http://localhost:8001

API:
  POST /agent/generate  — SSE stream of agent execution events
  GET  /agent/status    — server status
  GET  /agent/screenshot — latest render.png from Godot
  GET  /                — Web UI (agent/web_ui.html)
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
from pathlib import Path
from typing import Any

import uvicorn
from fastapi import FastAPI
from fastapi.responses import FileResponse, HTMLResponse, StreamingResponse
from pydantic import BaseModel

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger(__name__)

app = FastAPI(title="3D World Builder Agent")

# Godot shared paths
AGENT_DIR = Path(__file__).resolve().parent
DEMOS_DIR = AGENT_DIR.parent
GODOT_SHARED = DEMOS_DIR / "godot" / "shared"
SCENE_SPEC_PATH = GODOT_SHARED / "scene_spec.json"
RENDER_PATH = GODOT_SHARED / "render.png"


class AgentRequest(BaseModel):
    request: str = ""


@app.get("/")
async def index():
    """Serve the web UI."""
    ui_path = AGENT_DIR / "web_ui.html"
    if ui_path.exists():
        return HTMLResponse(ui_path.read_text(encoding="utf-8"))
    return HTMLResponse("<h1>Agent Server</h1><p>Web UI not found at agent/web_ui.html</p>")


@app.get("/agent/status")
async def agent_status():
    """Check server and Godot status."""
    return {
        "status": "ok",
        "godot_shared": str(GODOT_SHARED),
        "spec_exists": SCENE_SPEC_PATH.exists(),
        "render_exists": RENDER_PATH.exists(),
        "glm_key_set": bool(os.environ.get("GLM_API_KEY")),
    }


@app.get("/agent/screenshot")
async def agent_screenshot():
    """Serve the latest render.png from Godot."""
    if RENDER_PATH.exists():
        return FileResponse(RENDER_PATH, media_type="image/png")
    return HTMLResponse("<p>No render.png yet. Run Godot first.</p>", status_code=404)


@app.get("/agent/scene_spec")
async def agent_scene_spec():
    """Serve the current scene_spec.json."""
    if SCENE_SPEC_PATH.exists():
        return json.loads(SCENE_SPEC_PATH.read_text(encoding="utf-8"))
    return {"error": "No scene_spec.json yet"}


@app.get("/agent/web3-status")
async def web3_status():
    """Check Web3 configuration and connection status."""
    enabled = os.environ.get("WEB3_ENABLED", "false").lower() == "true"
    result: dict[str, Any] = {
        "enabled": enabled,
        "chain": os.environ.get("WEB3_CHAIN", "anvil"),
    }
    if enabled:
        try:
            from agent.web3.config import Web3Config
            from web3 import Web3
            config = Web3Config.from_env()
            w3 = Web3(Web3.HTTPProvider(config.rpc_url))
            result["connected"] = w3.is_connected()
            result["chain_id"] = config.chain_id
            result["wallet_address"] = config.wallet_address
            result["contract_address"] = config.contract_address
        except Exception as e:
            result["error"] = str(e)
            result["connected"] = False
    return result


@app.post("/agent/generate")
async def agent_generate(request: AgentRequest):
    """
    SSE endpoint for agent-driven world generation.

    Streams events:
    - plan_created: GLM-5.1's task decomposition
    - step_started / step_completed / step_failed: tool execution
    - render_ready: Godot screenshot available
    - evaluation_result: vision evaluation score
    - repair_started / repair_completed: repair process
    - generation_complete: final result
    """
    from agent.orchestrator import WorldBuilderAgent

    queue: asyncio.Queue = asyncio.Queue()

    async def event_callback(event: dict):
        await queue.put(event)

    async def event_stream():
        agent = WorldBuilderAgent(
            event_callback=event_callback,
            scene_spec_path=SCENE_SPEC_PATH,
            render_path=RENDER_PATH,
        )
        agent_task = asyncio.create_task(agent.run(request.request or "build a cyberpunk NFT gallery"))

        try:
            while True:
                if agent_task.done() and queue.empty():
                    break
                try:
                    event = await asyncio.wait_for(queue.get(), timeout=0.1)
                    yield f"data: {json.dumps(event, ensure_ascii=False)}\n\n"
                except asyncio.TimeoutError:
                    continue
        except asyncio.CancelledError:
            if not agent_task.done():
                agent_task.cancel()
            return
        except Exception as e:
            logger.exception(f"SSE stream error: {e}")
            yield f"data: {json.dumps({'type': 'error', 'data': {'error': str(e)}})}\n\n"

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "Connection": "keep-alive", "X-Accel-Buffering": "no"},
    )


if __name__ == "__main__":
    port = int(os.environ.get("AGENT_PORT", "8001"))
    uvicorn.run(
        "agent.server:app",
        host="0.0.0.0",
        port=port,
        reload=True,
        log_level="info",
    )
