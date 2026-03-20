# 在家活动系统设计方案

## 1. 设计哲学

外出活动（约会、兼职、SBeam）是"事件驱动"的——去一个地方、发生一件事、回来。
在家活动是"空间共处"的——两个人在同一个屋檐下，互动从日常的缝隙里自然长出来。

核心原则：
- **不是所有在家活动都需要 AVG**。AVG 留给有叙事张力的关键时刻，日常用 LinkChat + 短消息 + 简单 UI。
- **松弛感优先**。同居的质感靠碎片化的消息和安静的共处来营造，不靠一段段正式演出。
- **林夏不是被动的**。她会主动发起互动，玩家可以选择回应或忽略（有代价）。
- **机会成本仍然存在**。在家聊天意味着不能去约会或赶工，选择本身就是游戏性。

## 2. 与现有系统的关系

### 时间结构（GameLoopManager）
- 每天 3 个时段：上午 / 下午 / 晚上
- 每时段 1 AP，消耗后自动推进
- 在家活动消耗 1 AP（与外出活动相同）
- 特例：「休息/睡觉」不消耗 AP，而是直接结束当天

### 属性系统（GameManager）
- 林夏三维：affection（好感）/ stress（压力）/ passion（激情）
- 项目四维：completion / quality / stability / hype
- money（零花钱）
- 在家活动主要影响三维，不直接影响项目四维

### 不继承 ActivitySessionManager
外出活动的状态机（departure → progress → scene → followup → moment → settlement）不适用于在家场景。
HomeActivityManager 是独立的 autoload，但复用以下组件：
- `ActivityChat`（LinkChat topic 对话）
- `MomentGenerator`（朋友圈生成）
- `GameManager`（属性修改）
- `GameLoopManager`（AP 消耗）

## 3. 活动分类总览

| 活动 | AP 消耗 | 交互方式 | 是否 AVG | 朋友圈 | 触发方式 |
|---|---|---|---|---|---|
| 休息/睡觉 | 1 | 睡前消息 + 跳过剩余时段 | 否（可触发事件） | 否 | 玩家主动 |
| 闲聊 | 1 | LinkChat topic（2-3 轮） | 否 | 偶尔 | 双向 |
| 谈心 | 1 | LinkChat topic（3-5 轮） | 可触发事件 | 经常 | 双向 |
| 各自忙各自的 | 1 | 简短描述 + 短消息 | 否 | 否 | 玩家主动 |
| 一起看东西 | 1 | 选择内容 + LinkChat 讨论 | 否 | 偶尔 | 双向 |
| 审视作品 | 1 | 展示进度 + LinkChat 讨论 | 否（可触发冲突） | 否 | 双向 |
| 亲密事件 | — | Important Event AVG | 是 | 是 | 条件触发 |
| 冲突事件 | — | Important Event AVG | 是 | 偶尔 | 条件触发 |
| 里程碑事件 | — | Important Event AVG | 是 | 是 | 条件触发 |

## 4. 各活动详细设计

### 4.1 休息/睡觉（rest）

**定位**：一天的结束仪式。不是"什么都不做"，而是一天中最私密的时刻。

**AP 消耗**：1 AP。和所有其他行动一样，休息就是"这个时段你选择了睡觉"。
如果在晚上选择，消耗 AP 后自动推进到下一天。
如果在上午或下午选择（提前休息），消耗 1 AP 后跳过后续所有时段直接进入下一天——代价是丢掉剩余行动机会。这让"提前休息"成为一个有意义的决策：你是真的撑不住了才会这么做。

**流程**：
1. 玩家选择休息 → 消耗 1 AP
2. 根据当前状态生成一条「睡前消息」（LLM 或 fallback）
3. 林夏在 LinkChat 发送这条消息（可能是晚安、可能是还在工作的碎碎念、可能是沉默）
4. 跳过剩余时段 → `GameLoopManager.advance_to_next_day()`
5. 新一天开始时，林夏发送「早安消息」

**属性效果**：
- stress -3（基础）
- 如果 affection >= 50：额外 stress -2（关系好睡得安稳）
- 如果 stress >= 70：只恢复 stress -1（焦虑到睡不好）
- `GameManager.on_new_day()` 的自然恢复照常执行

**特殊触发**：
- stress >= 80 → 可能触发「失眠事件」（Important Event AVG）
- affection >= 70 + 特定前置 → 可能触发「深夜对话事件」

