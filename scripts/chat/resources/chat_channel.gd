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
	var ts: int = 0
	var time_str: String = ""

	# 1. 尝试 TimeManager（连续时钟，当前已禁用）
	var time_mgr: Node = null
	if Engine.has_singleton("TimeManager"):
		time_mgr = Engine.get_singleton("TimeManager")
	elif Engine.get_main_loop() is SceneTree:
		time_mgr = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("TimeManager")
	if time_mgr:
		ts = time_mgr.get_game_timestamp()
		time_str = time_mgr.format_time()
	else:
		# 2. 使用 GameLoopManager 的阶段制时间
		var phase_time := _calc_phase_time()
		if not phase_time.is_empty():
			ts = int(phase_time["timestamp"])
			time_str = str(phase_time["time_str"])
		else:
			# 3. 终极回退（正常游戏中不应走到这里）
			ts = int(Time.get_unix_time_from_system())
			time_str = _format_time_fallback()

	var msg := {
		"sender_id": sender_id,
		"sender_name": sender_name,
		"content": content,
		"timestamp": ts,
		"time": time_str,
		"time_phase": _get_current_time_phase_display(),
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


## 根据 GameLoopManager 阶段制时间计算游戏内时间戳和 HH:MM
func _calc_phase_time() -> Dictionary:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return {}
	var glm: Node = tree.root.get_node_or_null("GameLoopManager")
	if glm == null:
		return {}
	var day: int = int(glm.get("current_day"))
	var phase: int = int(glm.get("time_phase"))
	# 阶段 → 代表性起始小时
	var base_hour: int
	match phase:
		0: base_hour = 9   # MORNING
		1: base_hour = 14  # AFTERNOON
		2: base_hour = 20  # NIGHT
		_: base_hour = 9
	# 按同阶段已有消息数递增分钟，模拟自然聊天时间流
	var phase_display: String = _get_current_time_phase_display()
	var phase_msg_count: int = 0
	for m in messages:
		if int(m.get("game_day", 0)) == day and str(m.get("time_phase", "")) == phase_display:
			phase_msg_count += 1
	@warning_ignore("integer_division")
	var minute_offset: int = mini(phase_msg_count / 2, 59)
	@warning_ignore("integer_division")
	var hour: int = base_hour + (minute_offset / 60)
	var minute: int = minute_offset % 60
	var timestamp: int = (day - 1) * 86400 + hour * 3600 + minute * 60
	var time_str: String = "%02d:%02d" % [hour, minute]
	return {"timestamp": timestamp, "time_str": time_str}


static func _get_current_game_day() -> int:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		var glm: Node = tree.root.get_node_or_null("GameLoopManager")
		if glm != null:
			return int(glm.get("current_day"))
	return 0


static func _get_current_time_phase_display() -> String:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		var glm: Node = tree.root.get_node_or_null("GameLoopManager")
		if glm != null and glm.has_method("get_phase_display_name"):
			return str(glm.call("get_phase_display_name", glm.get("time_phase")))
	return ""
