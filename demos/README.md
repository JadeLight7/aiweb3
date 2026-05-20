# Demos — Task 3 Interactive Artifacts

按 Agent 工具隔离产物，方便横向对比：

```
demos/
├── README.md
├── claude-code/    # Claude Code 生成
└── codex/          # Codex 生成
```

## Artifacts

- Claude Code: `demos/claude-code/tx-lifecycle.html` (543 lines)
- Codex: `demos/codex/blockchain-lifecycle.html` (1002 lines)

## Comparison

### 1. Code Quality

| 方面 | Claude Code | Codex |
|------|-------------|-------|
| 代码量 | 543 行 | 1002 行 |
| 主题 | 暗色 (紫+蓝) | 浅色 (青绿+灰) |
| CSS | 简洁，单一断点 | 多断点响应式 (880px/560px)，hover/transition 完善 |
| JS 架构 | 直接 DOM 操作，数据内联 | 数据与渲染分离，renderX() 函数化 |
| 无障碍 | 无 aria / 键盘支持 | aria-label、focus-visible、Enter/Space 翻卡 |
| 交互组件 | Stepper + 翻卡 + Mempool 模拟器 + Quiz | Stepper + 翻卡 + 完整交易模拟器(含失败动画) + CLI 模拟器 + Quiz + 区块可视化图 |
| **结论** | 精简直接，功能聚焦 | 工程化更好，组件更丰富，可访问性胜出 |

### 2. Context Retention

| 方面 | Claude Code | Codex |
|------|-------------|-------|
| 与已有笔记关联 | 紧密 — 5 步直接对应 day3.md 的 5 条知识点 | 松 — 扩展为 8 步通用教程 |
| 用户画像感知 | 知悉用户 Web3 熟练，避开基础概念直奔交叉点 | 面向通用区块链入门读者 |
| 对话延续 | 同一会话，知道前置讨论内容 | 独立生成，无前后文 |
| **结论** | 上下文保持更好，产物锚定用户学习进度 | 更像是独立教程，可复用但缺乏个性化 |

### 3. Content Organization

| 方面 | Claude Code | Codex |
|------|-------------|-------|
| 生命周期步骤 | 5 步水平 Stepper | 8 步垂直侧栏 Stepper |
| 概念卡片 | 6 张 (Nonce/RPC/ECDSA/Gas/Mempool/Finality) | 8 张 (Hash/Nonce/Gas/Mempool/Receipt/Finality/State/Indexer) |
| 独有组件 | Mempool 优先级模拟器、Agent Collaboration Notes | Hero 区块图、CLI 模拟器、交易失败状态分支动画 |
| Agent 分工记录 | ✅ 页面内嵌 | ❌ 无 |
| **结论** | 更聚焦，透明标注 Agent 贡献 | 覆盖更广，模块更丰富 |

### 4. Tool Integration

| 方面 | Claude Code | Codex |
|------|-------------|-------|
| 文件创建 | Write 工具直接写入仓库 | 用户手动放入 |
| Git 管理 | add + commit + push 一体化 | 无 |
| 目录隔离 | 主动创建 claude-code/codex/ 子目录 + README | 无 |
| 浏览器打开 | `open` 命令一键启动 | 无 |
| **结论** | 工具调用完胜 — 全流程自动化 | 纯代码生成，无工具链集成 |

### 5. Long-term Learning Record

| 方面 | Claude Code | Codex |
|------|-------------|-------|
| 可追溯性 | Git 历史完整，每次改动有 commit message | 依赖用户手动管理 |
| 模板复用 | templates/ 目录提供 daily-note / task-note 模板 | 无 |
| 反馈闭环 | handbook-feedback/ 已初始化 | 无 |
| **结论** | 适合长期学习记录维护 | 单次生成质量高，但缺少持续学习基础设施 |

---

## Summary

| 维度 | 优势方 |
|------|--------|
| 代码工程化 & 组件丰富度 | Codex |
| 对话上下文 & 个性化 | Claude Code |
| 工具链集成 (Git/文件/浏览器) | Claude Code |
| 内容覆盖面 | Codex |
| 长期学习基础设施 | Claude Code |

**最佳实践：** 两者互补 — Claude Code 负责学习计划、打卡、Git 管理和反馈闭环；Codex 适合生成丰富的前端交互 demo。可让其中一方生成初版，另一方做 code review 和补充。

---

*Task 3 | AI × Web3 School | Cohort 0*
