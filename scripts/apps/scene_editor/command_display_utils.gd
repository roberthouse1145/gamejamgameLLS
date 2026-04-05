class_name CommandDisplayUtils extends RefCounted
## 命令显示工具类 — 纯静态函数，供场景编辑器各组件共用
## 包含：命令类型定义、显示文本生成、默认参数初始化、变量名解析、条件摘要

## 命令分类定义（有序，决定 Tab 顺序）
const COMMAND_CATEGORIES: Array[String] = [
	"对话", "角色", "流程", "变量", "音频", "画面", "镜头", "节点",
]

## 命令类型定义（含分类）
const COMMAND_TYPES: Array = [
	# 对话
	{"id": "DIALOGUE", "name": "对话", "category": "对话"},
	{"id": "CLEAR_DIALOGUE", "name": "清除对话", "category": "对话"},
	{"id": "SET_TEXT_SPEED", "name": "文字速度", "category": "对话"},
	# 角色
	{"id": "SHOW_CHARACTER", "name": "显示角色", "category": "角色"},
	{"id": "HIDE_CHARACTER", "name": "隐藏角色", "category": "角色"},
	{"id": "STAGE_SET", "name": "舞台排位", "category": "角色"},
	{"id": "STAGE_ENTER", "name": "舞台入场", "category": "角色"},
	{"id": "STAGE_EXIT", "name": "舞台离场", "category": "角色"},
	{"id": "CHANGE_EXPRESSION", "name": "切换表情", "category": "角色"},
	{"id": "MOVE_CHARACTER", "name": "移动角色", "category": "角色"},
	{"id": "MOVE_CHARACTER_BY", "name": "相对移动", "category": "角色"},
	{"id": "FLIP_CHARACTER", "name": "翻转角色", "category": "角色"},
	{"id": "CHARACTER_EFFECT", "name": "角色特效", "category": "角色"},
	{"id": "SET_CHARACTER_PROPERTY", "name": "角色属性", "category": "角色"},
	# 流程
	{"id": "CHOICE", "name": "选项", "category": "流程"},
	{"id": "IF", "name": "条件分支", "category": "流程"},
	{"id": "LABEL", "name": "标签", "category": "流程"},
	{"id": "JUMP_LABEL", "name": "跳转标签", "category": "流程"},
	{"id": "JUMP_SCENE", "name": "跳转场景", "category": "流程"},
	{"id": "CALL_EVENT", "name": "调用事件", "category": "流程"},
	{"id": "WAIT_CLICK", "name": "等待点击", "category": "流程"},
	{"id": "WAIT_TIME", "name": "等待时间", "category": "流程"},
	# 变量
	{"id": "SET_VARIABLE", "name": "设置变量", "category": "变量"},
	# 音频
	{"id": "PLAY_BGM", "name": "播放BGM", "category": "音频"},
	{"id": "STOP_BGM", "name": "停止BGM", "category": "音频"},
	{"id": "PLAY_SFX", "name": "播放音效", "category": "音频"},
	# 画面
	{"id": "CHANGE_BACKGROUND", "name": "切换背景", "category": "画面"},
	{"id": "SHOW_IMAGE", "name": "显示图片", "category": "画面"},
	{"id": "HIDE_IMAGE", "name": "隐藏图片", "category": "画面"},
	{"id": "SCREEN_FADE", "name": "屏幕淡入淡出", "category": "画面"},
	{"id": "SCREEN_FLASH", "name": "屏幕闪烁", "category": "画面"},
	{"id": "SCREEN_SHAKE", "name": "屏幕震动", "category": "画面"},
	{"id": "SHOW_NOTIFICATION", "name": "通知", "category": "画面"},
	{"id": "SET_HUD_VISIBLE", "name": "显隐HUD", "category": "画面"},
	# 镜头
	{"id": "CAMERA_ZOOM", "name": "镜头缩放", "category": "镜头"},
	{"id": "CAMERA_PAN", "name": "镜头平移", "category": "镜头"},
	{"id": "CAMERA_RESET", "name": "镜头重置", "category": "镜头"},
	# 节点
	{"id": "SPAWN_NODE", "name": "生成节点", "category": "节点"},
	{"id": "SET_TEXT", "name": "设置文本", "category": "节点"},
	{"id": "SET_STYLE", "name": "设置样式", "category": "节点"},
	{"id": "MOVE_NODE", "name": "移动节点", "category": "节点"},
	{"id": "RESIZE_NODE", "name": "调整大小", "category": "节点"},
	{"id": "SHOW_NODE", "name": "显示节点", "category": "节点"},
	{"id": "HIDE_NODE", "name": "隐藏节点", "category": "节点"},
	{"id": "REMOVE_NODE", "name": "移除节点", "category": "节点"},
]

