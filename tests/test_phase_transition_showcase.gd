extends Control

const DesktopScene = preload("res://scenes/pseudo_os/desktop.tscn")

var _desktop: Control = null
var _hint_label: Label = null
var _auto_cycle_enabled: bool = false
var _auto_cycle_timer: SceneTreeTimer = null


func _ready() -> void:
	var game_loop: Node = get_node_or_null("/root/GameLoopManager")
	if game_loop != null and game_loop.has_method("reset_runtime_state"):
		game_loop.reset_runtime_state()

	_desktop = DesktopScene.instantiate()
	_desktop.name = "DesktopUnderTest"
	_desktop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_desktop)

	_hint_label = Label.new()
	_hint_label.name = "HintLabel"
	_hint_label.anchor_left = 0.0
	_hint_label.anchor_top = 0.0
	_hint_label.anchor_right = 0.0
	_hint_label.anchor_bottom = 0.0
	_hint_label.offset_left = 24.0
	_hint_label.offset_top = 24.0
	_hint_label.offset_right = 520.0
	_hint_label.offset_bottom = 168.0
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.add_theme_font_size_override("font_size", 20)
	_hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	_hint_label.text = "Space: 下一个时段\n1/2/3: 上午 / 下午 / 晚上\nD: 直接换天\nR: 重置到 Day 1 上午\nA: 开关自动循环演示"
	add_child(_hint_label)

	print("[TestPhaseShowcase] Space: 下一个时段")
	print("[TestPhaseShowcase] 1/2/3: 切到 上午/下午/晚上")
	print("[TestPhaseShowcase] D: 直接换天")
	print("[TestPhaseShowcase] R: 重置运行状态")
	print("[TestPhaseShowcase] A: 开关自动循环演示")


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	var game_loop: Node = get_node_or_null("/root/GameLoopManager")
	if game_loop == null:
		return

	match event.keycode:
		KEY_SPACE:
			if game_loop.has_method("_advance_phase"):
				game_loop._advance_phase()
				_print_state("advance_phase")
		KEY_1:
			_set_phase(game_loop, 0)
		KEY_2:
			_set_phase(game_loop, 1)
		KEY_3:
			_set_phase(game_loop, 2)
		KEY_D:
			if game_loop.has_method("advance_to_next_day"):
				game_loop.advance_to_next_day()
				_print_state("advance_day")
		KEY_R:
			if game_loop.has_method("reset_runtime_state"):
				game_loop.reset_runtime_state()
				_print_state("reset")
		KEY_A:
			_toggle_auto_cycle()


func _set_phase(game_loop: Node, phase: int) -> void:
	game_loop.time_phase = phase
	game_loop.phase_changed.emit(phase)
	_print_state("set_phase")


func _print_state(tag: String) -> void:
	var game_loop: Node = get_node_or_null("/root/GameLoopManager")
	if game_loop == null:
		return
	var phase_name: String = game_loop.get_phase_display_name(game_loop.time_phase)
	print("[TestPhaseShowcase] %s -> Day %d / %s" % [tag, game_loop.current_day, phase_name])


func _toggle_auto_cycle() -> void:
	_auto_cycle_enabled = not _auto_cycle_enabled
	print("[TestPhaseShowcase] auto_cycle = %s" % str(_auto_cycle_enabled))
	if _auto_cycle_enabled:
		_run_auto_cycle()


func _run_auto_cycle() -> void:
	while _auto_cycle_enabled:
		_auto_cycle_timer = get_tree().create_timer(2.4)
		await _auto_cycle_timer.timeout
		if not _auto_cycle_enabled:
			break
		var game_loop: Node = get_node_or_null("/root/GameLoopManager")
		if game_loop == null or not game_loop.has_method("_advance_phase"):
			break
		game_loop._advance_phase()
		_print_state("auto_cycle")