**睡前消息 fallback 示例**：
- 普通："晚安。明天见。"
- 高好感："今天辛苦了。……嗯，晚安。"
- 高压力："我再改一会儿，你先睡吧。"
- 刚吵完架："……晚安。"

### 4.2 闲聊（chat_casual）

**定位**：轻量级关系维护。不追求深度，追求自然。

**流程**：
1. 玩家选择闲聊（或林夏主动发起）→ 消耗 1 AP
2. 启动 LinkChat topic，注入当前上下文：
   - 最近发生的事（刚约会回来？刚完成一个工单？）
   - 当前时段（上午的闲聊 vs 晚上的闲聊语气不同）
   - 她的心情和状态
3. 2-3 轮对话后 topic 自动结束
4. 结算：affection +1, stress -1
5. 概率生成朋友圈（约 20%）

**topic prompt 构建要点**：
- 不要让 LLM 写成"正式谈话"，要像两个人坐在沙发上随口聊
- 注入最近 1-2 个活动的摘要作为话题种子
- 明确指示：不要主动提起项目进度，除非玩家先提

### 4.3 谈心（chat_deep）

**定位**：深度关系推进。解锁林夏的内心世界和背景故事。

**前置条件**：affection >= 20

**流程**：
1. 玩家选择谈心（或林夏在特定条件下主动发起）→ 消耗 1 AP
2. 启动 LinkChat topic，注入深度上下文：
   - 林夏的背景故事进度（已解锁到哪一层）
   - 当前关系阶段的核心矛盾
   - 最近的情感事件
3. 3-5 轮对话
4. 结算：affection +2~3, stress -1 或 +1（取决于话题是否触及痛点）
5. 高概率生成朋友圈（约 50%）
6. 检查 Important Event 触发条件

**背景故事解锁机制**：
- 林夏的故事分层解锁（lore_level: 0 → 1 → 2 → 3）
- 每次谈心根据当前 lore_level 注入对应层的 prompt 上下文
- 特定 lore_level + affection 阈值 → 触发 Important Event AVG

### 4.4 各自忙各自的（personal）

**定位**：独处时间。降压但不加感情。过度使用有代价。

**流程**：
1. 玩家选择 → 消耗 1 AP
2. 简短文字描述两人各自在做什么（LLM 生成或 fallback pool 随机）
3. 林夏可能在 LinkChat 分享一条她看到的东西（约 30% 概率）
4. 结算：stress -2, affection 0
5. 如果连续 3 次选择 personal → affection -1（她会觉得被冷落）

**描述 fallback 示例**：
- "你戴上耳机刷了一会儿手机。她在旁边翻一本不知道从哪借来的小说。"
- "你打开笔记本看了一集番。她趴在桌上画草稿，偶尔抬头看你一眼。"
- "你们各自安静了一个时段。窗外的风偶尔吹进来。"

### 4.5 一起看东西（watch）

**定位**：共享体验，类似在家版 SBeam，但更轻量。

**流程**：
1. 选择观看内容（2-3 个选项，从 pool 中随机）：
   - 动画/电影片段
   - 游戏直播
   - 竞争对手的 AVG Demo（特殊：影响项目方向讨论）
2. 消耗 1 AP
3. 启动 LinkChat topic，讨论刚看的内容（1-2 轮）
4. 结算：affection +1, stress -2
5. 如果看的是竞争对手作品：可能触发关于自己项目方向的讨论（passion +1 或 stress +1）

**内容 pool 数据格式**：
```json
{
  "content_id": "anime_quiet_night",
  "title": "《深夜食堂》第三季",
  "type": "anime",
  "tone": "cozy",
  "reaction_seeds": [
    "她看到某个角色的台词时笑了一下，但没解释为什么",
    "片尾曲响起来的时候她没有跳过，就让它放完了"
  ]
}
```

### 4.6 审视作品（review）

**定位**：工作与关系的桥梁。是唯一一个在家活动中涉及项目的。

**前置条件**：completion >= 10（至少有东西可看）

**流程**：
1. 玩家选择审视作品 → 消耗 1 AP
2. 展示当前 AVG 项目的状态摘要（completion / quality / stability）
3. 启动 LinkChat topic，林夏给出她的看法：
   - quality 高：她会表达满意
   - quality 低 + passion 高：她会提出改进想法
   - quality 低 + passion 低：她会有些沮丧
   - 如果最近有创意分歧：可能升级为冲突
4. 结算：passion +1~2（重新审视作品能激发热情）
5. 检查冲突事件触发条件

## 5. 条件触发的 Important Event（AVG 场景）

