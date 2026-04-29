class_name ChatTopic extends Resource
## 聊天话题资源
## Topic驱动的对话系统核心：只有激活Topic时玩家才能输入

## Topic唯一标识
@export var topic_id: String = ""

## Topic类型：work_clarification, work_report, story_event, casual_interaction, relationship_event, tutorial
@export var topic_type: String = ""

## 显示标题
@export var display_title: String = ""

## 参与的NPC ID
@export var npc_id: String = ""

## 所在频道ID
@export var channel_id: String = ""

## AI行为指令（system prompt的一部分）
@export_multiline var system_prompt: String = ""

## 对话目标描述
@export_multiline var goal_description: String = ""

## 上下文数据（工单内容、剧情变量等）
@export var context_data: Dictionary = {}

## 已停用：保留字段仅为兼容旧数据
@export var max_turns: int = 0

## 超时时间（秒，0=无限制）
@export var timeout_seconds: int = 300

## 完成后的回调函数名
@export var on_complete_callback: String = ""

## 结果变量
@export var result_variables: Dictionary = {}

## 运行时数据（不导出）
var turn_count: int = 0
var start_time: int = 0
var is_active: bool = false
