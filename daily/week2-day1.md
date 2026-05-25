# Week 2 Day 1 — AI × Web3 问题地图与方向选择

> 2026-05-26 | 更新 2026-05-28：方向从 DeFi Execution 切换到 Payment/Commerce (x402)

## 一、AI × Web3 问题地图

```
                    AI 能力维度
                    │
        ┌─ 理解/生成 ──┼── 规划/推理 ──┐
        │              │              │
        │    ┌─────────┼─────────┐    │
        │    │    ⑥ Governance    │    │
        │    │   AI辅助提案总结、  │    │
        │    │   贡献追踪、透明执行│    │
        │    └─────────┼─────────┘    │
        │              │              │
        │    ┌─────────┼─────────┐    │
        │    │   ⑤ Privacy/Security│   │
        │    │  prompt injection, │    │
        │    │  tool abuse, 主权   │    │
        │    └─────────┼─────────┘    │
        │              │              │
  ──────┼──────────────┼──────────────┼────── Web3 机制维度
        │              │              │
        │    ┌─────────┼─────────┐    │
        │    │  ④ Wallet/Permission│   │
        │    │  Session Key, Guard,│   │
        │    │  Policy, 账户抽象   │    │
        │    └─────────┼─────────┘    │
        │              │              │
        │    ┌─────────┼─────────┐    │
        │    │ ① Payment/Commerce │ ← 主方向
        │    │ x402, MPP, Escrow, │    │
        │    │ 托管, 争议处理      │    │
        │    └─────────┼─────────┘    │
        │              │              │
        │    ┌─────────┼─────────┐    │
        │    │ ③ Agent DeFi Exec  │    │
        │    │ swap/approve/deposit│   │
        │    │ 预算/滑点/MEV/清算  │    │
        │    └─────────┼─────────┘    │
        │              │              │
        │    ┌─────────┼─────────┐    │
        │    │ ② Identity/Capability│  │
        │    │ MCP, A2A, ERC-8004, │   │
        │    │ Agent Profile, Reputation│
        │    └─────────┴─────────┘    │
        │                             │
    工具调用/自动化 ────────┼────── 支付/结算/身份/权限/可验证记录
```

## 二、6 个方向速览

### ① Payment / Commerce / Settlement ← 主方向
- **AI 做什么**：Agent 识别支付需求、判断是否在预算范围内、自动完成支付、验证交付
- **Web3 提供什么**：链上结算（无需银行/信用卡）、交易收据可验证、Pact 权限硬约束
- **为什么不是纯 AI**：AI 能判断"这个 API 值得付 0.01 ETH"，但无法自己完成价值转移——需要链上支付层
- **为什么不是纯 Web3**：传统 crypto 支付需要人工点钱包确认每一笔，Agent 的价值在于"自动判断+预算内自动支付+超额/异常暂停"
- **典型入口**：x402 paywall、MPP、Cobo CAW + Pact

### ② Identity / Reputation / Capability / Interoperability
- **AI 做什么**：描述 Agent 能力、理解其他 Agent 的 profile、匹配合适的服务方
- **Web3 提供什么**：DID、链上信誉、可验证凭证、能力注册表
- **为什么不是纯 AI**：Agent 身份和能力声明需要不可篡改的注册层
- **为什么不是纯 Web3**：单纯的身份注册不需要 AI，但 Agent 的动态能力发现和语义匹配需要
- **典型入口**：MCP、A2A、ERC-8004、EAS、ENS

### ③ Agent DeFi Execution
- **AI 做什么**：理解用户意图、规划执行路径、检查风险、决定执行策略
- **Web3 提供什么**：DEX/借贷协议、链上执行、交易记录、可审计性
- **为什么不是纯 AI**：AI 能分析市场但无法自动执行链上交易
- **为什么不是纯 Web3**：传统 DeFi 用户手动操作，但 Agent 可以 24/7 监控+自动执行+风险检查
- **典型入口**：Uniswap V3、Aave、LI.FI、Cobo CAW

### ④ Wallet / Permission / Safe Execution
- **AI 做什么**：理解用户意图、翻译为链上操作、判断风险等级
- **Web3 提供什么**：账户抽象、Session Key、Guard、Policy、多签
- **为什么不是纯 AI**：AI 可以作为决策辅助，但权限执行需要链上约束
- **为什么不是纯 Web3**：传统钱包不需要 AI，但 Agent wallet 需要智能的权限判断和风险分析
- **典型入口**：Safe、ERC-4337、ERC-7702、Cobo CAW Pact

### ⑤ Privacy / Security / Sovereignty
- **AI 做什么**：Agent 的安全策略执行、异常检测、威胁分析
- **Web3 提供什么**：TEE、链上审计日志、抗审查、自我主权
- **为什么不是纯 AI**：AI 模型本身是攻击面，需要环境级隔离
- **为什么不是纯 Web3**：传统安全审计不需要 AI，但 Agent 执行的实时威胁检测和动态策略需要 AI
- **典型入口**：prompt injection 防护、MCP tool abuse 检测、Safe Guard

