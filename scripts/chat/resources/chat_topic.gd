class_name ChatTopic extends Resource
## 一段可执行的聊天剧本。LOCAL 与 LLM 文本彼此独立，切换模式不会丢失原文。

enum Mode {
	LOCAL,
	LLM,
}

@export var topic_id: String = ""
@export var channel_id: String = ""
@export var mode: Mode = Mode.LOCAL
## 自动消息由 TopicManager 推进，窗口仅负责展示与点击加速。
@export var auto_advance: bool = true
@export_range(0.1, 10.0, 0.1) var min_advance_delay: float = 1.2
@export_range(0.0, 0.2, 0.01) var advance_char_seconds: float = 0.06
@export_range(0.5, 20.0, 0.5) var max_advance_delay: float = 6.0

## 作者直接编写的完整 Chat DSL，仅在 LOCAL 模式执行。
@export_multiline var local_script: String = ""

## 交给 PromptManager 装配的创作要求，仅在 LLM 模式使用。
@export_multiline var prompt: String = ""
