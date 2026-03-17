# LinkChat 聊天软件 SPEC v2

## 核心设计理念

**Topic驱动的对话系统**
- 闲置状态：玩家不能主动发起聊天
- Topic激活：特定事件触发ChatTopic，玩家才能输入
- 成本控制：只有Topic激活时才调用LLM

## 一、ChatTopic系统

### 1.1 ChatTopic资源

```gdscript
class_name ChatTopic extends Resource

@export var topic_id: String
@export var topic_type: String  # work_clarification, story_event, casual_interaction
@export var display_title: String
@export var npc_id: String
@export var channel_id: String
@export_multiline var system_prompt: String
@export var goal_description: String
@export var context_data: Dictionary = {}
@export var max_turns: int = 10
@export var timeout_seconds: int = 300
@export var on_complete_callback: String
```

### 1.2 Topic类型

| 类型 | 触发场景 | 示例 |
|------|---------|------|
| work_clarification | AI执行工单需要澄清需求 | "角色的服装风格是现代还是古风？" |
| work_report | AI完成工单，汇报结果 | "角色立绘已完成，请查看" |
| story_event | 剧情触发的对话 | "小雪邀请你参加game jam" |
| casual_interaction | NPC主动发起的日常互动 | "今天看到一只超可爱的猫" |
| relationship_event | 好感度达到阈值触发 | "小雪向你表白" |

### 1.3 Topic生命周期

```
激活 → 玩家输入 → AI回复 → 检查完成条件 → 完成/超时
```

- 激活时：发送开启消息，启用输入框
- 完成时：提取对话结果，存储记忆，执行回调
- 超时时：强制结束，记录未完成状态

## 二、消息批处理机制

### 2.1 设计理念

**问题：** 传统IM每条消息立即调用AI，成本高且不自然

**解决方案：** 批处理 + 延迟触发
1. 玩家发送消息后不立即调用AI
2. 等待10秒，期间可以继续输入
3. 10秒无变化或点击发送按钮时，整合所有消息为一次输入
4. AI返回多条消息（结构化输出）
5. UI逐条显示，根据消息长度自动计算延迟（打字机效果）

### 2.2 消息流程

```
玩家输入流程：
玩家输入 → 添加到pending_messages → 启动/重置10秒计时器
→ 超时或点击发送 → 触发batch_ready → 整合消息

AI回复流程：
构建prompt（角色+历史+记忆+Topic） → 调用AI（JSON输出）
→ 解析多条消息 → 显示"正在输入..."
→ 逐条显示（自动计算延迟） → 消息间随机间隔0.5-1.5秒
```

### 2.3 Prompt结构

**不使用传统的system/user/assistant交替，改为单次调用：**

```
system:
  # 聊天系统

  ## 当前频道角色
  {{characters_prompts}}

  ## 聊天历史（最近20条）
  {{chat_history}}

  ## 你的相关记忆（检索5条）
  {{relevant_memories}}

  ## 当前对话任务（ChatTopic）
  {{topic_prompt}}

  ## 回复要求
  1. 以{{npc_name}}的身份回复
  2. 可以发送1-3条消息
  3. 每条消息简短自然
  4. 达成目标后在最后一条消息末尾添加[TOPIC_COMPLETE]

  ## 输出格式（JSON）
  {
      "messages": ["消息1", "消息2", "消息3"],
      "typing_speed": "normal",  // fast/normal/slow
      "emotion": "neutral"
  }

user:
  玩家发送了以下消息：
  - {{message1}}
  - {{message2}}
  - {{message3}}
```

**Token优化：**
- 单次调用包含所有上下文
- 聊天历史限制20条
- 记忆限制5条
- 总消耗：约1500-2500 tokens/次

### 2.4 AI输出格式

```json
{
    "messages": [
        "好的！现代科技风格~",
        "那配色方面你有什么想法吗？",
        "我觉得蓝白色系会比较有科技感"
    ],
    "typing_speed": "normal",
    "emotion": "excited"
}
```

**注意：** 不包含delay字段，延迟由代码根据消息长度自动计算

### 2.5 打字机效果

