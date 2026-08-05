class_name GameStoryActions extends Node
## 游戏侧剧情动作处理器。
## 把 StoryDirector 的通用 action 接到桌面 OS / 浏览器 / AVG 播放器，
## 并把关键剧情变量同步进 GameState。
## 由游戏组合入口创建。

func _ready() -> void:
	var director: Node = get_node_or_null("/root/StoryDirector")
	if director == null:
		push_warning("[GameStoryActions] StoryDirector not available")
		return
	director.register_action_handler("launch_app", _action_launch_app)
	director.register_action_handler("close_app", _action_close_app)
	director.register_action_handler("focus_app", _action_focus_app)
	director.register_action_handler("open_browser", _action_open_browser)
	director.register_action_handler("notify", _action_notify)
	director.register_action_handler("set_desktop_app_visibility", _action_set_desktop_app_visibility)
	director.register_action_handler("install_app", _action_install_app)
	director.register_action_handler("play_transit", _action_play_transit)
	director.register_action_handler("play_avg", _action_play_avg)
	director.register_action_handler("check_llm_available", _action_check_llm_available)
	if not director.story_variable_changed.is_connected(_on_story_variable_changed):
		director.story_variable_changed.connect(_on_story_variable_changed)
	# App 启动事件桥接为剧情等待条件：wait: app_launched + app_id 匹配
	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager != null and app_manager.has_signal("app_launched") \
		and not app_manager.app_launched.is_connected(_on_app_launched):
		app_manager.app_launched.connect(_on_app_launched)
	var transit_manager: Node = get_node_or_null("/root/TransitManager")
	var transit_finished_cb := Callable(self, "_on_transit_finished")
	if transit_manager != null and transit_manager.has_signal("transit_finished") \
		and not transit_manager.is_connected("transit_finished", transit_finished_cb):
		transit_manager.connect("transit_finished", transit_finished_cb)


## { "type": "launch_app", "app_id": "linkchat" }
func _action_launch_app(action: Dictionary) -> bool:
	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager == null:
		return false
	return app_manager.launch_app(str(action.get("app_id", "")), true) != null


## { "type": "close_app", "app_id": "browser" }
func _action_close_app(action: Dictionary) -> bool:
	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager == null:
		return false
	var app_id: String = str(action.get("app_id", ""))
	if not app_manager.is_app_running(app_id):
		return true
	return app_manager.close_app(app_id, true)


## { "type": "focus_app", "app_id": "linkchat" }（未运行则拉起）
func _action_focus_app(action: Dictionary) -> bool:
	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager == null:
		return false
	return app_manager.focus_app(str(action.get("app_id", "")), true) != null


## { "type": "open_browser", "url": "browser://signup" }
func _action_open_browser(action: Dictionary) -> bool:
	var url: String = str(action.get("url", "")).strip_edges()
	if url.is_empty():
		return false
	var app_manager: Node = get_node_or_null("/root/AppManager")
	var browser_manager: Node = get_node_or_null("/root/BrowserManager")
	if app_manager == null or browser_manager == null:
		return false
	if app_manager.focus_app("browser", true) == null:
		return false
	# 延迟到浏览器首页导航之后执行，避免被覆盖
	browser_manager.request_open_url.call_deferred(url, str(action.get("design_prompt", "")), str(action.get("page_context", "")))
	return true


## { "type": "notify", "title": "鸢鸢", "body": "快看文件！", "duration": 5.0 }
func _action_notify(action: Dictionary) -> bool:
	var desktop: Node = get_tree().get_first_node_in_group("desktop")
	if desktop == null or not desktop.has_method("show_system_notification"):
		return false
	desktop.show_system_notification(
		str(action.get("title", "")),
		str(action.get("body", "")),
		str(action.get("icon", "warning")),
		float(action.get("duration", 5.0))
	)
	return true


