# GDD: AI-Powered 3D World Builder

> GLM-5.1 驱动的自主 3D 世界构建系统

## 1. Overview

AI-Powered 3D World Builder 是一个 GLM-5.1 驱动的长程自主 Agent 系统，从自然语言描述自动生成可交互的 3D 虚拟展厅，并将每个展位的艺术品质铸为链上 NFT。系统覆盖从需求理解、规划、渲染、视觉评估、自我纠错到链上发布的完整闭环。

## 2. Player Fantasy

**用户体验**：用户只需用一句话描述想要的场景（如"赛博朋克风格的 NFT 展厅"），Agent 自主完成全部工作。用户在 Web Dashboard 上实时观看 Agent 的思考过程、3D 渲染结果、视觉评估打分、自我修复过程，最终获得链上 NFT 资产。

**评委体验**：看到 Agent 如何：
- 自主拆解自然语言需求为专业 3D 设计方案
- 生成可执行的 JSON 规格文件驱动 Godot 引擎
- 用多模态视觉能力评估自己的渲染结果
- 根据评估反馈自我修复设计方案
- 完成多轮迭代直到质量达标
- 将成果铸为链上 NFT

## 3. Detailed Rules

### 3.1 Agent 工作流程 (Long-Horizon Task)

```
用户输入 → Prompt优化 → GLM-5.1生成SceneSpec → 写入JSON
→ Godot渲染3D场景 → 截图 → GLM-5.1视觉评估
→ [不达标] → GLM-5.1修改Spec → 重新渲染 → 循环
→ [达标] → 部署NFT合约 → 批量铸造 → 完成
```

### 3.2 评估维度 (5-dimension Evaluation)

| 维度 | 权重 | 评分标准 |
|------|------|----------|
| 动线合理性 | 20% | 展位分布是否合理，通道是否通畅 |
| 展位密度 | 20% | 展位数量和间距是否舒适 |
| 灯光氛围 | 20% | 灯光层次、氛围效果 |
| 色彩协调 | 20% | 颜色搭配是否和谐 |
| 艺术品展示 | 20% | NFT艺术品是否突出 |

### 3.3 自我纠错机制

- 评估分数 < 8/10 触发修复
- 最多 3 轮修复迭代
- GLM-5.1 查看评估反馈 + 原始截图进行针对性修复
- 每轮修复只修改有问题的部分

## 4. Formulas

### 展位位置约束
```
x ∈ [-width/2 + margin, width/2 - margin]    // margin = 1.0
y = 0.0                                       // 地面
z ∈ [-depth/2 + margin, depth/2 - margin]    // margin = 1.0
中心通道保护: |x| < 0.5 && |z| < 1.0 → 禁止放置
```

### 灯光强度
```
omni_energy = intensity × 0.01                // 线性缩放
omni_range = distance_to_farthest_booth + 1.5 // 自动计算
```

### 视觉评估分数
```
overall_score = (circulation + density + lighting + color + artwork) / 5
pass_threshold = 8.0
```

## 5. Edge Cases

- **GLM API 超时**: 2 次重试，间隔递增 (2s, 4s)
- **JSON 解析失败**: 多策略容错（markdown fence 剥离、JSON object 提取）
- **Godot 未运行**: 自动跳过视觉评估，默认通过 (score=8)
- **Web3 链不可达**: 非阻塞失败，不影响 3D 渲染流程
- **DNS 解析失败**: 内置 DNS 补丁 (open.bigmodel.cn → 119.23.85.51)
- **渲染超时**: 30 秒等待，超时后使用现有截图

## 6. Dependencies

- GLM-5.1 API (via Anthropic-compatible endpoint)
- Godot 4.6 Engine
- Foundry (Anvil local chain)
- Python 3.11+ (web3.py, fastapi, uvicorn)
- OpenZeppelin ERC-721

## 7. Tuning Knobs

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| MAX_REPAIR_ROUNDS | 3 | 1-5 | 最大修复轮次 |
| DEFAULT_SCORE_THRESHOLD | 8 | 1-10 | 评估通过阈值 |
| ROOM_WIDTH | 10-20 | 8-30 | 房间宽度 |
| ROOM_HEIGHT | 4-8 | 3-12 | 房间高度 |
| ROOM_DEPTH | 12-24 | 8-30 | 房间深度 |
| BOOTH_COUNT | 3-8 | 1-12 | 展位数量 |
| ART_TEXTURE_SIZE | 256×320 | 128-512 | 纹理分辨率 |

## 8. Acceptance Criteria

- [ ] 从自然语言生成有效的 scene_spec.json
- [ ] Godot 正确渲染 3D 场景并截图
- [ ] GLM-5.1 视觉评估返回 1-10 分数
- [ ] 评估不达标时自动修复并重新渲染
- [ ] SSE 实时推送 Agent 工作过程
- [ ] Web Dashboard 展示完整执行时间线
- [ ] 部署 ERC-721 合约并铸造 NFT
- [ ] 完整执行记录可追溯
