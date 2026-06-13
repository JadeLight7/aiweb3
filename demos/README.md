# 🏗️ AI-Powered 3D World Builder

> **GLM-5.1 驱动的自主 3D 世界构建系统** — 从自然语言到可交互 3D 场景 + 链上 NFT 完整闭环

[![Z.AI Hackathon](https://img.shields.io/badge/Z.AI-Hackathon-blue)]()
[![GLM-5.1](https://img.shields.io/badge/Model-GLM--5.1-green)]()
[![Godot 4.6](https://img.shields.io/badge/Engine-Godot_4.6-478cbf)]()
[![Solidity](https://img.shields.io/badge/Web3-ERC721_NFT-363636)]()

## 📌 项目概述

用户只需输入一句话（如"赛博朋克风格的 NFT 展厅"），GLM-5.1 Agent 自主完成：

```
用户自然语言 → GLM-5.1 场景规划 → Godot 3D 渲染 → GLM-5.1 视觉评估
  → [不达标] 自动修复 → 重新渲染 → ... → [达标] → 链上 NFT 铸造
```

**全程 SSE 实时推送**，评委可在 Web Dashboard 上观看 Agent 的完整工作过程。

> 📄 **完整黑客松提交文档**: [HACKATHON_SUBMISSION.md](./HACKATHON_SUBMISSION.md)

## 🤖 GLM-5.1 核心调用位置

| 调用点 | 文件 | 类型 | 功能 |
|--------|------|------|------|
| 场景规划 | `agent/planner.py` | Text → JSON | NL → scene_spec.json |
| 视觉评估 | `agent/evaluator.py` | Multimodal | 截图 + spec → 5维度评分 |
| 自我修复 | `agent/orchestrator.py` | Text → JSON | 评估反馈 → 修改 spec |

**GLM-5.1 使用关键性：** Agent 的核心长程任务全部由 GLM-5.1 驱动，体现自主规划、持续执行和自我纠错能力。

## 🏗️ 架构

```
Web Dashboard (SSE) ←── FastAPI Agent (Python)
                              │
                 ┌────────────┼────────────┐
                 │            │            │
           GLM-5.1 API    File IPC    Web3 (web3.py)
         (plan/eval/fix)  (JSON+PNG)  (deploy+mint)
                 │            │            │
                 │      Godot 4.6     Anvil Chain
                 │      (3D Render)   (ERC-721)
```

## 🚀 快速开始

```bash
# 1. 安装依赖
pip install fastapi uvicorn web3 eth-account urllib3

# 2. 设置 API Key
export GLM_API_KEY="your_key_here"

# 3. 启动 Agent 服务器
cd agent && python server.py
# → http://localhost:8001

# 4. 触发生成
curl -X POST http://localhost:8001/agent/generate \
  -H "Content-Type: application/json" \
  -d '{"request": "赛博朋克风格的NFT展厅，6个展位"}'
```

**可选**: 启动 Godot 4.6 获得实时 3D 渲染，启动 Anvil 获得链上 NFT 铸造。

## 📁 项目结构

```
demos/
├── agent/                # Python AI Agent (GLM-5.1 编排)
│   ├── orchestrator.py   # 主编排器: plan → render → eval → fix → mint
│   ├── planner.py        # GLM-5.1 场景规划
│   ├── evaluator.py      # GLM-5.1 视觉评估
│   ├── server.py         # FastAPI + SSE
│   └── web3/             # NFT 合约部署与铸造
├── godot/                # Godot 4.6 3D 场景构建
│   ├── SceneBuilder.gd   # 主构建器 (2763 行, 9 种艺术风格)
│   ├── scripts/          # CCGS 模块化组件
│   │   ├── art_generator.gd     # 程序化艺术生成器
│   │   └── material_factory.gd  # 材质工厂 + 缓存
│   └── shared/           # Agent ↔ Godot IPC
├── contracts/            # Solidity (Foundry)
│   └── src/WorldBuilderNFT.sol  # ERC-721 NFT 合约
├── design/gdd/           # 游戏设计文档
├── docs/architecture/    # 系统架构文档
├── CLAUDE.md             # CCGS 项目配置
└── HACKATHON_SUBMISSION.md  # 完整提交文档
```

## 🧩 CCGS 集成

本项目使用 [Claude Code Game Studios](https://github.com/Donchitos/Claude-Code-Game-Studios) (CCGS v1.0.0) 框架优化开发：

- `scene-organization` → 模块化 GDScript 组件 (`godot/scripts/`)
- `procedural-generation` → 9 种程序化艺术算法 (`art_generator.gd`)
- `godot-optimization` → Material 缓存系统 (`material_factory.gd`)
- `state-machine` → Agent 状态管理 (plan → eval → fix)
- `create-architecture` → 系统架构文档
- `design-review` → 5 维度视觉评估框架

## 🛡️ 安全边界

| 边界 | 说明 |
|------|------|
| API Key | 仅环境变量，不写入代码 |
| 私钥 | 仅 Anvil 测试私钥，**绝不用于主网** |
| Web3 | 仅 Anvil (31337) + Sepolia |
| 失败处理 | NFT 铸造非阻塞，不影响 3D 流程 |
| 人工介入 | 3 轮修复未通过 → Agent 终止 |

详见 [HACKATHON_SUBMISSION.md - 安全边界说明](./HACKATHON_SUBMISSION.md#-安全边界说明)

## 📊 Demo 效果

- ⏱️ 端到端延迟: 15-45s (取决于 Godot 是否运行 + 修复轮次)
- 🎨 9 种程序化 NFT 艺术风格
- 🔄 GLM-5.1 自主评估 + 修复 (最多 3 轮)
- ⛓️ 完整链上 NFT 铸造

## 📄 License

MIT