**延迟计算逻辑：**
```
base_speed = {fast: 30, normal: 20, slow: 10} 字符/秒
char_count = 计算字符数（中文算2个字符）
delay = char_count / base_speed * random(0.8, 1.2)
delay = clamp(delay, 0.5, 5.0)
```

**显示流程：**
```
显示"正在输入..."
→ 延迟delay1 → 显示消息1
→ 随机间隔0.5-1.5秒 → 延迟delay2 → 显示消息2
→ 随机间隔0.5-1.5秒 → 延迟delay3 → 显示消息3
→ 隐藏"正在输入..."
```

## 三、UI设计

### 3.1 输入框状态

| 状态 | 条件 | 表现 |
|------|------|------|
| 可输入 | Topic激活 | 输入框可编辑，placeholder显示"输入消息（回车发送，10秒后自动触发AI回复）" |
| 禁用 | 无Topic | 输入框禁用，placeholder显示"等待对话..."，显示提示"当前没有进行中的对话" |
| 批处理中 | 有pending消息 | 显示"等待输入完成..."提示 |

### 3.2 频道列表

```
LinkChat窗口
├── 左侧边栏（200px）
│   ├── 频道列表
│   │   ├── 工作频道
│   │   │   ├── # project-gamejam (3)  # 未读数
│   │   │   └── # design-team
│   │   ├── 社交频道
│   │   │   ├── # general
│   │   │   └── # anime-club
│   │   └── 私聊
│   │       ├── 小雪 💚 (1)  # 好感度标记
│   │       └── 小林
├── 中间聊天区
│   ├── 频道标题栏
│   ├── 消息列表
│   └── 输入框 + 批处理提示
└── 右侧信息栏（可折叠）
    ├── 频道信息
    ├── 成员列表（群聊）
    └── 个人信息（私聊）
        ├── 好感度：💚💚💚🤍🤍 (60/100)
        ├── 关系：朋友
        └── 兴趣标签
```

### 3.3 Topic提示

```
新对话通知：
┌─────────────────────────────────────┐
│ 💬 新对话：关于角色设计的讨论        │
│ 小雪想和你确认一些设计细节           │
│ [开始对话]                          │
└─────────────────────────────────────┘

对话进行中：
┌─────────────────────────────────────┐
│ 🎯 当前话题：角色设计讨论            │
│ 对话轮数：3/10                      │
│ [查看目标] [结束对话]                │
└─────────────────────────────────────┘
```

## 四、Topic Prompt模板

### 4.1 工单澄清Topic

```markdown
你是{{npc_name}}，一位{{npc_role}}。

## 当前情况
你正在处理工单：{{work_order_title}}
工单内容：{{work_order_description}}

## 你的问题
{{clarification_questions}}

## 对话目标
- 向玩家清晰说明疑问
- 理解玩家的回答
- 如果不够明确，继续追问
- 确认理解后总结需求

## 对话风格
- 保持{{personality_type}}性格
- 专业但友好
- 表情符号频率：{{emoji_frequency}}

## 相关记忆
{{relevant_memories}}

## 完成标准
完全理解需求后，在回复末尾添加：[TOPIC_COMPLETE]
```

### 4.2 剧情对话Topic

```markdown
你是小雪，开朗活泼的美术设计师。

## 剧情背景
公司game jam即将开始，你想邀请玩家组队。

## 你的心情
- 兴奋：最喜欢的活动
- 期待：想和玩家一起做游戏
- 紧张：不知道会不会答应

## 你与玩家的关系
- 好感度：{{affection}}/100
- 关系阶段：{{relationship_stage}}
- 称呼：{{player_nickname}}

## 相关记忆
{{relevant_memories}}

## 对话目标
1. 介绍game jam
2. 表达组队意愿
3. 说服玩家（如果犹豫）
4. 确认决定

## 完成标准
玩家明确表示同意或拒绝后，添加：[TOPIC_COMPLETE]

## 结果变量
提取：player_decision (accept/decline), player_game_idea
```

## 五、与工单系统集成

### 5.1 request_player_input工具

**工具定义：**
```json
{
    "name": "request_player_input",
    "description": "需要玩家澄清需求或做决策时使用",
    "parameters": {
        "questions": ["问题1", "问题2"],
        "context": "问题背景",
        "urgency": "low/medium/high"
    }
}
```