这些事件不在活动菜单中，而是在特定在家活动进行时被触发。
采用与 DateManager 的 Important Event 相同的技术方案：模板化 AVG + DateEventPlayer 播放。

### 5.1 触发评估时机

每次在家活动的 `_apply_settlement` 阶段，调用 `_evaluate_important_events(session)` 检查是否满足触发条件。
如果满足 → 在结算前插入 Important Event AVG 播放。

### 5.2 事件类型

#### 亲密事件（intimate）

触发条件（全部满足）：
- affection >= 阈值（首次 40，后续递增）
- stress < 50（太焦虑不会发生）
- 当前活动是 chat_deep 或 rest（只在私密场景触发）
- 该事件 ID 未被播放过

设计要点：
- 不是"选择亲热"，而是对话自然升温后的转折
- AVG 场景以氛围铺垫为主，选择点影响亲密程度和后续关系走向
- affection 变化较大（+3~5）

#### 冲突事件（conflict）

触发条件（任一满足）：
- stress >= 70 且 passion < 30（高压低热情 → 爆发）
- 连续 3 天没有约会或闲聊（冷落触发）
- review 活动中 quality < 20 且 completion > 40（做了很多但质量差 → 争执）

设计要点：
- 冲突不是惩罚，是关系的转折点
- 玩家的选择决定冲突走向：和解（affection 小降但 stress 大降）/ 僵持（affection 大降）/ 突破（affection 反升，解锁新的关系层次）
- 冲突后的 followup 消息语气明显不同

#### 里程碑事件（milestone）

触发条件：
- 项目 completion 首次达到 25 / 50 / 75
- 或者 GameLoopManager 的 milestone_reached 信号触发时

设计要点：
- 庆祝或反思的时刻
- 如果 quality 高：两人一起开心
- 如果 quality 低但 completion 达标：复杂情绪（赶出来了但不满意）
- affection 和 passion 都可能变化

### 5.3 Important Event 数据格式

复用 DateEventBuilder 的模板结构：

```json
{
  "event_id": "intimate_first_closeness",
  "event_type": "intimate",
  "trigger": {
    "min_affection": 40,
    "max_stress": 50,
    "allowed_activities": ["chat_deep", "rest"],
    "once": true
  },
  "window_title": "那个晚上",
  "title": "第一次靠近",
  "intro_lines": [
    {"speaker": "", "text": "不知道从什么时候开始，沙发上两个人之间的距离变得比平时近了一点。"},
    {"speaker": "林夏", "text": "……你有没有觉得，最近我们好像比刚开始的时候自然多了。"}
  ],
  "choice_prompt": {
    "speaker": "林夏",
    "text": "你在想什么？"
  },
  "choices": [
    {
      "choice_id": 1,
      "text": "说实话，我在想你刚才那个表情",
      "summary": "你坦率地回应了她，气氛变得更近了一步。",
      "result_tag": "honest",
      "affection_delta": 4
    },
    {
      "choice_id": 2,
      "text": "没什么，就是觉得现在挺好的",
      "summary": "你没有推进，但也没有后退。她似乎理解了。",
      "result_tag": "gentle",
      "affection_delta": 2
    },
    {
      "choice_id": 3,
      "text": "在想明天的工作安排",
      "summary": "你把话题拉回了安全区。她笑了一下，但眼神里有一瞬间的失落。",
      "result_tag": "deflect",
      "affection_delta": -1
    }
  ],
  "outro_lines": [
    {"speaker": "", "text": "窗外的路灯把影子拉得很长。今晚的安静和平时不太一样。"}
  ]
}
```

## 6. 林夏主动发起系统

### 6.1 设计意图

如果所有互动都由玩家发起，林夏就变成了一个"等待被选择的菜单项"。
主动发起系统让她成为一个有自己节奏和需求的人。

### 6.2 机制

每个时段开始时，`HomeActivityManager` 评估是否生成一个「林夏主动发起」：

**评估条件**（概率叠加）：
- 基础概率：15%
- affection >= 50：+10%
- stress >= 60（她的）：+15%（压力大时更需要倾诉）
- 连续 2 个时段玩家没有和她互动：+20%
- 刚发生重大事件（约会回来、工单完成）：+10%

**发起形式**：
林夏在 LinkChat 发一条消息，暗示她想做某件事：
- "你吃了吗？我刚煮了点东西。"（meal）
- "忙完了吗？我想跟你说个事。"（chat_deep）
- "你要不要过来看一下这个？"（watch / review）
- "……今天好累。"（chat_casual，但可能升级为 chat_deep）

