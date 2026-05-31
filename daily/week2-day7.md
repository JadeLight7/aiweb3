
## 一、技术栈确认

### 核心组件

| 组件 | 技术 | 用途 | 成熟度 |
|------|------|------|--------|
| 合约 | Solidity + Hardhat | 存储支付记录 | ✅ 成熟 |
| 测试网 | Sepolia | 所有交易 | ✅ 成熟 |
| 链上交互 | viem | 查询/写入链上数据 | ✅ 成熟 |
| 服务端 | Node.js + Express | x402 服务端 | ✅ 成熟 |
| Agent | Node.js | 自动购买逻辑 | ✅ 成熟 |
| 钱包 | Cobo CAW 或 viem 直接签 | 自动支付 | ⚠️ 需验证 |

### 关键决策：CAW vs viem

**问题**：CAW SDK 是否支持调用自定义合约？

**分析**：
- CAW 主要设计用于 ETH/ERC20 转账
- 我们的支付记录合约需要调用 `recordPurchase()` 函数
- 如果 CAW 不支持自定义合约调用，需要用 viem 直接签名

**方案**：
- **优先尝试 CAW**：如果支持，更简单，有 Pact 权限控制
- **备选 viem**：如果 CAW 不支持，用 viem 直接签名，更灵活

**结论**：先验证 CAW 的能力，再决定最终方案。

---

## 二、x402 协议实现细节

### 协议流程

```
① Client → GET /api/token/openai-api
② Server → 402 Payment Required
   Body: {
     "amount": "10000000000000000",  // 0.01 ETH
     "token": "ETH",
     "chain": "sepolia",
     "recipient": "0x...",
     "deadline": 1717123456,
     "description": "OpenAI API token"
   }
③ Client 解析 → 检查 Pact 预算 → 支付
④ Client → GET /api/token/openai-api
   Header: X-Payment-Proof: 0xabc...
⑤ Server 验证 tx → 200 OK + token
```

### 验证逻辑

**服务端验证**：
1. 解析 X-Payment-Proof 头部的 tx_hash
2. 查询链上交易状态
3. 验证 tx 的 recipient、amount 与 402 响应匹配
4. 验证 tx 确认数足够（1-3 个区块）
5. 验证 tx 未被使用过（防重放）

**客户端验证（Pact 约束）**：
1. 检查 amount ≤ per_tx_limit（0.05 ETH）
2. 检查 recipient 在白名单
3. 检查 chain 在白名单
4. 检查 deadline 未过期
5. 检查 daily 累计 + amount ≤ daily_limit

### 安全边界

```
🟢 自动支付（Pact 范围内）：
  ✅ 金额 ≤ 0.05 ETH
  ✅ 收款方在白名单
  ✅ 链在白名单
  ✅ 单日累计 < 0.2 ETH
  ✅ gas < 50 gwei

🔴 暂停+人工确认：
  ❌ 金额 > 0.05 ETH
  ❌ 收款方不在白名单
  ❌ 非白名单链
  ❌ 单日累计将超限
  ❌ gas > 100 gwei
  ❌ 402 deadline 已过期
```

---

## 三、合约设计

### 数据结构

```
交易记录：
- id: uint256 (交易 ID)
- agent: address (Agent 地址)
- tokenType: string (token 类型，如 "openai-api")
- amount: uint256 (支付金额，wei)
- seller: address (服务商地址)
- timestamp: uint256 (交易时间)
- txHash: bytes32 (支付交易哈希)
- purpose: string (用途描述，可选)
```

### 核心函数

```
recordPurchase(tokenType, amount, seller, txHash, purpose)
  - 记录一笔购买
  - 更新 Agent 的统计数据
  - 返回交易 ID

getPurchase(id)
  - 查询单笔交易详情

getAgentPurchases(agent)
  - 查询 Agent 的所有交易

getTotalSpent(agent)
  - 查询 Agent 的总支出

getSpentByTokenType(agent, tokenType)
  - 按 token 类型查询支出
```

### 设计决策

| 决策 | 选择 | 原因 |
|------|------|------|
| 存储位置 | 链上 | 不可篡改，任何人可查 |
| 数据粒度 | 每笔交易 | 支持详细查询和统计 |
| 查询方式 | 事件 + 函数 | 事件用于索引，函数用于直接查询 |

---

## 四、MVP 实现路径

### Phase 1：最小闭环（3 天）

**Day 8：合约 + 服务端**
- 搭建 Hardhat 项目
- 编写支付记录合约
- 部署到 Sepolia
- 编写 x402 服务端（模拟 token 服务商）

**Day 9：Agent 脚本**
- CAW/viem 集成
- Agent 脚本：请求→402→检查预算→支付→记录
- 端到端测试

**Day 10：查询 + 文档**
- 查询功能：本月花了多少？按 token 类型统计
- README + 演示

### Phase 2：预算控制（2 天）

- Pact 配置：单笔/每日/每月上限
- 预算检查逻辑
- 警告机制（80% 预算）
- 暂停机制（100% 预算）

---

## 五、可行性评估

### 技术可行性

| 组件 | 可行性 | 风险 | 缓解 |
|------|--------|------|------|
| 支付记录合约 | ✅ 高 | 低 | 标准 Solidity |
| x402 服务端 | ✅ 高 | 低 | Express + 链上验证 |
| Agent 脚本 | ✅ 高 | 低 | Node.js + viem |
| CAW 集成 | ⚠️ 中 | 中 | 备选 viem 直接签 |
| Sepolia 测试网 | ✅ 高 | 低 | Faucet 获取测试 ETH |

### 时间评估

| 任务 | 预计时间 | 依赖 |
|------|----------|------|
| 搭建 Hardhat 项目 | 1 小时 | 无 |
| 编写支付记录合约 | 2 小时 | Hardhat 项目 |
| 部署合约到 Sepolia | 1 小时 | 合约 + 测试 ETH |
| 编写 x402 服务端 | 2 小时 | 无 |
| 编写 Agent 脚本 | 3 小时 | CAW/viem + 服务端 |
| 端到端测试 | 2 小时 | 所有组件 |
| **总计** | **11 小时** | |

### 关键风险

| 风险 | 概率 | 影响 | 缓解 |
|------|------|------|------|
| CAW 不支持自定义合约 | 中 | 中 | 用 viem 直接签 |
| x402 文档不完整 | 中 | 中 | 参考示例代码 |
| 测试网 ETH 不够 | 低 | 低 | 多 faucet 领取 |
| 合约 gas 过高 | 低 | 低 | 测试网不要求优化 |

---

