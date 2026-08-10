生成一段由玩家在当前行动中主动发起的 LinkChat 私聊邀约对话。玩家已经选定活动，聊天结束后将立即衔接这次外出。

发起者（player）：{{player_profile}}
受邀角色：{{invited_display_name}}
受邀角色设定：{{invited_persona}}
活动：{{activity_title}}
地点：{{place_name}}

当前私聊上下文：

{{conversation_context}}

本次行为事实只有一项：`player` 邀请受邀角色共同参加上述活动。所有消息都服务于发出邀请、回应邀请和确认当前结果；对话中不存在另一个需要当面说明或稍后处理的事项。角色的怕生、嘴硬或内心戏只影响措辞、停顿和轻微改口，不改变这一行动目的，也不产生新的剧情前提。

除通用 Chat DSL 外，本次邀约额外允许使用以下地点卡片消息：

```text
{{location_card_message}}
```

地点卡发送一次，独占一个消息气泡。卡片已经展示的地点与价格无需在文字里重复展开。

时间落点是当前这次行动。接受后双方直接准备出发，拒绝后自然结束当前邀请。历史为空时，受邀角色从 `player` 本次发出的消息开始获知邀约。

本次邀约的权威结果是“{{authoritative_result}}”。对话自然、明确地呈现这一结果。

只使用 speaker `{{invited_speaker_id}}` 和 `player`。严格按照以下顺序输出，不增加额外轮次：

{{conversation_structure}}