**玩家响应**：
- 接受 → 开始对应活动（消耗 AP）
- 忽略 → 不消耗 AP，但 affection -1，且她的下一条消息语气会变
- 主动发起的活动 affection 收益 +1（她会因为你回应了而更开心）

### 6.3 数据格式

```json
{
  "initiative_id": "she_wants_to_talk",
  "activity_type": "chat_deep",
  "trigger_weight": {
    "base": 0.1,
    "high_stress_bonus": 0.15,
    "no_interaction_bonus": 0.2
  },
  "message_variants": [
    "忙完了吗？我想跟你聊点事。",
    "你现在有空吗？",
    "……我有点话想说，但不知道怎么开口。"
  ],
  "decline_affection_penalty": -1,
  "accept_affection_bonus": 1
}
```

## 7. 技术架构

### 7.1 HomeActivityManager（autoload）

```
HomeActivityManager
├── 信号
│   ├── activity_started(activity_id, session)
│   ├── activity_completed(activity_id, session)
│   ├── important_event_triggered(event_id, session)
│   ├── initiative_presented(initiative)
│   └── initiative_responded(initiative_id, accepted)
│
├── 组件（复用）
│   ├── _chat: ActivityChat
│   ├── _moment_gen: MomentGenerator
│   └── _event_builder: HomeEventBuilder（类似 DateEventBuilder）
│
├── 数据
│   ├── _activity_catalog: Array[Dictionary]     ← home_activities.json
│   ├── _important_events: Array[Dictionary]     ← home_important_events.json
│   ├── _played_events: Dictionary               ← 已触发事件记录
│   ├── _initiative_pool: Array[Dictionary]      ← home_initiatives.json
│   ├── _consecutive_personal_count: int         ← 连续独处计数
│
├── 公开 API
│   ├── get_available_activities(phase) → Array[Dictionary]
│   ├── begin_activity(activity_id) → Dictionary
│   ├── evaluate_initiative() → Dictionary?
│   ├── respond_to_initiative(initiative_id, accepted) → void
│   └── get_run_state() / load_run_state()
│
└── 内部流程
    ├── _run_chat_flow(session, depth)
    ├── _run_personal_flow(session)
    ├── _run_watch_flow(session)
    ├── _run_review_flow(session)
    ├── _run_rest_flow(session)
    ├── _evaluate_important_events(session) → Dictionary?
    ├── _play_important_event(session, event_def)
    └── _apply_settlement(session)
```

### 7.2 生命周期对比

```
外出活动（ActivitySessionManager）:
  begin → departure_chat → progress_bar → AVG_scene → followup_chat → moment → settlement → AP消耗

在家活动（HomeActivityManager）:
  begin → interaction（chat_topic / choice_ui / 短消息）→ [important_event?] → moment? → settlement → AP消耗
```

在家活动没有 departure 和 progress bar，因为你已经在家了。
交互阶段根据活动类型不同而不同，但都比外出活动轻量。

### 7.3 文件结构

```
autoload/
  home_activity_manager.gd          # 主管理器

scripts/home/
  home_event_builder.gd             # Important Event 构建（复用 DateEventBuilder 模式）
  home_activity_utils.gd            # 工具函数（fallback 文本、条件评估等）

resources/data/home/
  home_activities.json              # 活动目录
  home_important_events.json        # 条件触发的 AVG 事件模板
  home_initiatives.json             # 林夏主动发起配置
  home_watch_pool.json              # 可观看内容池
  home_meal_options.json            # 饭菜选项池

scenes/home/
  home_activity_manager.tscn        # 配套场景
```

### 7.4 活动目录数据格式（home_activities.json）