### ⑥ Governance / Coordination / Public Goods
- **AI 做什么**：提案总结、讨论脉络、会议转行动项、贡献记录
- **Web3 提供什么**：公开记录、可验证贡献、透明预算、链上投票
- **为什么不是纯 AI**：AI 可以整理信息但不能替代社区做价值判断
- **为什么不是纯 Web3**：DAO 工具已有 Snapshot/Governor，但信息过载和效率问题需要 AI
- **典型入口**：Snapshot、OpenZeppelin Governor、Gitcoin

---

## 三、方向选择

### 主方向：① Payment / Commerce — x402 Paywall + CAW Agent

**为什么选这个**：
1. **可测试性强**：在 Sepolia 测试网上可以跑完整链路——部署 paywall 服务 + Agent 用测试 ETH 付款 + 拿到结果。不需要依赖主网真实数据
2. **协议清晰**：x402 规范明确（HTTP 402 + 链上支付验证），不涉及模糊的"意图理解"或"策略推荐质量"评估
3. **Cobo CAW 原生匹配**：Notion 页面专门有 "x402 Paywall + CAW Agent 自主支付闭环" 任务，CAW 的 Pact 机制天然适合 Agent 预算控制
4. **Hackathon 友好**：端到端可演示（上传文件 → Agent 付款 → 拿到分析结果），评委和观众一眼能看懂
5. **实操性强**：每个组件（x402 server、CAW agent、链上支付）都是可写代码的，不是纯研究输出

**为什么不是纯 AI 问题**：传统 API 付费是信用卡/API Key 模式，Agent 需要理解 HTTP 402 响应、解析链上支付参数、判断是否在预算范围内——这些是 AI 的"理解+决策"能力，不是简单脚本。

**为什么不是纯 Web3 问题**：纯链上支付（如直接打 ETH）不需要 AI，但 Agent 需要"看到 402 → 解析 → 判断预算 → 支付 → 验证交付 → 异常时暂停"，这是 AI 驱动的自主决策链路。

### 备选方向（放 backlog）

| 方向 | 暂时不选的原因 |
|------|---------------|
| Agent DeFi Execution (③) | DeFi Agent 的推荐质量无法在测试网验证（主网才有真实数据）；"意图理解"的好坏缺乏客观评估标准；实用场景不清晰 |
| Wallet/Permission (④) | 偏基础设施层，单独 demo 效果差；但 Pact 权限配置会融入 x402 Agent 的执行层 |

---

## 四、方向判断矩阵（5 维度评估）

| 维度 | 问什么 | 分析 |
|------|--------|------|
| **结构性需求** | 这个问题长期存在还是蹭热点？ | **长期存在**。机器/Agent 之间的微支付需求一直存在（API 调用、数据查询、AI 推理），传统支付方案（信用卡/订阅制/API Key）都不适合 Agent 间的按次小额支付 |
| **验证可能性** | 能用 demo/流程图/交易记录/用户访谈验证吗？ | **完全可以**。Sepolia 测试网上：部署 x402 服务 → Agent 发起请求 → 收到 402 → CAW 付款 → 拿到结果。每一步都有链上 tx hash 可验证 |
| **最小切入点** | 一周内能不能做出问题拆解、流程图、mock 或最小 prototype？ | **能**。Week 2 产出完整拆解+流程图+proposal；Week 3 即可实现最小版：一个受 x402 保护的简单 API + 一个能自动付款的 Agent 脚本 |
| **风险边界** | 涉及私钥/签名/资金/身份/治理权力吗？ | **可控**。测试网资金无价值；Agent 通过 CAW 管理签名（不直接握私钥）；Pact 限制单次/单日支付上限；所有交易在测试网，零真实资产风险 |
| **后续承接** | 能否自然进入 Week 3 proposal、Hackathon track 或长期 backlog？ | **直接承接**。Week 3 实现 x402 server + CAW Agent → Week 4 增加更复杂的支付场景（多服务比价、escrow）→ Hackathon 可演示完整 Agent Commerce 链路 |

### 失败模式分析

| 如果这个方向失败，最可能的原因是 | 判断 |
|------|------|
| 需求不存在？ | 低概率——Agent 调用付费 API 是真实需求（AI 推理、数据查询、计算服务） |
| 信任不可建立？ | 低概率——链上支付+收据天然可信，不需要信任任何中介 |
| 成本过高？ | 低概率——测试网 gas 免费；主网 L2 上 gas 极低 |
| 接口不成熟？ | **中概率——x402 本身还在早期，文档和工具链可能不完善** |
| 权限风险？ | 低概率——Pact 硬约束+测试网，风险可控 |
| 用户不愿改变流程？ | 低概率——如果 API 只有 x402 一个入口，用户别无选择；Agent 用的是机器流程，不涉及用户习惯 |

---

*Week 2 Day 1 | AI × Web3 School*
