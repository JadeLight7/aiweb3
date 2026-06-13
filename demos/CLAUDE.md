# AI-Powered 3D World Builder — Hackathon Project

> GLM-5.1 驱动的自主 3D 世界构建系统 — 从自然语言到可交互 3D 场景 + 链上 NFT 完整闭环

## Technology Stack

- **Engine**: Godot 4.6 (Forward+ renderer)
- **Language**: GDScript (Godot) + Python 3.11+ (Agent)
- **AI Model**: GLM-5.1 via Anthropic-compatible API
- **Blockchain**: Solidity (Foundry) + web3.py, Anvil local chain / Sepolia
- **Framework**: Claude Code Game Studios (CCGS) v1.0.0 — 49 agents, 73 skills

## Project Structure

```
demos/
├── CLAUDE.md                    # This file — master configuration
├── README.md                    # Hackathon submission document
├── .claude/                     # Claude Code settings
├── agent/                       # Python AI agent (GLM-5.1 orchestration)
│   ├── main.py                  # CLI entry point
│   ├── orchestrator.py          # WorldBuilderAgent — main orchestrator
│   ├── planner.py               # GLM-5.1 scene spec generation
│   ├── evaluator.py             # GLM-5.1 vision-based render evaluation
│   ├── reviser.py               # Spec revision based on visual feedback
│   ├── schema.py                # Data models (SceneSpec, BoothSpec, etc.)
│   ├── execution.py             # Execution trace data models
│   ├── server.py                # FastAPI server (SSE streaming)
│   ├── web_ui.html              # Real-time web dashboard
│   └── web3/                    # Web3/NFT minting module
│       ├── config.py            # Chain configuration (Anvil/Sepolia)
│       ├── contract.py          # NFT contract interaction
│       ├── minter.py            # Full minting orchestration
│       └── metadata.py          # ERC-721 metadata generation
├── godot/                       # Godot 4.6 scene builder
│   ├── project.godot            # Godot project config
│   ├── Builder.tscn             # Main scene
│   ├── scripts/                 # Modular GDScript components
│   │   ├── scene_builder.gd     # Main orchestrator
│   │   ├── room_builder.gd      # Room geometry construction
│   │   ├── booth_builder.gd     # NFT booth construction
│   │   ├── art_generator.gd     # Procedural art (9 algorithms)
│   │   ├── lighting_builder.gd  # Lighting & atmosphere
│   │   ├── camera_controller.gd # FPS camera controls
│   │   └── decoration_builder.gd # Decorative elements
│   ├── screenshot.gd            # Render capture utility
│   └── shared/                  # IPC directory (agent ↔ Godot)
│       ├── scene_spec.json      # Scene specification
│       └── render.png           # Rendered screenshot
├── contracts/                   # Solidity smart contracts (Foundry)
│   ├── src/WorldBuilderNFT.sol  # ERC-721 NFT contract
│   └── foundry.toml             # Foundry config
├── design/                      # CCGS design documents
│   └── gdd/
│       └── 3d-world-builder.md  # Game design document
├── docs/                        # Technical documentation
│   └── architecture/
│       └── system-architecture.md
└── tests/                       # Test suites
```

## Engine Version Reference

- **Engine**: Godot 4.6 (January 2026)
- **LLM Knowledge Cutoff**: May 2025
- **Post-Cutoff Changes**: Jolt default physics, glow rework, D3D12 default on Windows

## Technical Preferences

### Engine & Language
- **Engine**: Godot 4.6
- **Language**: GDScript (Godot) + Python 3.11+ (Agent)
- **Rendering**: Forward+ with SDFGI, volumetric fog, SSR, SSAO
- **Physics**: Jolt (Godot 4.6 default)

### Naming Conventions
- **GDScript**: snake_case for functions/variables, PascalCase for classes
- **Python**: snake_case for functions/variables, PascalCase for classes
- **Constants**: UPPER_SNAKE_CASE
- **Files**: snake_case.gd / snake_case.py
- **Scenes**: PascalCase.tscn

### Performance Budgets
- **Target Framerate**: 60 FPS (editor), 30 FPS (headless render)
- **Draw Calls**: < 200 (indoor scene)
- **Art Texture Size**: 256×320 (procedural)

### Web3 Configuration
- **Local Chain**: Anvil (chain ID 31337)
- **Testnet**: Sepolia (optional)
- **Contract**: ERC-721 (WorldBuilderNFT)
- **Gas**: Auto-estimated, max 1M gas per batch mint

## CCGS Skills Used

This project leverages Claude Code Game Studios (CCGS) framework skills:

| Skill | Application |
|-------|-------------|
| `scene-organization` | Modular GDScript architecture (6 component scripts) |
| `procedural-generation` | 9 procedural art algorithms with post-processing |
| `gdscript-patterns` | Type-safe constants, material caching, signal patterns |
| `godot-optimization` | Material caching, draw call reduction, deferred calls |
| `state-machine` | Agent state management (plan → render → evaluate → revise) |
| `create-architecture` | System architecture documentation |
| `design-review` | 5-dimension visual evaluation framework |
| `qa-plan` | Execution trace recording and validation rounds |

## Coordination Rules

1. **Agent ↔ Godot**: Communication via file-based IPC (scene_spec.json, render.png)
2. **Agent ↔ GLM-5.1**: Anthropic-compatible API at open.bigmodel.cn
3. **Agent ↔ Web3**: web3.py + eth_account for contract deployment and minting
4. **SSE Streaming**: Real-time event stream to web dashboard

## Coding Standards

- All GDScript functions include type hints and doc comments
- All Python classes include docstrings with usage examples
- Scene spec schema is the single source of truth for 3D layout
- Web3 operations are non-blocking (failure doesn't stop the pipeline)
- Error handling: graceful degradation, never crash on API/network failure

## Context Management

- Agent execution trace is persisted to `ExecutionTrace` dataclass
- SSE events provide real-time progress to frontend
- Render screenshots are saved for vision evaluation
- Web3 transaction hashes and contract addresses are recorded in trace