## { "type": "set_desktop_app_visibility", "app_id": "obs_live", "visible": true }
func _action_set_desktop_app_visibility(action: Dictionary) -> bool:
	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager == null:
		return false
	return app_manager.set_app_desktop_visible(str(action.get("app_id", "")), bool(action.get("visible", true)))


## { "type": "install_app", "path": "res://resources/apps/obs_live_app.tres" }
func _action_install_app(action: Dictionary) -> bool:
	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager == null:
		return false
	return app_manager.install_app_from_path(str(action.get("path", "")))


## { "type": "play_transit", "id": "to_cafe", "duration": 3.6, ... }
## 行程完成后发 transit_finished 等待条件，后续场景不会提前启动。
func _action_play_transit(action: Dictionary) -> bool:
	var transit_manager: Node = get_node_or_null("/root/TransitManager")
	if transit_manager == null or not transit_manager.has_method("play_timed_transit"):
		return false
	return not str(transit_manager.call("play_timed_transit", action)).is_empty()


func _on_transit_finished(transit_id: String, payload: Dictionary) -> void:
	var director: Node = get_node_or_null("/root/StoryDirector")
	if director != null:
		director.notify_condition_met("transit_finished", {
			"transit_id": transit_id,
			"payload": payload,
		})


## { "type": "play_avg", "dsl_path": "res://resources/story/avg/cafe.txt", "title": "咖啡厅", "session_id": "prologue_cafe" }
## 播完发 avg_finished 等待条件（data 带 session_id / outcome）
func _action_play_avg(action: Dictionary) -> bool:
	var dsl_path: String = str(action.get("dsl_path", "")).strip_edges()
	var session_id: String = str(action.get("session_id", "")).strip_edges()
	if session_id.is_empty():
		session_id = dsl_path.get_file().get_basename()
	var title: String = str(action.get("title", session_id))

	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager == null:
		return false
	var window: Control = app_manager.launch_app("avg_player", true)
	if window == null:
		return false
	var players: Array[Node] = window.find_children("*", "AVGPlayer", true, false)
	if players.is_empty():
		push_warning("[GameStoryActions] play_avg: AVGPlayer node not found in window")
		return false
	var player: Node = players[0]
	var finished_cb := Callable(self, "_on_avg_playback_finished")
	if not player.playback_finished.is_connected(finished_cb):
		player.playback_finished.connect(finished_cb)
	if not player.has_method("play_dsl_file"):
		push_warning("[GameStoryActions] play_avg: AVGPlayer does not support DSL playback")
		return false
	return bool(player.play_dsl_file(session_id, dsl_path, title))


func _on_avg_playback_finished(session_id: String, outcome: Dictionary) -> void:
	var director: Node = get_node_or_null("/root/StoryDirector")
	if director != null:
		director.notify_condition_met("avg_finished", {"session_id": session_id, "outcome": outcome})


## { "type": "check_llm_available", "key": "llm_available" }
## 把"聊天 LLM 是否可用"写入剧情变量，供 next_conditions 分支
func _action_check_llm_available(action: Dictionary) -> bool:
	var director: Node = get_node_or_null("/root/StoryDirector")
	if director == null:
		return false
	var available: bool = false
	var topic_manager: Node = director.get_topic_manager()
	if topic_manager != null and topic_manager.has_method("can_auto_generate_llm"):
		available = bool(topic_manager.can_auto_generate_llm())
	director.set_variable(str(action.get("key", "llm_available")), available)
	return true


func _on_app_launched(app_id: String, _window: Control) -> void:
	var director: Node = get_node_or_null("/root/StoryDirector")
	if director != null:
		director.notify_condition_met("app_launched", {"app_id": app_id})


## 关键剧情变量 → GameState
func _on_story_variable_changed(key: String, value: Variant) -> void:
	var game_state: Node = get_node_or_null("/root/GameState")
	if key == "vtuber_name" and game_state != null and "streamer_name" in game_state:
		game_state.streamer_name = str(value)