```json
[
  {
    "activity_id": "chat_casual",
    "title": "和她聊聊",
    "category": "chat",
    "ap_cost": 1,
    "available_phases": ["MORNING", "AFTERNOON", "NIGHT"],
    "prerequisites": {},
    "stat_effects": {"affection": 1, "stress": -1},
    "description": "坐在沙发上随便聊点什么。",
    "moment_chance": 0.2,
    "icon_hint": "chat_bubble",
    "can_trigger_events": false
  },
  {
    "activity_id": "chat_deep",
    "title": "认真谈谈",
    "category": "chat",
    "ap_cost": 1,
    "available_phases": ["AFTERNOON", "NIGHT"],
    "prerequisites": {"min_affection": 20},
    "stat_effects": {"affection": 2, "stress": -1},
    "description": "有些话，只有坐下来才说得出口。",
    "moment_chance": 0.5,
    "icon_hint": "heart",
    "can_trigger_events": true
  },
  {
    "activity_id": "personal",
    "title": "各自忙各自的",
    "category": "personal",
    "ap_cost": 1,
    "available_phases": ["MORNING", "AFTERNOON", "NIGHT"],
    "prerequisites": {},
    "stat_effects": {"stress": -2},
    "description": "有时候，安静地待在同一个空间里就够了。",
    "moment_chance": 0.0,
    "icon_hint": "headphones",
    "can_trigger_events": false,
    "overuse_penalty": {"threshold": 3, "affection_delta": -1}
  },
  {
    "activity_id": "watch",
    "title": "一起看点什么",
    "category": "watch",
    "ap_cost": 1,
    "available_phases": ["AFTERNOON", "NIGHT"],
    "prerequisites": {},
    "stat_effects": {"affection": 1, "stress": -2},
    "description": "挑个东西一起看，让脑子休息一下。",
    "moment_chance": 0.2,
    "icon_hint": "monitor",
    "can_trigger_events": false
  },
  {
    "activity_id": "review",
    "title": "一起看看作品",
    "category": "review",
    "ap_cost": 1,
    "available_phases": ["MORNING", "AFTERNOON", "NIGHT"],
    "prerequisites": {"min_completion": 10},
    "stat_effects": {"passion": 1},
    "description": "打开项目，看看你们到底做出了什么。",
    "moment_chance": 0.0,
    "icon_hint": "code",
    "can_trigger_events": true
  },
  {
    "activity_id": "rest",
    "title": "休息",
    "category": "rest",
    "ap_cost": 1,
    "available_phases": ["MORNING", "AFTERNOON", "NIGHT"],
    "prerequisites": {},
    "stat_effects": {"stress": -3},
    "description": "今天到此为止。",
    "moment_chance": 0.0,
    "icon_hint": "moon",
    "can_trigger_events": true,
    "ends_day": true
  }
]
```

## 8. 与 GameLoopManager 的集成

### ActionType 扩展

现有 ActionType 中已有 `LIFE`，在家活动统一使用这个类型：

```gdscript
# consume_ap 调用示例
glm.consume_ap(1, "life", "chat_casual")
glm.consume_ap(1, "life", "watch")
```

### 休息的特殊处理

休息消耗 1 AP（和所有行动一样），然后跳过剩余时段推进到下一天：

```gdscript
func _run_rest_flow(session: Dictionary) -> void:
    # 正常消耗 1 AP
    glm.consume_ap(1, "life", "rest")
    # 发送睡前消息
    _send_bedtime_message(session)
    # 属性结算
    _apply_settlement(session)
    # 跳过剩余时段，直接进入下一天
    glm.advance_to_next_day()
```

在上午或下午选择休息 = 放弃剩余 1~2 个时段的行动机会。这是有代价的决策。

## 9. 设计节奏示例

一个典型的游戏日可能是这样的：

```
Day 12 — 上午
  [AP: 1/1]
  可选：工单开发 / 闲聊 / 各自忙 / 审视作品 / 一起吃饭(早餐,免费)
  → 玩家选择：工单开发（消耗 AP，推进到下午）

Day 12 — 下午
  [AP: 1/1]
  林夏主动发起："你要不要过来看一下这个？"（watch）
  → 玩家接受：一起看了一段竞争对手的 Demo（消耗 AP）
  → 讨论中 passion +1，她说"我们的比这个有意思多了"
  → 推进到晚上

Day 12 — 晚上
  [AP: 1/1]
  可选：约会 / 兼职 / SBeam / 谈心 / 闲聊 / 一起吃饭(晚餐,免费) / 休息
  → 玩家选择：谈心（消耗 AP）
  → 3 轮深度对话，解锁了林夏 lore_level 2 的一段往事
  → affection 达到 40 阈值 → 触发「第一次靠近」Important Event AVG
  → AVG 播放完毕，affection +4
  → 推进到夜间结束

  → 玩家选择：休息
  → 林夏发来睡前消息："今晚……谢谢你听我说那些。晚安。"
  → 进入 Day 13
```

## 10. 开发优先级建议

1. **P0 — 先做骨架**：HomeActivityManager + rest + chat_casual，能跑通基本流程
2. **P1 — 补全日常**：meal + personal + watch，让每天有足够的选择
3. **P2 — 深度内容**：chat_deep + review + 林夏主动发起系统
4. **P3 — 高光时刻**：Important Event（intimate / conflict / milestone）的 AVG 模板
