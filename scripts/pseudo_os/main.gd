class_name Main extends Control
## 主入口 — 管理 Splash -> Boot -> Login -> Desktop 的场景切换

const SplashScreenScene: PackedScene = preload("res://scenes/pseudo_os/splash_screen.tscn")
const BootScreenScene: PackedScene = preload("res://scenes/pseudo_os/boot_screen.tscn")
const LoginScreenScene: PackedScene = preload("res://scenes/pseudo_os/login_screen.tscn")
const StoryDesktopScene: PackedScene = preload("res://scenes/pseudo_os/game_desktop.tscn")
const FreeDesktopScene: PackedScene = preload("res://scenes/pseudo_os/free_desktop.tscn")
const MODE_FREE: String = "free"

enum State { SPLASH, BOOT, LOGIN, DESKTOP }

var _current_state: State = State.SPLASH
var _current_screen: Control = null


func _ready() -> void:
	_enter_splash()


func _enter_splash() -> void:
	_clear_screen()
	_current_state = State.SPLASH
	var splash: Control = SplashScreenScene.instantiate()
	_current_screen = splash
	add_child(splash)
	splash.splash_finished.connect(_on_splash_finished)


func _on_splash_finished() -> void:
	_transition_to(_enter_boot)


func _enter_boot() -> void:
	_clear_screen()
	_current_state = State.BOOT
	var boot: Control = BootScreenScene.instantiate()
	_current_screen = boot
	add_child(boot)
	boot.boot_finished.connect(_on_boot_finished)


func _transition_to(next_callable: Callable) -> void:
	if _current_screen != null and is_instance_valid(_current_screen):
		var tween: Tween = create_tween()
		var screen_ref: Control = _current_screen
		tween.tween_property(screen_ref, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_callback(func() -> void:
			if is_instance_valid(screen_ref):
				screen_ref.queue_free()
			_current_screen = null
			next_callable.call()
		)
	else:
		next_callable.call()


func _on_boot_finished() -> void:
	_transition_to(_enter_login)


func _enter_login() -> void:
	_current_state = State.LOGIN
	var login: Control = LoginScreenScene.instantiate()
	_current_screen = login
	add_child(login)
	login.login_requested.connect(_on_login_requested)
	login.quit_requested.connect(_on_quit_requested)
	login.settings_requested.connect(_on_settings_requested)


func _on_login_requested(player_name: String, is_new_game: bool, play_mode: String) -> void:
	_save_player_name(player_name)
	# 将网名存入 StoryDirector，供 prompt 系统使用
	var story_director: Node = get_node_or_null("/root/StoryDirector")
	if story_director != null and story_director.has_method("set_variable"):
		story_director.set_variable("player_name", player_name)
	if is_new_game:
		_transition_to(func() -> void: _start_new_game(player_name, play_mode))
	else:
		_transition_to(func() -> void: _continue_game(player_name, play_mode))


func _start_new_game(player_name: String, play_mode: String) -> void:
	print("[Main] New game started. Player: %s" % player_name)
	_reset_all_managers()
	_enter_desktop(play_mode)


func _continue_game(_player_name: String, play_mode: String) -> void:
	print("[Main] Continuing game.")
	_enter_desktop(play_mode)


func _enter_desktop(play_mode: String) -> void:
	_current_state = State.DESKTOP
	var desktop_scene: PackedScene = FreeDesktopScene if play_mode == MODE_FREE else StoryDesktopScene
	var desktop: Control = desktop_scene.instantiate()
	desktop.modulate.a = 0.0
	_current_screen = desktop
	add_child(desktop)
	var tween: Tween = create_tween()
	tween.tween_property(desktop, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_quit_requested() -> void:
	# 恢复系统鼠标
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().quit()


func _on_settings_requested() -> void:
	# TODO: 打开设置界面
	print("[Main] Settings requested (not implemented yet)")


func _clear_screen() -> void:
	if _current_screen != null and is_instance_valid(_current_screen):
		_current_screen.queue_free()
		_current_screen = null


func _save_player_name(player_name: String) -> void:
	var meta_path: String = "user://run/meta.json"
	var meta: Dictionary = {}

	# 读取已有 meta
	if FileAccess.file_exists(meta_path):
		var read_file: FileAccess = FileAccess.open(meta_path, FileAccess.READ)
		if read_file != null:
			var parsed: Variant = JSON.parse_string(read_file.get_as_text())
			read_file.close()
			if parsed is Dictionary:
				meta = parsed

	meta["player_name"] = player_name

	# 确保目录存在
	if not DirAccess.dir_exists_absolute("user://run/"):
		DirAccess.make_dir_recursive_absolute("user://run/")

	var write_file: FileAccess = FileAccess.open(meta_path, FileAccess.WRITE)
	if write_file != null:
		write_file.store_string(JSON.stringify(meta, "\t"))
		write_file.close()


func _reset_all_managers() -> void:
	# 重置游戏循环
	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null and glm.has_method("reset_runtime_state"):
		glm.reset_runtime_state()

	# 重置游戏数值
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null and gm.has_method("reset_runtime_state"):
		gm.reset_runtime_state()

	# 重置故事进度
	var sd: Node = get_node_or_null("/root/StoryDirector")
	if sd != null and sd.has_method("reset_runtime_state"):
		sd.reset_runtime_state()
