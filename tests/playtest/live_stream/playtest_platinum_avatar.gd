extends Node3D
## Platinum 模型姿态、表情与手势的人工验收入口。
## 按钮列表从模型 Resource 动态生成，模型能力更新后无需改场景。

@export var model_resource: StreamerModelResource = null

@onready var _avatar: PlatinumAvatarController = $PlatinumAvatar

const AUTO_INTERVAL: float = 3.0
const ZOOM_MIN: float = 1.2
const ZOOM_MAX: float = 5.5
const ZOOM_STEP: float = 0.12

## 预览用全身取景（模型 Resource 的相机是直播胸像构图，不适用于验收）。
const FRAME_TARGET := Vector3(0.0, 0.95, 0.0)
const FRAME_DISTANCE: float = 4.5
const FRAME_FOV: float = 24.0

const POSTURE_LABELS: Dictionary = {
	&"idle": "自然待机",
	&"thinking": "后仰思考",
	&"lean_forward": "前倾投入",
	&"lean_back": "后仰放松",
	&"slump": "沮丧驼背",
	&"proud": "挺胸得意",
}
const HEAD_LABELS: Dictionary = {
	&"idle": "平视",
	&"head_down": "低头",
	&"head_down_side": "低头侧视",
	&"head_tilt": "歪头",
}
const EXPRESSION_LABELS: Dictionary = {
	&"default": "默认",
	&"neutral": "中性",
	&"smile": "微笑",
	&"happy": "开心",
	&"laugh": "大笑",
	&"excited": "兴奋",
	&"embarrassed": "害羞",
	&"shy": "腼腆",
	&"worried": "苦恼",
	&"strained": "勉强",
	&"sad": "难过",
	&"angry": "生气",
	&"serious": "认真",
	&"surprised": "惊讶",
	&"shocked": "震惊",
	&"panicked": "慌乱",
	&"thinking": "思考",
	&"smug": "得意",
	&"love": "花痴",
	&"wink": "眨眼",
	&"sleepy": "困倦",
	&"teasing": "吐舌",
	&"dizzy": "晕头",
}
const GESTURE_LABELS: Dictionary = {
	&"wave": "挥手",
	&"nod": "点头",
	&"shake_head": "摇头",
	&"bow": "鞠躬",
	&"clap": "拍手",
	&"cheer": "欢呼",
}
const ARM_LABELS: Dictionary = {
	&"idle": "垂臂",
	&"hands_on_hips": "双手叉腰",
	&"hand_on_hip_l": "单手叉腰左",
	&"hand_on_hip_r": "单手叉腰右",
	&"arms_crossed": "抱手",
}
@onready var status_label: Label = %StatusLabel
@onready var detail_label: Label = %DetailLabel
@onready var posture_row: HFlowContainer = %PostureRow
@onready var expression_row: HFlowContainer = %ExpressionRow
@onready var gesture_row: HFlowContainer = %GestureRow
@onready var arm_row: HFlowContainer = %ArmRow
@onready var head_row: HFlowContainer = %HeadRow
@onready var talk_button: Button = %TalkButton
@onready var auto_toggle: CheckButton = %AutoToggle
@onready var avatar_camera: Camera3D = %Camera3D

var _talking: bool = false
var _auto_index: int = 0
var _auto_time_left: float = AUTO_INTERVAL
var _camera_target: Vector3 = Vector3.ZERO
var _camera_distance: float = 3.15


func _ready() -> void:
	if model_resource != null:
		_camera_target = FRAME_TARGET
		_camera_distance = FRAME_DISTANCE
		_apply_camera()
		_build_buttons()
	talk_button.pressed.connect(_on_talk_pressed)
	auto_toggle.toggled.connect(_on_auto_toggled)
	_update_status("模型能力已从 Resource 载入；滚轮缩放镜头")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera_distance = maxf(ZOOM_MIN, _camera_distance - ZOOM_STEP)
			_apply_camera()
			_update_status("镜头距离 %.2f" % _camera_distance)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera_distance = minf(ZOOM_MAX, _camera_distance + ZOOM_STEP)
			_apply_camera()
			_update_status("镜头距离 %.2f" % _camera_distance)
			get_viewport().set_input_as_handled()


