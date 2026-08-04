class_name ChatTopic extends Resource
## 一段可执行的聊天剧本。LOCAL 与 LLM 文本彼此独立，切换模式不会丢失原文。

enum Mode {
	LOCAL,
	LLM,
}

@export var topic_id: String = ""
@export var channel_id: String = ""
@export var mode: Mode = Mode.LOCAL

## 作者直接编写的完整 Chat DSL，仅在 LOCAL 模式执行。
@export_multiline var local_script: String = ""

## 交给 PromptManager 装配的创作要求，仅在 LLM 模式使用。
@export_multiline var prompt: String = ""
