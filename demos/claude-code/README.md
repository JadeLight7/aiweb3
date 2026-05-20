# Claude Code — Transaction Lifecycle Demo

**File:** `demos/claude-code/tx-lifecycle.html`

## Overview

交互式 HTML 页面，展示区块链交易完整生命周期：Sign → Broadcast (RPC) → Mempool → Gas & Mine → Confirm。

543 行，自包含，浏览器直接打开即可使用。

## Components

| 组件 | 说明 |
|------|------|
| 5-Step Stepper | 点击切换步骤，每步含代码示例和 Key Insight |
| 6 Concept Cards | 翻转卡片：Nonce / RPC / ECDSA / Gas / Mempool / Finality |
| Mempool Simulator | 按 Gas Price 排序模拟交易优先级 |
| 4-Question Quiz | 即时判分 |

## Agent Collaboration

- **Agent 生成**：全部 HMTL/CSS/JS
- **人工修正**：Gas Limit 描述、EIP-1559 补充、配色调整
- **已知问题**：卡片翻转用 display 切换（非 CSS 3D），下一步可接入真实 RPC 查询

## Usage

```bash
open demos/claude-code/tx-lifecycle.html
```
