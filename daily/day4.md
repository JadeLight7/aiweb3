# Day 4 — Uniswap V2 / V3 Deep Dive

## Uniswap V2: The Foundation

### AMM 核心机制

Uniswap V2 是恒定乘积做市商（Constant Product Market Maker）：

```
x * y = k
```

- `x` = Token A reserve，`y` = Token B reserve
- `k` 在单次 swap 中保持不变（不含手续费）
- 交易会改变 `x` 和 `y` 的比例，从而改变价格

### Price Impact & Slippage

池子越小，单笔交易对价格的影响越大。这是 AMM 的固有属性，不是 bug：
- **Price Impact**：交易本身造成的价格变化
- **Slippage**：交易广播到执行之间，其他人的交易导致的价格变化

用户设置 `minAmountOut` 来防止前端运行攻击。

### LP Token & Fees

- 提供流动性获得 LP Token，代表你在池子中的份额
- 每笔交易收取 0.3% 手续费，按比例分配给 LP
- 手续费直接留在池子中，增加 `k`，赎回时一并取出

### Impermanent Loss（无常损失）

当池子中两种 token 的相对价格发生变化时，LP 会比简单持有（HODL）更差：

- 价格偏离越大，IL 越大
- 价格涨 1 倍 → IL 约 5.7%
- 价格涨 4 倍 → IL 约 20%
- 手续费收入能否覆盖 IL 是关键考量

注意："impermanent" 是误导——如果价格不回来，损失就是永久的。

---

## ERC-4626 Inflation Attack（引申阅读）

从 Uniswap V2 的 LP Token share 计算引申看了 Vault 类合约的经典攻击面。

### 攻击原理

ERC-4626 Vault 的 share 计算：`shares = assets * totalSupply / totalAssets`

攻击者：
1. 向 Vault 直接转入少量资产（不走 deposit，绕开 share mint）
2. `totalAssets` 变大，`totalSupply` 不变
3. 正常用户 deposit 时，`shares` 被向下取整，可能 mint 出 0 share
4. 攻击者赎回自己的 share，拿走用户的资产

### 防护措施

- **Virtual offset**：给 `totalAssets` 加一个虚拟偏移量（如 1e18），让攻击者在 share 计算中需要极大成本
- **Dead shares**：部署时就 mint 少量 share 到 0xdead 地址，让 totalSupply 永远不为 0
- OpenZeppelin 的 ERC-4626 实现已经内置了这些防护

### 与 Uniswap 的关联

Uniswap V2 也有类似的 front-run 攻击面——第一个 LP 可以通过操纵初始流动性比例来定价。Uniswap 的做法是 burn 前 1000 个 LP unit（`MINIMUM_LIQUIDITY`），和 dead shares 思路一致。

---

## Uniswap V3: Concentrated Liquidity

### 核心变革：从全区间到自定义区间

V2 的问题是资金效率低：流动性均匀分布在 `(0, ∞)` 价格区间，大部分资金在远离市场价的地方闲置。

V3 允许 LP 在自定义价格区间 `[Pa, Pb]` 内提供流动性：
- 区间越窄 → 资金越集中 → 费率收入越高
- 但也意味着价格一旦跑出区间，你的流动性不再参与交易，也不再赚手续费
- 你可以理解成 V3 的流动性是 "active only when price is in your range"

### Tick：价格的最小单位

V3 用 Tick 来表示价格，而不是直接使用价格值：

```
price = 1.0001^tick
```

- `tick = 0` → price = 1（两种 token 1:1）
- `tick` 每增加 1 → 价格乘以 1.0001
- `tick` 每减少 1 → 价格除以 1.0001
- `tick` 是整数，所以价格是离散的

为什么要用 tick？
- 便于计算流动性分布
- 每个 tick 是一个价格分界点，swap 时可以逐个 tick 跨过
- tick 间距（tick spacing）控制了池子精度：稳定币对用 tickSpacing=1，普通对用 60 或 200

### Tick Bitmap

