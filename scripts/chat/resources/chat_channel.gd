class_name ChatChannel extends Resource
## 聊天频道资源
## 支持工作频道、社交频道、私聊

enum ChannelType {
	WORK, ## 工作频道（项目组、部门群）
	SOCIAL, ## 社交频道（全体员工、兴趣小组）
	DM, ## 私聊
	SYSTEM, ## 系统通知
}

## 频道唯一标识
@export var channel_id: String = ""

## 频道显示名称
@export var display_name: String = ""

## 频道的环境与背景人设（用于群聊的大模型上下文）
@export_multiline var channel_prompt: String = ""

## 频道类型
@export var channel_type: ChannelType = ChannelType.SOCIAL

## 频道成员ID列表
@export var members: Array[String] = []

## 频道图标
@export var icon: Texture2D

## 是否置顶
@export var pinned: bool = false

## 未读消息数
var unread_count: int = 0

## 消息历史
var messages: Array[Dictionary] = []


## 添加消息
func add_message(sender_id: String, sender_name: String, content: String, extras: Dictionary = {}) -> Dictionary:
	var time_mgr: Node = Engine.get_singleton("TimeManager") if Engine.has_singleton("TimeManager") else null
	var ts: int = 0
	var time_str: String = ""
	if time_mgr:
		ts = time_mgr.get_game_timestamp()
		time_str = time_mgr.format_time()
	else:
		# fallback: 从 autoload 获取
		var tm: Node = null
		if Engine.get_main_loop():
			tm = Engine.get_main_loop().root.get_node_or_null("TimeManager")
		if tm:
			ts = tm.get_game_timestamp()
			time_str = tm.format_time()
		else:
			ts = int(Time.get_unix_time_from_system())
			time_str = _format_time_fallback()

	var msg := {
		"sender_id": sender_id,
		"sender_name": sender_name,
		"content": content,
		"timestamp": ts,
		"time": time_str,
		"game_day": _get_current_game_day(),
	}
	for key in extras:
		msg[key] = extras[key]
	messages.append(msg)
	return msg


## 获取最近N条消息
func get_recent_messages(count: int = 20) -> Array[Dictionary]:
	if messages.size() <= count:
		return messages.duplicate()
	return messages.slice(messages.size() - count)


func _format_time_fallback() -> String:
	var dt := Time.get_datetime_dict_from_system()
	return "%02d:%02d" % [dt.hour, dt.minute]


static func _get_current_game_day() -> int:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		var glm: Node = tree.root.get_node_or_null("GameLoopManager")
		if glm != null:
			return int(glm.get("current_day"))
	return 0