**执行流程：**
```
AI调用工具 → 创建ChatTopic → 构建prompt（包含记忆检索）
→ 激活Topic → 暂停Agent执行
→ 等待Topic完成 → 提取对话结果 → 返回给Agent
```

### 5.2 Topic结果提取

使用AI分析对话，提取结构化结果：
```json
{
    "answers": {
        "问题1": "玩家的回答",
        "问题2": "玩家的回答"
    },
    "summary": "对话摘要（1-2句话）",
    "player_sentiment": "positive/neutral/negative",
    "key_points": ["要点1", "要点2"]
}
```

## 六、NPC系统

### 6.1 NPC资源

```gdscript
class_name NPCCharacter extends Resource

@export var character_id: String
@export var display_name: String
@export var avatar: Texture2D
@export var role: String
@export var department: String
@export_file("*.md") var personality_prompt_path: String
@export var work_skills: Array[String]
@export var interests: Array[String]
@export var emoji_frequency: float = 0.3
@export var initial_affection: int = 50
```

### 6.2 好感度系统

**影响因素：**
```
good_work_order: +5
chat_frequency: +2
gift: +10
praise: +5
ignore: -3
bad_work_order: -5
rude_response: -10
```

**关系阶段：**
```
stranger: 0
colleague: 30
friend: 60
close_friend: 80
romance: 90
```

**影响：**
- 对话语气和称呼
- Topic触发概率
- 剧情分支解锁

## 七、记忆系统

### 7.1 记忆层级

```
短期记忆：当前Topic的完整对话（10-20轮）
工作记忆：检索出的相关记忆（5条，发送给LLM）
长期记忆：压缩存储的历史记忆
```

### 7.2 记忆存储

**Topic结束时：**
```
提取对话摘要 → 创建MemoryEntry → 存储到长期记忆
→ 更新记忆索引 → 定期压缩旧记忆
```

**记忆条目：**
```gdscript
class MemoryEntry:
    var memory_id: String
    var npc_id: String
    var memory_type: MemoryType  # EPISODIC/SEMANTIC/EMOTIONAL
    var timestamp: int
    var content: String  # 记忆文本
    var tags: Array[String]
    var importance: float  # 0-1
    var emotional_valence: float  # -1到1
```

### 7.3 记忆检索

**检索逻辑：**
```
query = 玩家消息 + Topic目标
→ 搜索记忆索引（标签、实体匹配）
→ 计算相关性分数（文本相似度 + 记忆强度 + 最近访问）
→ 返回Top 5记忆
```

### 7.4 记忆压缩

**定期任务（每天）：**
```
筛选7天前的低重要性记忆 → 按天分组
→ 使用AI生成摘要 → 删除原始记忆，保存摘要
→ 清理30天前且强度<0.1的记忆
```

**Token优化：**
- 原始10轮对话：约2000 tokens
- 压缩后摘要：约50 tokens

## 八、实现优先级

### P0（核心）
- ChatTopic资源定义
- TopicManager（激活、完成、超时）
- MessageBatchHandler（10秒批处理）
- ChatPromptBuilder（单次调用prompt）
- NPCResponseHandler（结构化输出+打字机效果）
- 基础聊天UI
- NPC资源定义
- 记忆系统基础

### P1（集成）
- request_player_input工具
- Topic结果提取
- 剧情Topic系统
- 好感度系统
- 频道系统（私聊/群聊）
- 记忆检索与压缩

### P2（增强）
- 群聊Topic（多NPC参与）
- Topic历史查看
- 关系阶段影响对话
- NPC主动发起casual_interaction
- 长期记忆管理

## 九、技术集成点

**DeepCode工单系统 → LinkChat：**
- 工单创建 → 发送通知到项目群
- AI需要clarification → 通过LinkChat发起对话
- 工单完成 → 发送结果到频道

**AVG引擎 → LinkChat：**
- 剧情通过LinkChat对话推进
- 好感度影响AVG剧情分支
- LinkChat对话触发AVG场景

**StorageManager：**
- 聊天记录、好感度、记忆数据统一管理
- 使用`user://`路径持久化