遍历所有可能的 tick 太贵了。Uniswap 用 bitmap 来快速定位下一个有流动性的 tick：

```
bitmap 是一个 mapping(uint16 => uint256)
```

- 每个 uint256 存 256 个 tick 的 "是否有流动性" 标记
- swap 时从当前 tick 开始，在 bitmap 中找到最近的下一个有流动性的 tick
- 不需要逐 tick 遍历空区间，gas 消耗大幅降低

这是 Uniswap V3 能在 swap 路径上跨越多个池子的关键优化。

### 流动性计算

V3 的流动性不再是 V2 的简单 `sqrt(k)`，而是：

- **虚拟储备（virtual reserves）**：把流动性区间映射回等效的 `x * y = k` 曲线
- 区间 `[Pa, Pb]` 内的流动性可以理解为：用更少的实际 token 达到与 V2 全区间相同的深度
- `L = Δy / (√P_upper - √P_lower)` 之类的公式（不深入，知道 L 是 liquidity amount 即可）

直观理解：如果你在 V3 把 1 ETH + 2000 USDC 放在 `[1800, 2200]` 区间，它的做市深度相当于 V2 需要投入 5-10 倍资金的效果。

### TWAP（Time-Weighted Average Price）

#### V2 TWAP 机制

Uniswap V2 每笔 swap 之前会先更新一个**价格累加器**（price accumulator）：

```
priceCumulativeLast += lastPrice * (currentTimestamp - lastTimestamp)
```

外部合约查询 TWAP：

```
TWAP = (priceCumulativeLast_now - priceCumulativeLast_ago) / (now - ago)
```

- 不在链上存储时间窗口，而是由查询方提供两个时间点的累加器值
- 常见窗口：30 分钟、1 小时、2 小时
- 窗口越长越安全，但价格越滞后
注意：时间窗口要长，流动性要高，不然仍然会被操纵
#### 为什么不用 Spot Price

- **Spot price 可被一笔大额 swap 瞬间改变**，配合闪电贷，借贷协议如果用它做清算判断会被操控
- TWAP 要求攻击者持续多笔交易覆盖整个时间窗口，成本 = 持续做市亏损 × 窗口长度
- 攻击者需要压低价格维持 30 分钟，期间 arbitrageur 会不断搬砖纠正价格 → 攻击成本极高

#### V3 TWAP 的改进

- V3 不只记录 price，还记录了 `tickCumulative` 和 `secondsPerLiquidityCumulative`（用于计算几何平均 TWAP）
- 精度更高——V2 用 uint224 存 price，精度有限；V3 tick 累加器用 int56
- 支持多 pool 聚合查询，不依赖单一池子
- 查询方可以用 `observe()` 获取任意历史 tick 值，然后算出窗口内的时间加权几何平均价

#### TWAP 的局限

- 只对流动性充足的池子可靠——冷门 token 或新池子即使 TWAP 也容易被操控
- 只是一个工具，不是银弹——需要结合其他安全措施

---

## V2 Security Concerns

### 1. Flash Loan + Spot Price Manipulation

攻击者用闪电贷借巨量资产，在池子里一笔 swap 把价格砸到极端值，然后在依赖该池子 spot price 的借贷协议里清算或借贷，最后还贷走人。整个过程在一个交易内完成。

防护：**永远不要用 spot price 做清算判断**，用 TWAP。


### 3. First LP Initialization Attack

第一个 LP 可以任意设定初始价格，如果另一个池子或协议已经依赖这个价格，Attacker 可以先用极小流动性创建极端价格，然后套利依赖方。

防护：Uniswap V2 会在初始化时 burn 掉 `MINIMUM_LIQUIDITY`（1000 个最小 LP unit），但这只解决 share 通胀问题，不解决价格初始化问题。外部依赖方应验证池子流动性深度。

### 4. Fee-on-Transfer Token 不兼容

V2 假设 `amountIn` 完全到账。如果 token 有转账税（如某些 meme coin），实际到账 < 预期，池子储备会计就会出错——攻击者可以用更少的 token 换走更多的对侧资产。

