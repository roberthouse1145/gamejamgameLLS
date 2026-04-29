# LinkChat 功能实现报告

## 1. 系统概述

LinkChat 是一个 Topic 驱动的 NPC 聊天系统，集成 LLM API（DeepSeek）实现 AI 对话。核心设计原则：**只有激活 Topic 时玩家才能输入**。

### 架构图

```
ChatManager (autoload, 数据层)
├── TopicManager        — Topic 生命周期管理
├── MessageBatchHandler — 玩家消息批处理（10秒窗口）
├── MemoryManager       — NPC 记忆存储/检索
├── AIService           — LLM API 调用
└── NPCManager          — NPC 角色注册表（纯数据）

LinkChatApp (UI层, Control)
├── NPCResponseHandler  — 打字机效果（纯 UI 动画）
└── 频道列表/消息列表/输入框 — UI 渲染
```

---

## 2. 新增文件清单

| 文件路径 | 类型 | 职责 |
|---------|------|------|
| `scripts/apps/linkchat/linkchat_app.gd` | 主控制器 | 频道管理、UI 绑定、信号路由 |
| `scenes/apps/linkchat/linkchat_app.tscn` | 场景 | UI 布局（侧边栏+聊天区+输入区） |
| `scripts/chat/topic_manager.gd` | 子系统 | Topic 激活/完成/超时 |
| `scripts/chat/message_batch_handler.gd` | 子系统 | 消息批处理 |
| `scripts/chat/npc_response_handler.gd` | 子系统 | 打字机效果 |
| `scripts/chat/memory_manager.gd` | 子系统 | 记忆管理 |
| `scripts/chat/chat_prompt_builder.gd` | 工具类 | Prompt 构建 |
| `scripts/chat/npc_manager.gd` | 工具类 | NPC 注册表 |
| `scripts/chat/resources/chat_channel.gd` | Resource | 频道数据模型 |
| `scripts/chat/resources/npc_character.gd` | Resource | NPC 角色数据模型 |
| `scripts/chat/resources/chat_topic.gd` | Resource | Topic 数据模型 |
| `scripts/llm/AIService.gd` | 服务 | HTTP LLM API 封装 |
| `scripts/llm/ai_config_manager.gd` | 配置 | AI 配置加载 |
| `prompts/npc/xiaoxue.md` | Prompt | 小雪人设 |
| `ai_config.cfg` | 配置 | API profiles + role 映射 |
| `resources/apps/linkchat_app.tres` | Resource | App 注册资源 |
| `tests/test_linkchat.gd` | 测试 | LLM 端到端测试 |
| `tests/test_linkchat.tscn` | 测试场景 | 测试入口 |

---

## 3. 核心逻辑详解

### 3.1 消息处理流水线

```
玩家输入 → BatchHandler(10s窗口) → ChatPromptBuilder → AIService → ResponseHandler → UI显示
```

**关键流程** (`linkchat_app.gd`):

1. `_on_text_submitted()` — 玩家按回车，消息进入 `batch_handler` 并立即显示在 UI
2. `_on_batch_ready(messages)` — 10 秒内的消息合并为一批，触发 AI 调用
3. `_on_ai_request_completed()` — 解析 AI JSON 回复，交给 `response_handler` 做打字机效果
4. `_on_npc_message_displayed()` — 每条 NPC 消息显示完毕后写入频道历史

### 3.2 Topic 系统 (`topic_manager.gd`)

Topic 是对话的最小单元，控制"谁在哪个频道聊什么"。

```gdscript
# ChatTopic 关键字段
topic_id: String          # 唯一ID
topic_type: String        # casual_interaction / work_task / ...
npc_id: String            # 对话NPC
channel_id: String        # 所属频道
system_prompt: String     # LLM system prompt
max_turns: int            # 已停用，保留仅为兼容旧数据
turn_count: int           # 当前轮数
```

生命周期：`activate_topic()` → `increment_turn()` → `complete_topic()` 或 `timeout_topic()`

信号：`topic_activated` / `topic_completed` / `topic_timeout`

**输入状态联动**：只有当前频道有 active topic 且不在等待 AI 回复时，输入框才可编辑 (`_update_input_state()`)。

### 3.3 消息批处理 (`message_batch_handler.gd`)

解决"玩家连续发多条消息"的问题。玩家每次输入重置 10 秒计时器，超时后将所有消息合并为 `Array[String]` 一次性发给 AI。

```
玩家: "你好"          → 计时器开始(10s)
玩家: "你是做什么的"   → 计时器重置(10s)
[10秒后]              → batch_ready.emit(["你好", "你是做什么的"])
```

点击"发送"按钮会调用 `force_send()` 立即触发。

