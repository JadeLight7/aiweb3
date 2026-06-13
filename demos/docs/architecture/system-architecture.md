# System Architecture: AI-Powered 3D World Builder

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Web Dashboard (SSE)                    │
│              agent/web_ui.html :8001                      │
└────────────────────────┬────────────────────────────────┘
                         │ SSE Events
┌────────────────────────▼────────────────────────────────┐
│                  FastAPI Server                           │
│              agent/server.py :8001                        │
│  ┌──────────────────────────────────────────────────┐   │
│  │           WorldBuilderAgent                        │   │
│  │         agent/orchestrator.py                      │   │
│  │                                                    │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────────┐   │   │
│  │  │ Planner  │  │ Evaluator│  │   Reviser     │   │   │
│  │  │ planner.py│  │evaluator.py│ │  reviser.py  │   │   │
│  │  └────┬─────┘  └────┬─────┘  └──────┬───────┘   │   │
│  │       │              │               │            │   │
│  │       ▼              ▼               ▼            │   │
│  │  ┌──────────────────────────────────────────┐    │   │
│  │  │     GLM-5.1 API (Anthropic-compatible)    │    │   │
│  │  │     open.bigmodel.cn/api/anthropic        │    │   │
│  │  └──────────────────────────────────────────┘    │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │              File-based IPC Layer                  │   │
│  │    godot/shared/scene_spec.json ←→ render.png     │   │
│  └──────────────────────┬───────────────────────────┘   │
└─────────────────────────┼───────────────────────────────┘
                          │ File Watch
┌─────────────────────────▼───────────────────────────────┐
│                Godot 4.6 Engine                          │
│           godot/scripts/scene_builder.gd                 │
│  ┌────────┐ ┌────────┐ ┌────────┐ ┌──────────────┐    │
│  │ Room   │ │ Booth  │ │  Art   │ │  Lighting    │    │
│  │Builder │ │Builder │ │Generator│ │   Builder    │    │
│  └────────┘ └────────┘ └────────┘ └──────────────┘    │
│  ┌────────┐ ┌──────────────────────────────────────┐   │
│  │Camera  │ │     Decoration Builder               │   │
│  │Control │ │  (orbs, dust, molding, chandelier)   │   │
│  └────────┘ └──────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────┐
│              Web3 / Blockchain Layer                     │
│  ┌─────────────────┐  ┌──────────────────────────┐     │
│  │  WorldMinter     │  │  NFTContract (ERC-721)   │     │
│  │  web3/minter.py  │  │  web3/contract.py         │     │
│  └────────┬────────┘  └──────────────────────────┘     │
│           │                                               │
│  ┌────────▼────────────────────────────────────────┐    │
│  │  Anvil (Local) / Sepolia (Testnet)              │    │
│  │  WorldBuilderNFT.sol (Foundry)                   │    │
│  └─────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────┘
```

## Component Details

### 1. Agent Layer (Python)

| Component | File | Responsibility |
|-----------|------|---------------|
| **Orchestrator** | `agent/orchestrator.py` | Main workflow: plan → render → evaluate → revise → mint |
| **Planner** | `agent/planner.py` | GLM-5.1 API client, prompt engineering, JSON parsing |
| **Evaluator** | `agent/evaluator.py` | Multimodal vision evaluation (5 dimensions) |
| **Server** | `agent/server.py` | FastAPI with SSE streaming |
| **Schema** | `agent/schema.py` | Data models (SceneSpec, BoothSpec, LightSpec, RoomSpec) |
| **Execution** | `agent/execution.py` | Execution trace recording (StepRecord, ValidationRound) |

### 2. Godot Layer (GDScript)

| Component | File | Responsibility |
|-----------|------|---------------|
| **SceneBuilder** | `godot/scripts/scene_builder.gd` | Main orchestrator, file watch, scene rebuild |
| **RoomBuilder** | `godot/scripts/room_builder.gd` | Room geometry (walls, floor, ceiling) |
| **BoothBuilder** | `godot/scripts/booth_builder.gd` | NFT booth pedestals and frames |
| **ArtGenerator** | `godot/scripts/art_generator.gd` | 9 procedural art algorithms + post-processing |
| **LightingBuilder** | `godot/scripts/lighting_builder.gd` | Lights, environment, volumetric fog |
| **CameraController** | `godot/scripts/camera_controller.gd` | FPS-style camera with WASD + mouse look |

### 3. Web3 Layer (Python + Solidity)

| Component | File | Responsibility |
|-----------|------|---------------|
| **Minter** | `agent/web3/minter.py` | Full minting orchestration |
| **Contract** | `agent/web3/contract.py` | Deploy, batchMint, setTokenURI |
| **Metadata** | `agent/web3/metadata.py` | ERC-721 metadata + base64 image encoding |
| **Config** | `agent/web3/config.py` | Chain RPC, private key, ABI/bytecode |
| **WorldBuilderNFT** | `contracts/src/WorldBuilderNFT.sol` | ERC-721 with batchMint |

## Data Flow

### Scene Spec JSON Schema
```json
{
  "theme_name": "string",
  "global_color_palette": ["#RRGGBB"],
  "rooms": [{"id": "main_hall", "dimensions": [w, h, d], "wall_color": "#RRGGBB"}],
  "booths": [{
    "id": "booth_N",
    "position": [x, y, z],
    "orientation": 0.0,
    "nft": {
      "name": "string",
      "collection": "string",
      "art_style": "gradient_noise|voronoi|geometric|plasma|mandala|pixel_art|fractal|nebula|flow_field",
      "art_seed": 42,
      "art_colors": ["#RRGGBB"],
      "token_id": "string"
    }
  }],
  "lights": [{"position": [x, y, z], "color": "#RRGGBB", "intensity": 500.0}]
}
```

### IPC Protocol (Agent ↔ Godot)
1. Agent writes `godot/shared/scene_spec.json`
2. Godot watches file mtime changes (1s interval)
3. Godot rebuilds entire scene from spec
4. Godot captures screenshot to `godot/shared/render.png`
5. Agent polls render.png mtime changes

### SSE Event Protocol
```json
{"type": "step_started", "data": {"step_id": "1", "tool": "plan_scene", "description": "..."}}
{"type": "step_completed", "data": {"step_id": "1", "tool": "plan_scene", "duration_ms": 2340}}
{"type": "render_ready", "data": {"image_url": "/agent/screenshot", "round": 1}}
{"type": "evaluation_result", "data": {"round": 1, "score": 7, "passed": false}}
{"type": "repair_started", "data": {"round": 1, "strategy": "revise_spec", "model": "glm-5.1"}}
{"type": "mint_completed", "data": {"contract_address": "0x...", "mints": [...]}}
{"type": "generation_complete", "data": {"trace": {...}, "scene_spec": {...}}}
```

## GLM-5.1 Integration Points

| Point | API Call | Purpose |
|-------|----------|---------|
| Scene Generation | `/v1/messages` (text) | NL → scene_spec.json |
| Visual Evaluation | `/v1/messages` (multimodal) | Screenshot + spec → 5-dimension score |
| Spec Revision | `/v1/messages` (text) | Eval feedback → revised spec |
| Prompt Enhancement | Rule-based | Keyword detection → style guidance |

## Security Boundaries

- **GLM API Key**: Environment variable only, never logged or committed
- **Web3 Private Key**: Anvil default key only (local chain), never used on mainnet
- **File IPC**: Only scene_spec.json and render.png, no arbitrary file access
- **Non-blocking Web3**: NFT minting failure does not stop the 3D pipeline
- **DNS Patch**: Hardcoded IP fallback for DNS resolution failures