防护：不要对有 transfer fee 的 token 创建 Uniswap V2 池子，或使用包装器标准化。

---

## V3 Security Concerns

### 1. TWAP 更易被操控（集中流动性反噬）

V3 的流动性集中在活跃 tick 附近，远离市价的地方流动性极薄。这意味着：

- 攻击者推价格跨越一个 tick 区间后，后续 tick 可能几乎没有对手流动性
- 同样的资金量在 V3 可以推动价格更远
- **V2 需要的攻击成本 >> V3 在流动性浅的池子**

防护：V3 TWAP 查询时应拉长窗口并验证池子的流动性深度；协议不应只信任单一 V3 池子的 TWAP。

### 2. JIT (Just-In-Time) Liquidity Attack

这是 V3 特有的 MEV：

1. 攻击者看到大额 swap 在 mempool
2. 在 swap 执行前 mint 一笔极窄区间的流动性，精确覆盖当前 tick
3. swap 执行 → 攻击者的流动性赚走了大部分手续费
4. 攻击者在同一笔交易中立刻 burn 流动性退出

结果：真正长期 LP 的手续费被 JIT 攻击者吃掉，做市 ROI 下降。

防护：目前社区在讨论协议层手续费分配优化，尚无完美解法；长期 LP 选择手续费较高的池子可以减少 JIT 比例。

### 3. 区间外 LP 的 "零收入" 风险

V3 LP 在价格跑出区间后，流动性变成纯粹的单一 token，不再赚手续费：

- 牛市/熊市剧烈波动时，窄区间 LP 很容易被踢出
- 频繁调区间 = 频繁支付 gas，侵蚀手续费收入
- 被动 LP 策略需要平衡区间宽度 vs 收入效率

### 4. Precision Loss with Extreme Ranges

Tick 是离散的（`tickSpacing` 限制），极窄或极偏的区间可能有精度损失：

- `tickSpacing=60` → 相邻可用 tick 之间价格差约 0.6%
- 稳定币对（`tickSpacing=1`）精度好，但波动币对可能在一个 tick 内就覆盖全部流动性
- 极低价位（如 token 几乎归零）→ tick 远离 0，计算中的平方根精度下降

### 5. Unchecked Oracle Cardinality

V3 的 `observations` 数组需要提前扩展（支付 gas）才能存储历史 tick 数据：

- 新池子默认只能存 1 个 observation → 查 TWAP 退化为 spot price
- 池子创建者若不调用 `increaseObservationCardinalityNext()` → 预言机不可靠
- 依赖方应检查 `observationCardinality` >= 所需的采样点数

### 6. 虚假 Token / 同名池子

攻击者创建名字和 symbol 与知名 token 相同的假 token，然后创建假池子，欺骗前端或用户。V3 的 Factory 无权限限制，任何人都能为任何 token 创建池子。

防护：验证 token 合约地址（不是 symbol），只信任官方列出的池子地址。

---

## Key Takeaways

1. **V2 简单但资金效率低**——恒定乘积 AMM，全区间做市，IL 是 LP 的主要风险
2. **ERC-4626 Inflation Attack 是 shares-based 合约的通用攻击面**——Uniswap 用 MINIMUM_LIQUIDITY 解决了同类问题
3. **V3 的集中流动性是 game changer**——自定义做市区间，资金效率数量级提升，但引入了 JIT 攻击和更高的 TWAP 操控风险
4. **Tick = 价格的离散单位**——1.0001 为底的对数价格，配合 bitmap 实现高效遍历，但 tickSpacing 带来的精度问题需要注意
5. **TWAP 的核心价值是对抗闪电贷操控**——V3 改进了精度但集中流动性让操控成本降低，依赖方需验证 observation cardinality 和流动性深度
6. **V2 安全问题**：Sandwich Attack、Flash Loan 价格操控、Fee-on-Transfer 不兼容
7. **V3 新增攻击面**：JIT Liquidity、Oracle 操控成本降低、区间外零收入、假 token 池子

---

*2026-05-21 | AI × Web3 School*
