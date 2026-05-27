# Week 2 Day 3 — Module B 深挖 + 交付物汇总

> 2026-05-28

## 一、为什么放弃 DeFi Agent，转向 x402

V2（DeFi Intent Agent）有两个致命问题：

| 问题 | 详情 |
|------|------|
| **测试网不可验证** | Phase 1 核心功能是"推荐 DeFi 策略"。但 Aave APY、Uniswap 池子深度、Lido 脱锚状态——这些在 Sepolia 上根本不存在真实数据。Agent 推荐得对不对，测不了 |
| **成功标准模糊** | 用户说"不想亏本金"，Agent 推荐了 Aave。这算对还是错？如何量化验证？人工评审太主观 |

**x402 完全不同**：

| 对比 | DeFi Agent（V2） | x402 + CAW（V3） |
|------|------|------|
| 测试网可验证？ | 否 | **是——整个链路在 Sepolia 跑通** |
| 成功标准明确？ | 否 | **是——Agent 付款成功 → 拿到结果** |
| 可演示？ | Phase 1 像 chatbot | **端到端：请求 → 402 → 付款 → 拿到结果** |
| Hackathon 匹配？ | DeFi 赛道竞争激烈 | Agentic Commerce 赛道直接命中 |

---

## 二、x402 是什么

利用 HTTP 402 Payment Required 实现链上支付：

```
传统 API 付费：                          x402 模式：

用户 → API Key → 月结账单                 Agent → GET /api/data
      (注册、绑定信用卡)                         ← HTTP 402 + 付款信息
                                                  ↓
                                            Agent 解析付款需求
                                                  ↓
                                            CAW 执行链上支付
                                                  ↓
                                            Agent → GET /api/data (带 tx proof)
                                                  ← HTTP 200 + 结果
```

**关键设计**：不需要注册/API Key/信用卡，按次付费，付款信息在 HTTP 402 body 中，支付验证在服务端查链确认。x402 把"身份认证+计费"换成了"链上支付即认证"——不需要知道你是谁，付了钱就行。

---

## 三、项目完整流程

服务方（Alice）部署了付费 AI 摘要服务。Agent（代表 Bob）自动为 Bob 付款获取结果：

```
Bob                      Agent                      Alice 服务
│                         │                           │
│ "总结这篇长文"           │                           │
├─────────────────────────►│                           │
│                         │  GET /api/summarize       │
│                         ├───────────────────────────►│
│                         │  ← HTTP 402               │
│                         │  {amount, token, chain,    │
│                         │   recipient, deadline}     │
│                         │                           │
│                         │  AI 判断:                  │
│                         │  - 金额 < Pact 限额 ✓       │
│                         │  - token/chain 在白名单 ✓   │
│                         │  - 收款方可信 ✓             │
│                         │  → 自动支付                 │
│                         │                           │
│                         │  CAW 链上转账 tx:0xabc...  │ (链上)
│                         │  GET + tx_hash            │
│                         ├───────────────────────────►│
│                         │  服务端验证 tx → 返回摘要    │
│                         │◄───────────────────────────┤
│                         │                           │
│  "这是摘要：..."         │                           │
│◄─────────────────────────┤                           │
│                         │                           │
│  审计: 服务/金额/tx/状态  │                           │
└─────────────────────────┴───────────────────────────┘
```

---

## 四、AI 与 Web3 各承担什么

### AI 不可替代

| AI 能力 | 做什么 | 为什么脚本做不到 |
|----------|--------|----------------|
| **402 响应解析** | 解析 body 中的支付参数，不同服务方可能用不同字段名 | x402 body 格式未强标准化，AI 需要语义理解而非固定字段解析 |
| **预算决策** | 判断金额是否在 Pact 内，结合今天已花费+服务方历史+剩余预算 | 不是简单比大小，需要多维度上下文判断 |
| **异常判断** | 金额突涨（typo/攻击？）、gas 异常高、deadline 已过 | "异常"的定义是动态的——昨天正常的价格今天可能就不正常 |
| **多服务选择** | 多个同类服务比价+信誉+质量 | 服务发现和比较是 Agent 核心能力，不是固定路由表 |

