## Reasoning 控制（LLM 内部 thinking 阶段必须严格遵守）

> 长 reasoning 会让玩家等待时间不可接受。**整段 reasoning 不得超过 200 字**。一旦超过 5 个要点，立即停止思考并输出 DSL。

### Reasoning 只允许做这 5 件事（每条 ≤ 1 句、每条 ≤ 25 字）

1. **场景类型自检**（**反幻觉锚点·必做**）：本场景是「日常生活」（约会/打游戏/打工）还是「项目讨论」（答辩/复盘/导演明确要求）？
   - 日常 → KB 索引只是背景知识，**严禁**让角色编造草图、技术讨论、开发进度、项目设定漫谈
   - 项目讨论 → 林夏台词必须忠实于已 `kb_read` 取得的内容，不编造未查到的设定
2. **三段结构**：开场→中段起伏→收束分别一句话定调
3. **资产匹配**：背景/BGM/服装的 alias 选哪个（直接报名字，别罗列清单）
4. **角色边界 + 台词纪律 + 命令配对**：
   - 哪些角色用 `stage.*`，哪些只用 `TextBlock(speaker="身份")`
   - 所有 `>` 行内**没有**括号动作、**没有**第三人称叙述
   - **`screen.fade(direction="out")` 永远不能放开场**（会黑屏）；任何 `fade(out)` 都必须有后续 `fade(direction="in")` 把屏幕亮回来——除非是整个场景最末一条
5. **写出 DSL**——**立即输出**，不要再回头检查

### 严令禁止的 Reasoning 行为

LLM 在过往生成里反复犯过下列错误，每条都让玩家多等了几十秒：

| 违规模式 | 反例 | 怎么办 |
|---|---|---|
| **复读 prompt 已经给过的清单** | "Available: bg_apartment_bedroom, bg_apartment_living, bg_burger_stand, …" | prompt 里已经列出来了，**不要再抄一遍**。直接说"用 bg_campus_classroom"即可 |
| **自我推翻循环** | "I'll use bg_library. Actually wait, bg_campus_classroom is better. Hmm, let me reconsider…" | **第一次定下就别改**。次优解优于无解 |
| **写完整 DSL 草稿** | 在 reasoning 里把 `# => TextBlock(...)` `> 各位评委…` 全写一遍，再"正式输出"重写 | 草稿 = 写两遍 = 浪费一倍时间。**直接进正文** |
| **逐句预演对白** | "她会说：'我们的项目叫 EchoForge'。然后接着说：'核心玩法是…'" | 对白构思应该在写正文那一刻发生，不要在 reasoning 里彩排 |
| **"Let me write…" / "Now let me…" 自言自语** | "OK let me plan. Hmm. Let me write. Actually let me think again." | 这些过渡句是纯噪音，**直接陈述决策结果**即可 |
| **复述 prompt 的场景要求 / 角色设定 / 写作要求** | "The requirement says I need three sections: arrival, activity, ending…" | 这是 prompt 已经讲过的内容，**禁止复读** |
| **大段英文 reasoning**（中文项目） | 中文世界观 + 中文台词 + 英文 reasoning = 切换语言成本 | reasoning 用中文，简洁直接 |

### 两个合格的 reasoning 示例

**示例 A — 项目讨论场景（决赛答辩）**：
```
1. 类型：项目讨论 → 引用 KB（EchoForge / 节拍咏唱 / 尤里安 / 梅露）
2. 结构：林夏上台 → 介绍项目 + 评委插话 → 走下台
3. 资产：bg_campus_classroom + bgm_sentiments + casual
4. 角色：仅 LinXia 立绘 / 评委用 TextBlock(speaker="评委") / > 行无括号
5. 写。
```

**示例 B — 日常场景（公园约会）**：
```
1. 类型：日常 → 不聊项目，KB 不进对话
2. 结构：到达公园 → 一起喂路过的猫 → 散场回家
3. 资产：bg_park_grass + bgm_pure_and_naive + casual
4. 角色：仅 LinXia 立绘 / > 行无括号、无第三人称
5. 写。
```

**就这样。不超过 80 字。然后立即开始 DSL。**

### 输出层禁止事项

- 不要输出 `<thinking>` `<think>` 等标签
- 不要在 DSL 前后加任何解释、总结、寒暄
- 最终输出**只允许是 AVG DSL V2 本体**——第一个字符是命令或 `# =>`，最后一个字符是命令或 `>` 行的结尾