## 条件运算符列表
const CONDITION_OPERATORS: Array[String] = ["==", "!=", ">", ">=", "<", "<="]


static func _format_decimal_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%.0f" % value
	return "%.1f" % value


static func _format_screen_shake_intensity(value: Variant) -> String:
	if value is int or value is float:
		return _format_decimal_number(float(value))

	if value is String:
		var text: String = value.strip_edges()
		if text.is_empty():
			return "10"
		if text.is_valid_int() or text.is_valid_float():
			return _format_decimal_number(text.to_float())
		return text

	return str(value)


static func _extract_stage_characters(params: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var raw_characters: Variant = params.get("characters", [])
	if raw_characters is Array:
		for entry in raw_characters:
			var trimmed: String = str(entry).strip_edges()
			if trimmed.is_empty():
				continue
			result.append(trimmed)
		if not result.is_empty():
			return result

	var raw_csv: String = str(params.get("characters_csv", "")).strip_edges()
	if raw_csv.is_empty():
		return result
	for entry in raw_csv.split(","):
		var trimmed_csv: String = entry.strip_edges()
		if trimmed_csv.is_empty():
			continue
		result.append(trimmed_csv)
	return result


## 解析变量显示名称：优先用 variable_id 查找名称，显示为 "ID(名称)" 格式
static func resolve_variable_display(var_id: String, var_name: String) -> String:
	var project: Resource = StorageManager.current_project
	if project == null or not "variables" in project:
		if not var_id.is_empty():
			return var_id
		return var_name if not var_name.is_empty() else "?"

	if not var_id.is_empty():
		for v in project.variables:
			if v.variable_id == var_id:
				return "%s(%s)" % [var_id, v.variable_name]
		return "%s(?)" % var_id

	if not var_name.is_empty():
		for v in project.variables:
			if v.variable_name == var_name:
				var vid: String = v.variable_id if "variable_id" in v else ""
				if not vid.is_empty():
					return "%s(%s)" % [vid, var_name]
				return var_name
		return var_name

	return "?"


## 获取条件命令列表的摘要文本
static func get_condition_summary(commands: Array) -> String:
	if commands.is_empty():
		return "无"

	var parts: Array[String] = []
	for cmd in commands:
		if cmd == null:
			continue
		var cmd_type: String = cmd.command_type if cmd is Resource and "command_type" in cmd else ""
		if cmd_type == "CHECK_VAR":
			var var_id: String = cmd.params.get("variable_id", "") if cmd.params else ""
			var vn: String = cmd.params.get("variable_name", "?") if cmd.params else "?"
			var display_name: String = resolve_variable_display(var_id, vn)
			var op: String = cmd.params.get("operator", ">=") if cmd.params else ">="
			var val = cmd.params.get("value", "0") if cmd.params else "0"
			parts.append("%s%s%s" % [display_name, op, str(val)])
		elif cmd_type == "CHECK_HOVER":
			var nid: String = cmd.params.get("node_id", "") if cmd.params else ""
			parts.append("悬停(%s)" % nid if not nid.is_empty() else "悬停(自身)")
		elif cmd_type == "CHECK_CLICK":
			var nid2: String = cmd.params.get("node_id", "") if cmd.params else ""
			parts.append("点击(%s)" % nid2 if not nid2.is_empty() else "点击(自身)")
		elif cmd_type == "IF":
			parts.append("IF(...)")

	return " & ".join(parts) if not parts.is_empty() else "无"


## 获取命令的显示文本
## 兼容 AVGCommand (Resource) 和 Dictionary 两种格式
static func get_command_display(cmd: Variant) -> String:
	if cmd == null:
		return "unknown"

	var cmd_type: String
	var params: Dictionary
	if cmd is Dictionary:
		cmd_type = cmd.get("command_type", "unknown")
		params = cmd.get("params", {})
	else:
		cmd_type = cmd.command_type
		params = cmd.params

	match cmd_type:
		"DIALOGUE":
			var speaker: String = params.get("speaker", "")
			var text: String = params.get("text", "")
			if text.length() > 20:
				text = text.substr(0, 20) + "..."
			if speaker.is_empty():
				return "旁白 \"%s\"" % text
			return "对话 %s: \"%s\"" % [speaker, text]
		"SHOW_CHARACTER":
			var char_id: String = params.get("character_id", "")
			var expression: String = params.get("emotion", params.get("expression", ""))
			var flip_str: String = " 翻转" if params.get("flip", false) else ""
			return "显示角色 %s %s%s" % [char_id, expression, flip_str]
		"HIDE_CHARACTER":
			return "隐藏角色 %s" % params.get("character_id", "")
		"STAGE_SET":
			var stage_characters: Array[String] = _extract_stage_characters(params)
			if stage_characters.is_empty():
				return "舞台清场"
			return "舞台排位 [%s]" % " / ".join(PackedStringArray(stage_characters))
		"STAGE_ENTER":
			var entering_characters: Array[String] = _extract_stage_characters(params)
			return "舞台入场 [%s]" % " / ".join(PackedStringArray(entering_characters))
		"STAGE_EXIT":
			var exiting_characters: Array[String] = _extract_stage_characters(params)
			return "舞台离场 [%s]" % " / ".join(PackedStringArray(exiting_characters))
		"CHANGE_EXPRESSION":
			var char_id: String = params.get("character_id", "")
			var expr: String = params.get("expression", "")
			var trans: String = params.get("transition", "")
			var trans_str: String = " (%s)" % trans if not trans.is_empty() else ""
			return "切换表情 %s -> %s%s" % [char_id, expr, trans_str]
		"MOVE_CHARACTER":
			var char_id: String = params.get("character_id", "")
			var target: String = params.get("target", "center")
			var dur: float = params.get("duration", 0.3)
			return "移动角色 %s -> %s (%.1fs)" % [char_id, target, dur]
		"MOVE_CHARACTER_BY":
			var char_id: String = params.get("character_id", "")
			var ox: float = params.get("offset_x", 0.0)
			var oy: float = params.get("offset_y", 0.0)
			return "相对移动 %s (%.2f, %.2f)" % [char_id, ox, oy]
		"FLIP_CHARACTER":
			var char_id: String = params.get("character_id", "")
			var flip_mode: String = params.get("flip", "toggle")
			return "翻转角色 %s [%s]" % [char_id, flip_mode]
		"CHARACTER_EFFECT":
			var char_id: String = params.get("character_id", "")
			var effect: String = params.get("effect", "jump")
			var intensity: String = params.get("intensity", "medium")
			return "角色特效 %s %s(%s)" % [char_id, effect, intensity]
		"SET_CHARACTER_PROPERTY":
			var char_id: String = params.get("character_id", "")
			var prop: String = params.get("property", "opacity")
			var val: String = str(params.get("value", "1.0"))
			return "角色属性 %s %s=%s" % [char_id, prop, val]
		"WAIT_CLICK":
			return "等待点击"
		"WAIT_TIME":
			return "等待 %.1f秒" % params.get("duration", 1.0)
		"CHOICE":
			var choices: Array = params.get("choices", [])
			var choice_texts: Array[String] = []
			for c in choices:
				if c is Dictionary:
					var ct: String = c.get("text", "")
					if ct.length() > 8:
						ct = ct.substr(0, 8) + ".."
					choice_texts.append(ct)
			if choice_texts.is_empty():
				return "选项 (%d个)" % choices.size()
			return "选项 [%s]" % "/".join(choice_texts)
		"LABEL":
			return "标签 [%s]" % params.get("name", "")
		"JUMP_LABEL":
			return "跳转标签 %s" % params.get("target", "")
		"JUMP_SCENE":
			var sid: String = params.get("scene_id", "")
			var trans: String = params.get("transition", "")
			if trans.is_empty():
				return "跳转场景 %s" % sid
			var dur: float = params.get("duration", 1.0)
			return "跳转场景 %s [%s %.1fs]" % [sid, trans, dur]
		"SET_VARIABLE":
			var var_id: String = params.get("variable_id", "")
			var var_name: String = params.get("variable_name", "")
			var display_name: String = resolve_variable_display(var_id, var_name)
			var value = params.get("value", "")
			var operation: String = params.get("operation", "set")
			return "设置变量 %s %s %s" % [display_name, operation, str(value)]
		"CALL_EVENT":
			return "调用事件 %s" % params.get("event_id", "")
		"PLAY_BGM":
			return "播放BGM %s" % params.get("audio_path", "")
		"STOP_BGM":
			return "停止BGM"
		"PLAY_SFX":
			return "播放音效 %s" % params.get("audio_path", "")
		"CHANGE_BACKGROUND":
			var trans: String = params.get("transition", "fade")
			var dur: float = params.get("fade_duration", 0.5)
			if trans == "fade" or trans.is_empty():
				return "切换背景 %.1fs" % dur
			return "切换背景 %.1fs [%s]" % [dur, trans]
		"IF":
			var cond_cmds: Array = params.get("condition_commands", [])
			if not cond_cmds.is_empty():
				return "如果 [%s]" % get_condition_summary(cond_cmds)
			return "如果 [%s]" % params.get("condition", "")
		"CHECK_VAR":
			var var_id: String = params.get("variable_id", "")
			var vn: String = params.get("variable_name", "?")
			var display_name: String = resolve_variable_display(var_id, vn)
			var op: String = params.get("operator", ">=")
			var val = params.get("value", "0")
			return "%s %s %s" % [display_name, op, str(val)]
		"SCREEN_FADE":
			var dir: String = params.get("direction", "out")
			var dur: float = params.get("duration", 1.0)
			var trans: String = params.get("transition", "fade")
			var dir_text: String = "淡出" if dir == "out" else "淡入"
			if trans == "fade" or trans.is_empty():
				return "屏幕%s %.1fs" % [dir_text, dur]
			return "屏幕%s %.1fs [%s]" % [dir_text, dur, trans]
		"SCREEN_FLASH":
			return "屏幕闪烁 %.1fs" % params.get("duration", 0.3)
		"SCREEN_SHAKE":
			var dur: float = params.get("duration", 0.5)
			var intensity_text: String = _format_screen_shake_intensity(params.get("intensity", 10.0))
			return "屏幕震动 %s %.1fs" % [intensity_text, dur]
		"SHOW_IMAGE":
			return "显示图片 %s" % params.get("image_id", "")
		"HIDE_IMAGE":
			return "隐藏图片 %s" % params.get("image_id", "")
		"SET_TEXT_SPEED":
			return "文字速度 %.3f" % params.get("speed", 0.03)
		"CLEAR_DIALOGUE":
			return "清除对话"
		"SHOW_NOTIFICATION":
			var ntf_text: String = params.get("text", "")
			if ntf_text.length() > 15:
				ntf_text = ntf_text.substr(0, 15) + "..."
			return "通知 \"%s\"" % ntf_text
		"SET_NODE_PROPERTY":
			# Legacy — should not appear, but handle gracefully
			return "节点属性(旧) %s" % params.get("node_id", "")
		"SET_TEXT":
			var nid: String = params.get("node_id", "")
			var txt: String = params.get("text", "")
			if txt.length() > 15:
				txt = txt.substr(0, 15) + ".."
			var target: String = nid if not nid.is_empty() else "自身"
			return "设置文本 [%s] \"%s\"" % [target, txt]
		"SET_STYLE":
			var nid2: String = params.get("node_id", "")
			var bg: String = params.get("bg_color", "")
			var target2: String = nid2 if not nid2.is_empty() else "自身"
			return "设置样式 [%s] bg=%s" % [target2, bg]
		"MOVE_NODE":
			var nid3: String = params.get("node_id", "")
			var nx: float = params.get("norm_x", 0.0)
			var ny: float = params.get("norm_y", 0.0)
			var dur: float = params.get("duration", 0.3)
			var target3: String = nid3 if not nid3.is_empty() else "自身"
			return "移动节点 [%s] (%.2f,%.2f) %.1fs" % [target3, nx, ny, dur]
		"RESIZE_NODE":
			var nid4: String = params.get("node_id", "")
			var nw: float = params.get("norm_w", 0.1)
			var nh: float = params.get("norm_h", 0.1)
			var target4: String = nid4 if not nid4.is_empty() else "自身"
			return "调整大小 [%s] (%.2f,%.2f)" % [target4, nw, nh]
		"SHOW_NODE":
			var nid5: String = params.get("node_id", "")
			var fd: float = params.get("fade_duration", 0.0)
			var target5: String = nid5 if not nid5.is_empty() else "自身"
			return "显示节点 [%s] %.1fs" % [target5, fd]
		"HIDE_NODE":
			var nid6: String = params.get("node_id", "")
			var fd2: float = params.get("fade_duration", 0.0)
			var target6: String = nid6 if not nid6.is_empty() else "自身"
			return "隐藏节点 [%s] %.1fs" % [target6, fd2]
		"REMOVE_NODE":
			var nid7: String = params.get("node_id", "")
			var target7: String = nid7 if not nid7.is_empty() else "自身"
			return "移除节点 [%s]" % target7
		"SPAWN_NODE":
			var sid: String = params.get("shared_node_id", "")
			var iid: String = params.get("instance_id", "")
			var id_str: String = iid if not iid.is_empty() else "auto"
			return "生成节点 %s -> %s" % [sid, id_str]
		"SET_HUD_VISIBLE":
			var vis: bool = params.get("visible", true)
			return "显示HUD" if vis else "隐藏HUD"
		"CHECK_HOVER":
			var nid2: String = params.get("node_id", "")
			if nid2.is_empty():
				return "悬停检测 (自身)"
			return "悬停检测 %s" % nid2
		"CHECK_CLICK":
			var nid3: String = params.get("node_id", "")
			if nid3.is_empty():
				return "点击检测 (自身)"
			return "点击检测 %s" % nid3
		"CAMERA_ZOOM":
			var zm: float = params.get("zoom", 1.5)
			var focus_target: String = str(params.get("focus", ""))
			var dur: float = params.get("duration", 1.0)
			if not focus_target.is_empty():
				return "镜头缩放 x%.1f →%s %.1fs" % [zm, focus_target, dur]
			var fx: float = params.get("focus_x", 0.5)
			var fy: float = params.get("focus_y", 0.5)
			if params.has("focus_x") or params.has("focus_y"):
				return "镜头缩放 x%.1f (%.2f,%.2f) %.1fs" % [zm, fx, fy, dur]
			return "镜头缩放 x%.1f (自动) %.1fs" % [zm, dur]
		"CAMERA_PAN":
			var pan_target: String = str(params.get("target", ""))
			var dur2: float = params.get("duration", 1.0)
			if not pan_target.is_empty():
				return "镜头平移 %s %.1fs" % [pan_target, dur2]
			var px: float = params.get("norm_x", 0.0)
			var py: float = params.get("norm_y", 0.0)
			return "镜头平移 (%.2f,%.2f) %.1fs" % [px, py, dur2]
		"CAMERA_RESET":
			var dur3: float = params.get("duration", 1.0)
			return "镜头重置 %.1fs" % dur3
		_:
			return cmd_type


## 初始化命令的默认参数
static func init_command_params(cmd: Resource) -> void:
	match cmd.command_type:
		"DIALOGUE":
			cmd.params = {"text": "", "speaker": "", "emotion": "", "text_speed": -1.0, "position": "default", "transparent": false}
		"SHOW_CHARACTER":
			cmd.params = {"character_id": "", "position": "center", "custom_x": 0.5, "custom_y": 0.5, "emotion": "", "fade_duration": 0.3, "flip": false, "scale": 1.0, "opacity": 1.0}
		"HIDE_CHARACTER":
			cmd.params = {"character_id": "", "fade_duration": 0.3}
		"STAGE_SET":
			cmd.params = {"characters_csv": "", "emotions": "", "outfits": "", "duration": 0.35, "enter_effect": "fade", "exit_effect": "fade"}
		"STAGE_ENTER":
			cmd.params = {"characters_csv": "", "emotions": "", "outfits": "", "duration": 0.35, "enter_effect": "fade"}
		"STAGE_EXIT":
			cmd.params = {"characters_csv": "", "duration": 0.35, "exit_effect": "fade"}
		"CHANGE_EXPRESSION":
			cmd.params = {"character_id": "", "expression": "", "transition": "", "duration": -1.0}
		"MOVE_CHARACTER":
			cmd.params = {"character_id": "", "target": "center", "duration": 0.3, "easing": "ease_in_out"}
		"MOVE_CHARACTER_BY":
			cmd.params = {"character_id": "", "offset_x": 0.0, "offset_y": 0.0, "duration": 0.3}
		"FLIP_CHARACTER":
			cmd.params = {"character_id": "", "flip": "toggle", "duration": 0.0}
		"CHARACTER_EFFECT":
			cmd.params = {"character_id": "", "effect": "jump", "intensity": "medium", "duration": -1.0}
		"SET_CHARACTER_PROPERTY":
			cmd.params = {"character_id": "", "property": "opacity", "value": "1.0", "duration": 0.3}
		"WAIT_CLICK":
			cmd.params = {}
		"WAIT_TIME":
			cmd.params = {"duration": 1.0}
		"CHOICE":
			cmd.params = {"choices": [{"text": "", "commands": [], "condition_commands": [], "hidden_when_unmet": false}]}
		"LABEL":
			cmd.params = {"name": ""}
		"JUMP_LABEL":
			cmd.params = {"target": ""}
		"JUMP_SCENE":
			cmd.params = {"scene_id": "", "transition": "", "duration": 1.0, "color": "000000"}
		"SET_VARIABLE":
			cmd.params = {"variable_id": "", "variable_name": "", "value": 0, "operation": "set"}
		"CALL_EVENT":
			cmd.params = {"event_id": ""}
		"PLAY_BGM":
			cmd.params = {"audio_path": "", "fade_duration": 1.0, "volume": 1.0}
		"STOP_BGM":
			cmd.params = {"fade_duration": 1.0}
		"PLAY_SFX":
			cmd.params = {"audio_path": "", "volume": 1.0}
		"CHANGE_BACKGROUND":
			cmd.params = {"texture": null, "fade_duration": 0.5, "transition": "fade"}
		"IF":
			cmd.params = {"condition_commands": [], "if_commands": [], "has_else": false, "else_commands": []}
		"CHECK_VAR":
			cmd.params = {"variable_id": "", "variable_name": "", "operator": ">=", "value": "0"}
		"SCREEN_FADE":
			cmd.params = {"direction": "out", "color": "000000", "duration": 1.0, "transition": "fade"}
		"SCREEN_FLASH":
			cmd.params = {"color": "ffffff", "duration": 0.3, "intensity": 0.8}
		"SCREEN_SHAKE":
			cmd.params = {"intensity": 10.0, "duration": 0.5, "frequency": 20.0}
		"SHOW_IMAGE":
			cmd.params = {"image_id": "", "image_path": "", "norm_position": Vector2(0.0, 0.0), "norm_size": Vector2(1.0, 1.0), "fade_duration": 0.5, "z_order": 0}
		"HIDE_IMAGE":
			cmd.params = {"image_id": "", "fade_duration": 0.5}
		"SET_TEXT_SPEED":
			cmd.params = {"speed": 0.03}
		"CLEAR_DIALOGUE":
			cmd.params = {}
		"SHOW_NOTIFICATION":
			cmd.params = {"text": "", "duration": 2.0, "position": "top", "font_size": 0, "color": "ffffff"}
		"SET_TEXT":
			cmd.params = {"node_id": "", "text": ""}
		"SET_STYLE":
			cmd.params = {"node_id": "", "bg_color": "000000cc", "corner_radius": 8, "border_width": 0, "border_color": "ffffffff"}
		"MOVE_NODE":
			cmd.params = {"node_id": "", "norm_x": 0.0, "norm_y": 0.0, "duration": 0.3}
		"RESIZE_NODE":
			cmd.params = {"node_id": "", "norm_w": 0.1, "norm_h": 0.1, "duration": 0.3}
		"SHOW_NODE":
			cmd.params = {"node_id": "", "fade_duration": 0.0}
		"HIDE_NODE":
			cmd.params = {"node_id": "", "fade_duration": 0.0}
		"REMOVE_NODE":
			cmd.params = {"node_id": "", "fade_duration": 0.0}
		"SPAWN_NODE":
			cmd.params = {"shared_node_id": "", "instance_id": "", "norm_x": 0.0, "norm_y": 0.0, "parent_node_id": ""}
		"SET_NODE_PROPERTY":
			cmd.params = {"node_id": "", "property": "style_box", "value": ""}
		"CHECK_HOVER":
			cmd.params = {"node_id": ""}
		"CHECK_CLICK":
			cmd.params = {"node_id": ""}
		"CAMERA_ZOOM":
			cmd.params = {"zoom": 1.5, "focus": "", "duration": 1.0}
		"CAMERA_PAN":
			cmd.params = {"target": "", "norm_x": 0.0, "norm_y": 0.0, "duration": 1.0}
		"CAMERA_RESET":
			cmd.params = {"duration": 1.0}
		_:
			cmd.params = {}


## 创建新的 AVGCommand 资源
static func create_command(command_type: String) -> Resource:
	var AVGCommandClass = load("res://scripts/avg/resources/avg_command.gd")
	var cmd: Resource = AVGCommandClass.new()
	cmd.command_type = command_type
	init_command_params(cmd)
	return cmd