### Web3 不可替代

| Web3 机制 | 提供什么 | 为什么不用传统支付 |
|-----------|---------|-----------------|
| **无许可支付** | 不需要注册 Stripe/银行卡/KYC，有个地址就能收款 | 个体开发者可能根本没有 Stripe 账户 |
| **链上收据** | tx hash 不可篡改，任何人都能独立验证 | 传统支付记录可被平台篡改 |
| **Pact 硬约束** | "最多花 0.05 ETH/次"是链上硬限制，不是 prompt 建议 | Agent 被 prompt injection 也无法绕过 |
| **结算即终结** | 链上确认即到账，不等 T+1 清算，不处理 chargeback | chargeback 对服务方是重大风险 |

---

## 五、自动化边界

```
🟢 自动执行（Pact 范围内）:
┌──────────────────────────────────┐
│ - 金额 ≤ per_tx_limit            │
│ - token/chain 在白名单            │
│ - gas < 50 gwei                  │
│ - 收款方已交互过（非首次）        │
│ - 单日累计 < daily_limit         │
└──────────────────────────────────┘

🔴 暂停+人工确认:
┌──────────────────────────────────┐
│ - 金额 > Pact 限额                │
│ - 非白名单 token/chain            │
│ - 收款方首次交互                  │
│ - 单日累计即将超限                │
│ - gas > 100 gwei                 │
│ - 402 deadline 已过期             │
│ - 连续 3 次付费后无有效结果        │
└──────────────────────────────────┘
```

### Pact 配置示例

```json
{
  "pact": {
    "task": "AI text summarization agent",
    "budget": { "per_tx_limit": "0.05 ETH", "daily_limit": "0.2 ETH", "weekly_limit": "1 ETH" },
    "scope": {
      "chains": ["sepolia-testnet"],
      "allowed_tokens": ["ETH", "USDC"],
      "allowed_recipients": ["0x...(ai-summarizer)", "0x...(data-analyzer)"],
      "banned_actions": ["contract_deploy", "governance_vote"]
    },
    "time_window": { "valid_from": "2026-05-28T00:00:00Z", "valid_until": "2026-06-04T00:00:00Z", "auto_expire": true },
    "thresholds": { "require_confirmation_above": "0.05 ETH", "max_gas_gwei": 50, "first_interaction_requires_confirmation": true },
    "recovery": { "pause_on_anomaly": true, "revocable_by_owner": true }
  }
}
```

---

## 六、反例：不需要 x402 的场景

| 场景 | 为什么不需要 x402 | 更好的方案 |
|------|------------------|-----------|
| 内部系统服务间调用 | 同一信任域 | API Key 或 mTLS |
| 大额订阅制 | 按月/年付费 | 传统 crypto 转账 |
| 免费 API | 不需要支付 | — |
| 需要 KYC/合规 | x402 无许可=无法 KYC | 合规稳定币+白名单 |
| 实时流式计费 | x402 按单次 HTTP 请求计费 | WebSocket + 定时结算 |

**x402 最适合**：Agent 按次小额支付——AI 推理、专有数据查询、计算资源。几分到几美元，不需注册/KYC，需链上收据。

---

## 七、关键风险与缓解

| 风险 | 缓解 |
|------|------|
| x402 生态不成熟 | 锁定具体 x402 库，参照官方示例 |
| 付款后服务端不响应 | 小额先测；未来可用 escrow（ERC-8183） |
| 金额误判（0.01 vs 1e16 wei） | 解析后显式验证金额范围；超 Pact 自动暂停 |
| Replay 攻击 | 服务端验证 tx 的 recipient/amount 与本次匹配 + nonce |
| CAW 依赖（托管风险） | 测试网可接受；未来迁移 Safe + ERC-4337 |

---

## 八、x402 vs MPP vs ERC-8004

| | x402 | MPP | ERC-8004 |
|------|------|------|------|
| **定位** | HTTP 层 paywall | Agent 支付通用框架 | Agent trust/job/evaluator |
| **层级** | 应用层 | 协议层（支付+escrow） | 协议层（身份+任务） |
| **当前成熟度** | 有可用工具 | Stripe 推动，早期 | EIP 草案 |
| **和本项目关系** | **直接使用** | 参考 escrow 设计 | Agent profile 可参考 |

