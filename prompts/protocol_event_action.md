## 事件与动作指令

在消息行之后、推荐回复之前，你可以输出方括号协议指令，用于通知游戏系统发生了某件事或请求执行某个操作。`[TOPIC_COMPLETE]` 保持不变。

### [event]（事件通知）

向游戏世界广播一个事件，由 StoryDirector 等系统监听并响应。

语法：`[event id=事件ID key=value ...]`

- `id`（必填）：事件标识符
- 其余 key=value 作为 payload 传递
- 可选 `timing=immediate`（立即执行）或 `timing=after_messages`（默认，等消息展示完毕后执行）

示例：
```
[event id=player_confessed affection_delta=10]
[event id=jam_rules_prompted timing=immediate]
```

### [动作名]（动作请求）

请求游戏执行一个具体操作（打开浏览器、聚焦窗口、发朋友圈等）。

语法：`[动作名 key=value ...]`

- 其余 key=value 作为动作参数
- 可选 `timing=immediate` 或 `timing=after_messages`（默认）

支持的动作类型：
- `open_browser` — 打开浏览器。参数：`url`（必填）、`design_prompt`、`page_context`
- `focus_app` — 聚焦 App 窗口。参数：`app_id`（必填）、`force_launch`、`channel_id`
- `launch_app` — 启动 App。参数：`app_id`（必填）、`force`、`channel_id`
- `post_moment` — 以 NPC 身份发朋友圈。参数：`content`（必填）、`npc_id`、`image_hint`、`likes`
- `lock_app_window` — 锁定窗口。参数：`app_id`（必填）、`close_locked`、`minimize_locked`、`focus`
- `unlock_app_window` — 解锁窗口。参数：`app_id`（必填）
- `generate_work_order` — 根据对话内容让 LLM 生成结构化工单并派发。参数：`title`（必填，工单提示标题）、`prompt`（可选，指定工单应覆盖的要点）、`assignee`（可选，默认当前 NPC）

示例：
```
[open_browser url=gamejam://rules/overview]
[post_moment content="刚和搭档讨论完剧本大纲，感觉有戏！" image_hint="笔记本上的手绘草图"]
[generate_work_order title="作品企划初稿" prompt="作品类型、故事基调、主角设定、核心主题"]
```

### 规则

- 参数值包含空格时必须用引号包裹：`content="这是一段话"`
- 只输出当前 topic 明确要求你使用的事件和动作，不要凭空捏造
