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

Uniswap V2 引入了 TWAP 预言机：

- 不是简单取当前价格，而是计算一段时间内的**时间加权**平均价
- 每次 swap 时更新累加器：`priceAccumulator += price * timeElapsed`
- TWAP = `(priceAccumulator_now - priceAccumulator_then) / (now - then)`

为什么用 TWAP：
- 抵抗闪电贷操控瞬时价格
- 攻击者需要持续多笔交易才能影响 TWAP，成本极高
- 很多借贷协议用 Uniswap TWAP 做价格预言机

V3 进一步优化了 TWAP 的精度和 gas 效率。

---

## Key Takeaways

1. **V2 简单但资金效率低**——恒定乘积 AMM，全区间做市，IL 是 LP 的主要风险
2. **ERC-4626 Inflation Attack 是 shares-based 合约的通用攻击面**——Uniswap 用 MINIMUM_LIQUIDITY 解决了同类问题
3. **V3 的集中流动性是 game changer**——自定义做市区间，资金效率数量级提升
4. **Tick = 价格的离散单位**——1.0001 为底的对数价格，配合 bitmap 实现高效遍历
5. **TWAP 防价格操控**——时间加权让瞬时操控不划算

---

*2026-05-21 | AI × Web3 School*