---

## 九、最小验证计划

### Phase 1（Week 3）：最小闭环
1. 部署 x402 Express Server：GET `/api/hello` → 402
2. Agent 脚本：收到 402 → 解析 → Pact 检查 → CAW 支付 → 带 tx_hash 重请求 → 打印结果
3. 验证标准：3 次内拿到结果 + tx 参数与 402 一致

### Phase 2（Week 4）：异常场景
超限额/非白名单/服务无响应/gas 异常 → 对应暂停或重试

### Phase 3（Week 5）：多服务比价
2 个同功能 x402 服务 → Agent 选便宜的

---

## 十、方向 Backlog

| 方向 | 不选原因 | 未来切入点 |
|------|---------|-----------|
| DeFi Execution (③) | 测试网无法验证推荐质量；标准主观 | 若支付项目跑通，可加 escrow |
| Wallet/Permission (④) | 偏基础设施，单独 demo 效果差 | Pact 已融入执行层 |
| Governance (⑥) | 当前不涉及治理 | 多用户金库管理时再进 |
| Identity/Reputation (②) | 需要先有运行数据 | 多用户时考虑 MCP/A2A/ERC-8004 |

---

## 十一、各模块覆盖记录

| 模块 | 覆盖方式 | 深度 |
|------|---------|------|
| A — 问题空间 | 6 方向地图 + 方向选择 + 5 维度判断矩阵 | **深** |
| B — Payment/Commerce | **主方向**：x402 全流程 + 反例 + 协议对比 | **深** |
| C — Identity | Agent Profile 卡片（proposal） | 浅 |
| D — Wallet/Permission | Pact 配置 + 自动化边界 + 执行分级 | 中 |
| E — Agent DeFi | 不覆盖（backlog） | — |
| F — Privacy/Security | 风险+缓解+审计日志+反例 | 中 |
| G — Governance | backlog 简述 | 浅 |

---

## 十二、提案演变：V1 → V2 → V3

| | V1 监控告警 | V2 DeFi Intent | V3 x402 Payment |
|------|------|------|------|
| AI 不可替代？ | 否 | 是 | **是** |
| Web3 不可替代？ | 否 | 是 | **是** |
| 测试网可验证？ | 否 | 否 | **是** |
| 成功标准明确？ | 是但不值钱 | 否 | **是** |
| Hackathon 匹配？ | 弱 | 中 | **强** |

---

## 十三、参考资料清单

| # | 资料 | 判断什么 |
|---|------|---------|
| 1 | x402 Docs | 协议规范、body 格式、示例 |
| 2 | Cobo CAW Quickstart | CAW API 接入 |
| 3 | MPP (Stripe) | Agent Commerce 完整框架参考 |
| 4 | ERC-8004 | Agent trust/job 未来扩展 |
| 5 | viem | 链上 tx 验证 |
| 6 | Sepolia Faucet | 测试 ETH |
| 7 | ERC-4337 | 非托管方案 |
| 8 | OpenZeppelin | 合约开发需求 |

---

## 十四、Notion 自检

| # | 框架问题 | 答案 |
|---|---------|------|
| 1 | 没有 AI 是否成立？ | 否——脚本能 hardcode 一种 402，但多格式/异常/多服务选择需要 AI |
| 2 | 没有 Web3 是否成立？ | 否——传统支付需注册/KYC/chargeback，Agent 无法自主 |
| 3 | 谁发起/执行/付款/验收/失败？ | 用户→Agent 发起 / CAW 执行 / 链上验证 / Agent 验收 / Pact 内可控 |
| 4 | 哪些自动哪些确认？ | 预算内白名单自动；超额/新地址/异常暂停 |
| 5 | 结果如何验证？ | tx hash 在 etherscan 可查，成本=一次 RPC 查询 |
| 6 | 是应用/工具/协议/安全/治理？ | 应用层体验 + 安全机制（Pact） |
| 7 | 如果失败最可能原因？ | x402 生态不成熟 |

---