### 3.4 Prompt 构建 (`chat_prompt_builder.gd`)

静态方法 `ChatPromptBuilder.build()` 组装 LLM 请求：

```gdscript
static func build(topic, npc, chat_history, player_messages, memories) -> Dictionary:
    # 返回 { "messages": [{ "role": "system", "content": ... }, { "role": "user", "content": ... }] }
```

System prompt 包含：
- Topic 的 `system_prompt`（含 NPC 人设）
- NPC 元数据（角色、部门、技能、兴趣）
- 相关记忆片段
- JSON 输出格式要求

User prompt 包含：
- 最近 20 条聊天历史
- 本轮玩家消息

**期望 AI 返回格式**：
```json
{
    "messages": ["消息1", "消息2"],
    "typing_speed": "normal",
    "emotion": "happy",
    "topic_complete": false
}
```

### 3.5 AI 回复处理 (`npc_response_handler.gd`)

收到 AI JSON 后：
1. 解析 `messages` 数组（支持多条回复）
2. 按 `typing_speed` 计算延迟（fast/normal/slow）
3. 逐条触发 `typing_started` → 延迟 → `message_displayed` → `typing_ended`
4. 检查 `topic_complete` 字段决定是否结束 Topic

非 JSON 回复降级为单条消息处理。

### 3.6 记忆系统 (`memory_manager.gd`)

简单的内存记忆存储：
- `store_topic_memory(topic_id, npc_id, summary)` — Topic 结束时存储摘要
- `retrieve_memories(npc_id, query, limit)` — 检索相关记忆（当前为按时间倒序，无语义搜索）

记忆在 prompt 构建时注入 system prompt，让 NPC "记住"之前的对话。

### 3.7 频道系统

4 种频道类型：

| 类型 | 用途 | 示例 |
|------|------|------|
| WORK | 工作讨论 | # 项目组、# 美术组 |
| SOCIAL | 闲聊 | # 全体员工 |
| DM | 私聊 | 小雪 |
| SYSTEM | 系统通知 | 通知中心 |

每个频道维护独立的消息历史和未读计数。频道切换时刷新消息显示并更新输入状态。

### 3.8 NPC 数据模型 (`npc_character.gd`)

```gdscript
character_id: String              # "npc_xiaoxue"
display_name: String              # "小雪"
role: String                      # "美术设计师"
department: String                # "art-team"
personality_prompt_path: String   # "res://prompts/npc/xiaoxue.md"
work_skills: Array[String]        # ["角色设计", "UI设计", "像素画"]
interests: Array[String]          # ["动漫", "猫咪", "甜点"]
emoji_frequency: float            # 0.4
initial_affection: int            # 55
```

### 3.9 AI 配置 (`ai_config.cfg` + `ai_config_manager.gd`)

```ini
[profiles/deepseek_chat]
base_url="https://api.deepseek.com"
api_key="sk-..."
model="deepseek-chat"

[roles]
linkchat="deepseek_chat"
```

`AIConfigManager.load_config()` 解析 ConfigFile，`apply_to_service()` 按 role 名查找 profile 并配置 AIService。

---

## 4. 测试方案

`tests/test_linkchat.gd` 直接实例化 LinkChat 场景（绕过 AppManager/WindowManager），自动激活一个与小雪的闲聊 Topic。

运行方式：Godot 编辑器中运行 `res://tests/test_linkchat.tscn`

验证结果：
- AIConfigManager 正确加载 `linkchat` → `deepseek_chat` profile
- Topic 激活成功，输入框可编辑
- 玩家输入 → 批处理 → Prompt 构建 → DeepSeek API 调用 → JSON 解析 → 打字机显示
- 全链路零错误

---

## 5. 需要 Review 关注的点

1. **`npc_manager` 无类型注解** (`linkchat_app.gd:28`) — 因为 NPCManager 是 preload 的脚本而非全局 class_name，用了 `var npc_manager` 无类型声明。所有 `:=` 推断依赖此变量的地方需要注意。

2. **记忆系统是纯内存的** — `MemoryManager` 没有持久化，重启后记忆丢失。后续需要加文件/数据库存储。

3. **批处理窗口 10 秒** — 这个值是硬编码的，可能需要根据实际体验调整。

4. **AI 回复容错** — `_on_ai_request_completed()` 对非 JSON 回复做了降级处理，但没有对 JSON schema 做严格校验。

5. **频道成员权限** — 当前 `members` 字段只用于显示，没有实际的权限控制逻辑。

6. **`_add_channel` 的 `members` 参数** (`linkchat_app.gd:142`) — 使用 `Array[String]` 类型，字面量赋值需要 `.assign()` 避免类型不匹配。