func _apply_camera() -> void:
	if model_resource == null:
		return
	var offset := Vector3(0.0, 0.0, 1.0) * _camera_distance
	avatar_camera.position = _camera_target + offset
	avatar_camera.fov = FRAME_FOV
	avatar_camera.look_at(_camera_target)


func _process(delta: float) -> void:
	if not auto_toggle.button_pressed or model_resource == null:
		return
	_auto_time_left -= delta
	if _auto_time_left > 0.0:
		return
	_auto_time_left = AUTO_INTERVAL
	var expressions: Array[StringName] = model_resource.supported_expressions
	if expressions.is_empty():
		return
	_auto_index = (_auto_index + 1) % expressions.size()
	var expression_name: StringName = expressions[_auto_index]
	if _avatar.set_expression(expression_name):
		_update_status("自动轮播表情：%s" % _label(EXPRESSION_LABELS, expression_name))


func _build_buttons() -> void:
	for posture_name: StringName in model_resource.supported_postures:
		_add_button(posture_row, _label(POSTURE_LABELS, posture_name), func() -> void:
			if _avatar.set_posture(posture_name):
				_update_status("姿态切换：%s（0.5 秒交叉淡化）" % _label(POSTURE_LABELS, posture_name))
		)
	for expression_name: StringName in model_resource.supported_expressions:
		_add_button(expression_row, _label(EXPRESSION_LABELS, expression_name), func() -> void:
			if _avatar.set_expression(expression_name):
				_update_status("表情切换：%s（0.3 秒过渡）" % _label(EXPRESSION_LABELS, expression_name))
		)
	for gesture_name: StringName in model_resource.supported_gestures:
		_add_button(gesture_row, _label(GESTURE_LABELS, gesture_name), func() -> void:
			if _avatar.play_gesture(gesture_name):
				_update_status("手势播放：%s（结束后回到当前姿态）" % _label(GESTURE_LABELS, gesture_name))
		)
	for arm_name: StringName in model_resource.supported_arm_poses:
		_add_button(arm_row, _label(ARM_LABELS, arm_name), func() -> void:
			if _avatar.set_arm_pose(arm_name):
				_update_status("手臂姿势切换：%s（与身体姿态叠加组合）" % _label(ARM_LABELS, arm_name))
		)
	for head_name: StringName in model_resource.supported_head_poses:
		_add_button(head_row, _label(HEAD_LABELS, head_name), func() -> void:
			if _avatar.set_head_pose(head_name):
				_update_status("头部姿势切换：%s（与身体姿态、手臂姿势叠加组合）" % _label(HEAD_LABELS, head_name))
		)


func _add_button(row: HFlowContainer, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override(&"font_size", 34)
	button.pressed.connect(callback)
	row.add_child(button)


func _label(labels: Dictionary, value: StringName) -> String:
	if labels.has(value):
		return "%s %s" % [str(labels[value]), String(value)]
	return String(value)


func _update_status(detail: String) -> void:
	status_label.text = "姿态：%s　头部：%s　手臂：%s　表情：%s　口型：%s" % [
		String(_avatar.get_current_posture()),
		String(_avatar.get_current_head_pose()),
		String(_avatar.get_current_arm_pose()),
		String(_avatar.get_current_expression()),
		"开启" if _talking else "关闭",
	]
	detail_label.text = detail


func _on_talk_pressed() -> void:
	_talking = not _talking
	_avatar.set_talking(_talking)
	talk_button.text = "停止口型" if _talking else "开启口型"
	_update_status("口型层独立淡入" if _talking else "口型层独立淡出")


func _on_auto_toggled(toggled_on: bool) -> void:
	_auto_time_left = AUTO_INTERVAL
	_auto_index = 0
	_update_status("每 3 秒自动轮播全部表情" if toggled_on else "自动轮播已关闭")
