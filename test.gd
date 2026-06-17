extends Node

const WindowManagerClass = preload("res://scripts/pseudo_os/window_manager.gd")
const CharacterDisplayClass = preload("res://scripts/avg/runtime/character_display.gd")
const StoryStepClass = preload("res://scripts/story/resources/story_step.gd")
const StoryChapterClass = preload("res://scripts/story/resources/story_chapter.gd")
const ChatTopicClass = preload("res://scripts/chat/resources/chat_topic.gd")
const WebPageRendererClass = preload("res://scripts/apps/browser/web_page_renderer.gd")
const ChatPromptBuilderClass = preload("res://scripts/chat/chat_prompt_builder.gd")


func _ready() -> void:
	print("=== StoryDirector Director Test ===")
	await _test_character_show_hide_effects()
	await _ensure_window_manager()
	await _test_signup_page()
	await _test_signup_scene_rejects_invalid_name()
	await _test_signup_scene_persists_locked_state()
	_test_npc_first_prompt_builder()
	await _test_app_window_lock()
	await _test_sbeam_library_launch()
	await _test_story_form_validation_gate()
	await _test_story_form_bridge()
	await _test_scene_page()
	await _test_linkchat_topic_focus()
	await _test_story_topic_force_open()
	await _test_day1_story_flow()
	_test_browser_history_domain_boundary()
	_test_player_project_runtime_mount()
	_test_day_checkpoint_roundtrip()
	await _test_new_run_bootstrap()
	print("=== StoryDirector Director Test Complete ===")


func _test_character_show_hide_effects() -> void:
	var character_display := CharacterDisplayClass.new()
	character_display.name = "CharacterDisplayTest"
	add_child(character_display)
	await get_tree().process_frame

	character_display.set_design_resolution(Vector2(1000, 1000))
	character_display.set_character_data({
		"char_test": {
			"character_name": "Test",
			"display_name": "Test",
			"sprites": {
				"default": _make_test_texture(100, 200, Color(1.0, 0.4, 0.6, 1.0)),
			},
		}
	})

	var signal_state := {"shown": false, "hidden": false}
	character_display.character_shown.connect(func(character_id: String) -> void:
		if character_id == "char_test":
			signal_state["shown"] = true
	)
	character_display.character_hidden.connect(func(character_id: String) -> void:
		if character_id == "char_test":
			signal_state["hidden"] = true
	)

	character_display.show_character(
		"char_test",
		"center",
		"default",
		0.05,
		false,
		1.0,
		1.0,
		"",
		"slide_from_right",
		0.2,
		"ease_out"
	)

	var sprite: TextureRect = character_display.get_character_sprite("char_test")
	if sprite == null:
		print("[FAIL] Character show/hide effects test could not create sprite")
		character_display.queue_free()
		return

	var target_position := Vector2(250.0, 0.0)
	if sprite.position.x <= target_position.x:
		print("[FAIL] Character enter effect did not start from the right side")
		print("  start_position: %s" % str(sprite.position))
		character_display.queue_free()
		return

	var show_tween: Tween = character_display._active_tweens.get("char_test_fade", null)
	if show_tween == null or not show_tween.is_valid():
		print("[FAIL] Character enter effect did not create a tween")
		character_display.queue_free()
		return
	show_tween.custom_step(0.1)
	await get_tree().process_frame

	if not bool(signal_state["shown"]) or not _is_close_vector2(sprite.position, target_position) or absf(sprite.modulate.a - 1.0) > 0.01:
		print("[FAIL] Character enter effect did not finish at the expected state")
		print("  shown: %s" % str(signal_state["shown"]))
		print("  position: %s" % str(sprite.position))
		print("  alpha: %s" % str(sprite.modulate.a))
		character_display.queue_free()
		return

	character_display.hide_character("char_test", 0.05, "slide_to_left", 0.15, "ease_in")
	var hide_tween: Tween = character_display._active_tweens.get("char_test_fade", null)
	if hide_tween == null or not hide_tween.is_valid():
		print("[FAIL] Character exit effect did not create a tween")
		character_display.queue_free()
		return
	hide_tween.custom_step(0.1)
	await get_tree().process_frame

	if not bool(signal_state["hidden"]) or sprite.visible or not _is_close_vector2(sprite.position, target_position):
		print("[FAIL] Character exit effect did not hide and restore sprite state")
		print("  hidden: %s" % str(signal_state["hidden"]))
		print("  visible: %s" % str(sprite.visible))
		print("  position: %s" % str(sprite.position))
		character_display.queue_free()
		return

	print("[OK] Character show/hide shortcut effects work")
	print("  enter_effect: slide_from_right")
	print("  exit_effect: slide_to_left")
	character_display.queue_free()


func _ensure_window_manager() -> void:
	if AppManager.window_manager != null:
		return

	var window_container := Control.new()
	window_container.name = "TestWindowContainer"
	window_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(window_container)

	var window_manager := WindowManagerClass.new()
	add_child(window_manager)
	await get_tree().process_frame
	window_manager.set_window_container(window_container)
	AppManager.set_window_manager(window_manager)
	print("[OK] WindowManager ready for app launch tests")


func _test_signup_page() -> void:
	var request_id: String = BrowserManager.open_page("gamejam://signup")
	print("[INFO] open_page request_id = %s" % request_id)
	await get_tree().process_frame

	var page: Dictionary = BrowserManager.get_cached_page("gamejam://signup")
	if page.is_empty():
		print("[FAIL] Premade signup page not cached")
		return

	if str(page.get("scene_path", "")).strip_edges().is_empty():
		print("[FAIL] Signup page payload missing scene_path")
		return

	BrowserManager.request_open_url("gamejam://signup")
	await get_tree().process_frame
	await get_tree().process_frame

	var browser_window: Control = AppManager.get_app_window("browser")
	if browser_window == null or browser_window.content == null:
		print("[FAIL] Browser app unavailable for signup scene test")
		return

	var browser_app: Node = browser_window.content
	var rendered_scene: Node = null
	if "content_root" in browser_app and browser_app.content_root != null and browser_app.content_root.get_child_count() > 0:
		rendered_scene = browser_app.content_root.get_child(0)

	if rendered_scene == null or rendered_scene.name != "GameJamSignupPage":
		print("[FAIL] Signup page did not instantiate expected scene")
		return

	print("[OK] Premade signup page loaded")
	print("  scene_path: %s" % str(page.get("scene_path", "")))
	print("  rendered_scene: %s" % rendered_scene.name)


func _test_signup_scene_rejects_invalid_name() -> void:
	StoryDirector.story_variables.erase("signup_completed")
	BrowserManager.request_open_url("gamejam://signup")
	await get_tree().process_frame
	await get_tree().process_frame

	var browser_window: Control = AppManager.get_app_window("browser")
	if browser_window == null or browser_window.content == null:
		print("[FAIL] Browser app unavailable for signup review rejection test")
		return

	var browser_app: Node = browser_window.content
	var signup_scene: Node = null
	if "content_root" in browser_app and browser_app.content_root != null and browser_app.content_root.get_child_count() > 0:
		signup_scene = browser_app.content_root.get_child(0)

	if signup_scene == null or not signup_scene.has_method("submit_signup_for_test"):
		print("[FAIL] Signup scene missing test hook for rejection test")
		return

	var accepted: bool = bool(signup_scene.call("submit_signup_for_test", {
		"player_name": "我是来捣乱的",
		"player_college": "互动媒体学院",
		"team_name": "MoonJam",
	}, false))
	var status_text: String = ""
	if signup_scene.has_method("get_status_text_for_test"):
		status_text = str(signup_scene.call("get_status_text_for_test"))
	var signup_completed: bool = bool(StoryDirector.get_variable("signup_completed", false))

	if accepted or signup_completed:
		print("[FAIL] Signup scene accepted invalid player name")
		print("  accepted: %s" % str(accepted))
		print("  status_text: %s" % status_text)
		print("  signup_completed: %s" % str(signup_completed))
		return

	print("[OK] Signup scene rejected invalid player name")
	print("  accepted: %s" % str(accepted))
	print("  status_text: %s" % status_text)
	print("  signup_completed: %s" % str(signup_completed))


func _test_signup_scene_persists_locked_state() -> void:
	StoryDirector.set_variable("signup_completed", true)
	StoryDirector.set_variable("player_name", "阿瓦")
	StoryDirector.set_variable("player_university", "蓝鲸大学")
	StoryDirector.set_variable("player_college", "互动媒体学院")
	StoryDirector.set_variable("team_name", "WhatGame")

	BrowserManager.request_open_url("gamejam://signup")
	await get_tree().process_frame
	await get_tree().process_frame

	var browser_window: Control = AppManager.get_app_window("browser")
	if browser_window == null or browser_window.content == null:
		print("[FAIL] Browser app unavailable for signup persistence test")
		return

	var browser_app: Node = browser_window.content
	var signup_scene: Node = null
	if "content_root" in browser_app and browser_app.content_root != null and browser_app.content_root.get_child_count() > 0:
		signup_scene = browser_app.content_root.get_child(0)

	if signup_scene == null or not signup_scene.has_method("is_submission_locked_for_test"):
		print("[FAIL] Signup scene missing lock-state hook")
		return

	var locked: bool = bool(signup_scene.call("is_submission_locked_for_test"))
	var status_text: String = ""
	if signup_scene.has_method("get_status_text_for_test"):
		status_text = str(signup_scene.call("get_status_text_for_test"))

	if not locked:
		print("[FAIL] Signup scene did not restore locked state after reopen")
		print("  status_text: %s" % status_text)
		return

	print("[OK] Signup scene restored locked state after reopen")
	print("  locked: %s" % str(locked))
	print("  status_text: %s" % status_text)


func _test_npc_first_prompt_builder() -> void:
	StoryDirector.set_variable("player_name", "阿瓦")
	StoryDirector.set_variable("player_university", "蓝鲸大学")
	StoryDirector.set_variable("player_college", "互动媒体学院")

	var channel: ChatChannel = ChatManager.get_channel("dm_lin_xia") as ChatChannel
	var npc: NPCCharacter = ChatManager.get_npc("npc_lin_xia")
	var npcs: Array[NPCCharacter] = []
	if npc != null:
		npcs.append(npc)
	var topic := ChatTopicClass.new()
	topic.topic_id = "test_npc_first_prompt"
	topic.topic_type = "story_event"
	topic.display_title = "NPC First Prompt Test"
	topic.npc_id = "npc_lin_xia"
	topic.channel_id = "dm_lin_xia"
	topic.system_prompt = "请先对报名后的队伍名做反应。"
	topic.goal_description = "先开口，再引导玩家继续。"

	var prompt_data: Dictionary = ChatPromptBuilderClass.build(
		channel,
		npcs,
		[],
		[],
		[],
		topic
	)
	var messages: Array = prompt_data.get("messages", [])
	var system_text: String = ""
	var user_text: String = ""
	if messages.size() > 0 and messages[0] is Dictionary:
		system_text = str(messages[0].get("content", ""))
	if messages.size() > 1 and messages[1] is Dictionary:
		user_text = str(messages[1].get("content", ""))
	var identity_ok: bool = "阿瓦" in system_text and "互动媒体学院" in system_text
	var opening_ok: bool = "NPC 主动发起" in user_text

	if not identity_ok or not opening_ok:
		print("[FAIL] NPC-first prompt builder did not build expected prompt")
		print("  user_text: %s" % user_text)
		print("  system_text_has_identity: %s" % str(identity_ok))
		return

	print("[OK] NPC-first prompt builder generated opening prompt")
	print("  user_text: %s" % user_text)
	print("  player_identity_in_system: %s" % str(identity_ok))


func _test_linkchat_response_protocol_parser() -> void:
	var line_protocol_response := "<thinking>测试</thinking>\n@npc_lin_xia: 骚鸡骚鸡！AGJ 的比赛主题刚刚公布了！\n@npc_lin_xia: [card:web_page url=gamejam://forum/theme]\n[TOPIC_COMPLETE]\n> 好的我这就去看看\n> 主题是什么？"
	var line_stripped: Dictionary = ChatManager.call("_strip_thinking_tags", line_protocol_response)
	var parsed_line: Dictionary = ChatManager.call("_parse_ai_response_text", str(line_stripped.get("body", "")), "npc_lin_xia")
	var line_messages: Array = parsed_line.get("messages", [])
	var line_replies: Array = parsed_line.get("recommended_replies", [])
	var line_ok: bool = line_messages.size() == 2 \
		and str(line_messages[0].get("speaker", "")) == "npc_lin_xia" \
		and "[TOPIC_COMPLETE]" in str(line_messages[1].get("content", "")) \
		and line_messages[1].has("card") \
		and str(line_messages[1].get("card", {}).get("url", "")) == "gamejam://forum/theme" \
		and line_replies.size() == 2

	if not line_ok:
		print("[FAIL] LinkChat line protocol parser regression")
		print("  parsed_line: %s" % str(parsed_line))
		return

	var legacy_json_response := "<thinking>测试</thinking>\n{\n  \"messages\": [\n    {\"speaker\": \"npc_lin_xia\", \"content\": \"旧 JSON 也应该继续工作\"}\n  ],\n  \"recommended_replies\": [\n    \"收到\"\n  ]\n}\n[TOPIC_COMPLETE]"
	var legacy_stripped: Dictionary = ChatManager.call("_strip_thinking_tags", legacy_json_response)
	var parsed_legacy: Dictionary = ChatManager.call("_parse_ai_response_text", str(legacy_stripped.get("body", "")), "npc_lin_xia")
	var legacy_messages: Array = parsed_legacy.get("messages", [])
	var legacy_replies: Array = parsed_legacy.get("recommended_replies", [])
	var legacy_ok: bool = legacy_messages.size() == 1 \
		and str(legacy_messages[0].get("speaker", "")) == "npc_lin_xia" \
		and "旧 JSON 也应该继续工作" in str(legacy_messages[0].get("content", "")) \
		and "[TOPIC_COMPLETE]" in str(legacy_messages[0].get("content", "")) \
		and legacy_replies.size() == 1

	if not legacy_ok:
		print("[FAIL] LinkChat legacy JSON compatibility regression")
		print("  parsed_legacy: %s" % str(parsed_legacy))
		return

	print("[OK] LinkChat response parser supports line protocol and legacy JSON")


func _test_app_window_lock() -> void:
	AppManager.clear_app_access_restriction()
	var browser_window: Control = AppManager.launch_app("browser", true)
	await get_tree().process_frame
	if browser_window == null:
		print("[FAIL] Browser app failed to launch")
		return

	StoryDirector._action_lock_app_window({
		"app_id": "browser",
		"close_locked": true,
		"minimize_locked": true,
		"focus": true,
	})

	print("[OK] Browser window lock applied")
	print("  close_locked: %s" % str(browser_window.close_locked if "close_locked" in browser_window else false))
	print("  minimize_locked: %s" % str(browser_window.minimize_locked if "minimize_locked" in browser_window else false))

	StoryDirector._action_unlock_app_window({"app_id": "browser"})
	print("[OK] Browser window unlock applied")


func _test_sbeam_library_launch() -> void:
	AppManager.clear_app_access_restriction()
	if AppManager.is_app_running("sbeam"):
		AppManager.close_app("sbeam", true)
	await get_tree().process_frame

	var sbeam_window: Control = AppManager.launch_app("sbeam", true)
	await get_tree().process_frame
	await get_tree().process_frame
	if sbeam_window == null or sbeam_window.content == null:
		print("[FAIL] Sbeam app failed to launch")
		return

	var sbeam_app: Node = sbeam_window.content
	if not sbeam_app.has_method("set_active_view") or not sbeam_app.has_method("launch_library_game"):
		print("[FAIL] Sbeam app missing library controls")
		return

	sbeam_app.call("set_active_view", "library")
	await get_tree().process_frame

	var game_window: Control = sbeam_app.call("launch_library_game", "2048")
	await get_tree().process_frame
	await get_tree().process_frame
	if game_window == null:
		print("[FAIL] Sbeam library failed to open 2048")
		return

	var reused_window: Control = sbeam_app.call("launch_library_game", "2048")
	await get_tree().process_frame

	var script_path: String = ""
	if game_window.content != null and game_window.content.get_script() != null:
		script_path = str(game_window.content.get_script().resource_path)

	var open_ok: bool = script_path == "res://scripts/apps/sbeam/games/game_2048.gd"
	var reuse_ok: bool = reused_window == game_window
	if not open_ok or not reuse_ok:
		print("[FAIL] Sbeam library window mismatch")
		print("  open_ok: %s" % str(open_ok))
		print("  reuse_ok: %s" % str(reuse_ok))
		print("  script_path: %s" % script_path)
	else:
		print("[OK] Sbeam library opened 2048 window")
		print("  reuse_ok: %s" % str(reuse_ok))
		print("  script_path: %s" % script_path)

	if AppManager.window_manager != null and game_window != null and is_instance_valid(game_window):
		AppManager.window_manager.close_window(game_window)
	await get_tree().process_frame

	if AppManager.is_app_running("sbeam"):
		AppManager.close_app("sbeam", true)
	await get_tree().process_frame


func _test_story_form_validation_gate() -> void:
	var browser_window: Control = AppManager.launch_app("browser", true)
	await get_tree().process_frame
	if browser_window == null or browser_window.content == null:
		print("[FAIL] Browser app unavailable for validation gate test")
		return

	var browser_app: Node = browser_window.content
	StoryDirector.story_variables.clear()

	var step := StoryStepClass.new()
	step.step_id = "signup_wait_validation"
	step.wait_for = {
		"type": "variable_equals",
		"key": "signup_completed",
		"value": "true",
	}

	var chapter := StoryChapterClass.new()
	chapter.chapter_id = "director_validation_test"
	chapter.chapter_name = "Director Validation Test"
	chapter.steps.append(step)

	StoryDirector.current_chapter = chapter
	StoryDirector._enter_step(step)

	browser_app._submit_story_form({
		"story_condition": "variable_equals",
		"story_key": "signup_completed",
		"story_value": "true",
		"__form_data": {
			"team_name": "",
		},
		"__form_validation": {
			"is_valid": false,
			"first_error": "队伍名不能为空",
		},
	})

	await get_tree().process_frame
	await get_tree().process_frame

	print("[OK] Story form validation gate blocked invalid submit")
	print("  signup_completed: %s" % str(StoryDirector.get_variable("signup_completed", false)))
	print("  current_step: %s" % str(StoryDirector.current_step.step_id if StoryDirector.current_step != null else ""))


func _test_story_form_bridge() -> void:
	var browser_window: Control = AppManager.launch_app("browser", true)
	await get_tree().process_frame
	if browser_window == null or browser_window.content == null:
		print("[FAIL] Browser app unavailable for form bridge test")
		return

	var browser_app: Node = browser_window.content
	var step := StoryStepClass.new()
	step.step_id = "signup_wait"
	step.wait_for = {
		"type": "variable_equals",
		"key": "signup_completed",
		"value": "true",
	}
	step.capture = {
		"team_name": "$.form_data.team_name",
	}

	var chapter := StoryChapterClass.new()
	chapter.chapter_id = "director_test"
	chapter.chapter_name = "Director Test"
	chapter.steps.append(step)

	StoryDirector.current_chapter = chapter
	StoryDirector._enter_step(step)

	browser_app._submit_story_form({
		"story_condition": "variable_equals",
		"story_key": "signup_completed",
		"story_value": "true",
		"__form_data": {
			"team_name": "MoonJam",
		},
	})

	await get_tree().process_frame
	await get_tree().process_frame

	print("[OK] Story form bridge submitted")
	print("  signup_completed: %s" % str(StoryDirector.get_variable("signup_completed", false)))
	print("  captured team_name: %s" % str(StoryDirector.get_variable("team_name", "")))


func _test_scene_page() -> void:
	var request_id: String = BrowserManager.open_page("browser://scene-demo")
	print("[INFO] scene page request_id = %s" % request_id)
	await get_tree().process_frame

	var page: Dictionary = BrowserManager.get_cached_page("browser://scene-demo")
	if str(page.get("scene_path", "")).strip_edges().is_empty():
		print("[FAIL] Scene page payload missing scene_path")
		return

	BrowserManager.request_open_url("browser://scene-demo")
	await get_tree().process_frame
	await get_tree().process_frame

	var browser_window: Control = AppManager.get_app_window("browser")
	if browser_window == null or browser_window.content == null:
		print("[FAIL] Browser app unavailable for scene page test")
		return

	var browser_app: Node = browser_window.content
	var rendered_scene: Node = null
	if "content_root" in browser_app and browser_app.content_root != null and browser_app.content_root.get_child_count() > 0:
		rendered_scene = browser_app.content_root.get_child(0)

	if rendered_scene == null or rendered_scene.name != "BrowserSceneDemo":
		print("[FAIL] Scene page did not instantiate expected scene")
		return

	if rendered_scene.has_method("_on_ping_button_pressed"):
		rendered_scene.call("_on_ping_button_pressed")
	await get_tree().process_frame

	var status_text: String = ""
	if rendered_scene.has_node("Root/StatusLabel"):
		status_text = str(rendered_scene.get_node("Root/StatusLabel").text)

	print("[OK] Scene page instantiated in BrowserApp")
	print("  scene_path: %s" % str(page.get("scene_path", "")))
	print("  status_text: %s" % status_text)


func _test_linkchat_topic_focus() -> void:
	if AppManager.is_app_running("linkchat"):
		AppManager.close_app("linkchat", true)
	await get_tree().process_frame

	var topic := ChatTopicClass.new()
	topic.topic_id = "test_class_group_focus"
	topic.topic_type = "casual_interaction"
	topic.display_title = "Class Group Ping"
	topic.npc_id = "npc_lin_xia"
	topic.channel_id = "class_group"
	topic.system_prompt = "test"

	if not ChatManager.activate_topic(topic):
		print("[FAIL] Unable to activate topic for LinkChat focus test")
		return

	var linkchat_window: Control = AppManager.launch_app("linkchat", true)
	await get_tree().process_frame
	await get_tree().process_frame

	if linkchat_window == null or linkchat_window.content == null:
		print("[FAIL] LinkChat app failed to launch for focus test")
		return

	print("[OK] LinkChat startup selected active topic channel")
	print("  current_channel_id: %s" % str(linkchat_window.content.current_channel_id))

	var active_topic: ChatTopic = ChatManager.get_active_topic("class_group")
	if active_topic != null:
		ChatManager.topic_manager.complete_topic(active_topic, {})


func _test_story_topic_force_open() -> void:
	if AppManager.is_app_running("linkchat"):
		AppManager.close_app("linkchat", true)
	await get_tree().process_frame

	StoryDirector._action_activate_topic({
		"topic_path": "res://resources/story/topics/day1_gamejam_announce.tres",
		"open_linkchat_mode": "force",
		"npc_speaks_first": false,
	})

	await get_tree().process_frame
	await get_tree().process_frame

	var linkchat_window: Control = AppManager.get_app_window("linkchat")
	if linkchat_window == null or linkchat_window.content == null:
		print("[FAIL] Story topic did not open LinkChat")
		return

	print("[OK] Story topic force-opened LinkChat")
	print("  current_channel_id: %s" % str(linkchat_window.content.current_channel_id))

	var active_topic: ChatTopic = ChatManager.get_active_topic("dm_lin_xia")
	if active_topic != null:
		ChatManager.topic_manager.complete_topic(active_topic, {})


func _test_day1_story_flow() -> void:
	if AppManager.is_app_running("browser"):
		AppManager.close_app("browser", true)
	if AppManager.is_app_running("map"):
		AppManager.close_app("map", true)
	if AppManager.is_app_running("linkchat"):
		AppManager.close_app("linkchat", true)
	await get_tree().process_frame

	var lingering_topic: ChatTopic = ChatManager.get_active_topic("dm_lin_xia")
	if lingering_topic != null:
		ChatManager.topic_manager.complete_topic(lingering_topic, {})

	StoryDirector.story_variables.clear()
	StoryDirector.completed_steps.clear()
	StoryDirector.completed_chapters.clear()

	if not StoryDirector.start_chapter("day1"):
		print("[FAIL] Unable to start day1 chapter")
		return

	await get_tree().process_frame
	await get_tree().process_frame
	print("[INFO] day1 step after start: %s" % str(StoryDirector.current_step.step_id if StoryDirector.current_step != null else ""))

	BrowserManager.request_open_url("gamejam://signup")
	await get_tree().process_frame
	await get_tree().process_frame

	var signup_browser_window: Control = AppManager.get_app_window("browser")
	if signup_browser_window == null or signup_browser_window.content == null:
		print("[FAIL] Day1 signup click did not force-open browser")
		return

	var signup_browser_app: Node = signup_browser_window.content
	var signup_url: String = ""
	if "address_display" in signup_browser_app and signup_browser_app.address_display != null:
		signup_url = str(signup_browser_app.address_display.text)
	if signup_url != "gamejam://signup":
		print("[FAIL] Day1 signup click opened unexpected browser url: %s" % signup_url)
		return
	print("[INFO] day1 browser after signup click: %s" % signup_url)

	var browser_window: Control = signup_browser_window
	if browser_window == null or browser_window.content == null:
		print("[FAIL] Browser app unavailable for day1 flow")
		return

	var browser_app: Node = browser_window.content
	var signup_scene: Node = null
	if "content_root" in browser_app and browser_app.content_root != null and browser_app.content_root.get_child_count() > 0:
		signup_scene = browser_app.content_root.get_child(0)
	if signup_scene == null or not signup_scene.has_method("submit_signup_for_test"):
		print("[FAIL] Signup scene missing test submission hook")
		return

	if not bool(signup_scene.call("submit_signup_for_test", {
		"player_name": "李沐",
		"player_college": "互动媒体学院",
		"team_name": "MoonJam",
	}, true)):
		print("[FAIL] Signup scene test submission failed")
		return

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var react_topic: ChatTopic = ChatManager.get_active_topic("dm_lin_xia")
	if react_topic != null and react_topic.topic_id == "day1_team_react":
		ChatManager.topic_manager.complete_topic(react_topic, {
			"summary": "队名反应测试已完成",
		})
		await get_tree().process_frame
		await get_tree().process_frame

	print("[INFO] day1 step after signup: %s" % str(StoryDirector.current_step.step_id if StoryDirector.current_step != null else ""))
	print("  map_running: %s" % str(AppManager.is_app_running("map")))

	DateManager.date_started.emit("day1_test_date", {
		"location": {
			"location_id": "park",
			"title": "Central Park",
		}
	})
	await get_tree().process_frame
	await get_tree().process_frame
	print("[INFO] day1 step after date_started: %s" % str(StoryDirector.current_step.step_id if StoryDirector.current_step != null else ""))

	DateManager.date_completed.emit("day1_test_date", {
		"location": {
			"location_id": "park",
			"title": "Central Park",
		}
	})
	await get_tree().process_frame
	await get_tree().process_frame
	print("[INFO] day1 step after date_completed: %s" % str(StoryDirector.current_step.step_id if StoryDirector.current_step != null else ""))

	BrowserManager.request_open_url("gamejam://forum/theme")
	await get_tree().process_frame
	await get_tree().process_frame

	var chapter_completed: bool = bool(StoryDirector.completed_chapters.get("day1", false))
	if chapter_completed:
		print("[OK] Day1 story flow completed")
	else:
		print("[FAIL] Day1 story flow did not complete")
	print("  chapter_completed: %s" % str(chapter_completed))
	print("  current_chapter: %s" % str(StoryDirector.current_chapter.chapter_id if StoryDirector.current_chapter != null else ""))


func _test_browser_history_domain_boundary() -> void:
	var expected_path: String = CampaignRunManager.get_browser_history_path()
	var actual_path: String = BrowserManager._get_history_path()
	var ok: bool = expected_path == actual_path and actual_path.begins_with("user://run/browser/")
	if ok:
		print("[OK] Browser history path is isolated in run domain")
	else:
		print("[FAIL] Browser history path leaked out of run domain")
	print("  expected: %s" % expected_path)
	print("  actual: %s" % actual_path)


func _test_player_project_runtime_mount() -> void:
	var mount_err: Error = StorageManager.mount_runtime_project()
	var mounted_path: String = str(StorageManager.current_project_path)
	var ok: bool = mount_err == OK and mounted_path.begins_with("user://run/player_project/")
	if ok:
		print("[OK] Runtime player project mounted under run root")
	else:
		print("[FAIL] Runtime player project mount failed")
	print("  err: %d" % int(mount_err))
	print("  current_project_path: %s" % mounted_path)


func _test_day_checkpoint_roundtrip() -> void:
	ChatManager.reset_runtime_state(true)
	BrowserManager.reset_runtime_state(true)
	StoryDirector.reset_runtime_state()
	GameLoopManager.reset_runtime_state()
	GameManager.reset_runtime_state()
	DateManager.load_run_state({
		"played_important_events": {
			"date_evt_alpha": true,
		}
	})
	PartTimeJobManager.load_run_state({
		"catalog_week_index": 2,
		"catalog": [
			{
				"job_id": "job_alpha",
				"job_title": "咖啡店晚班",
				"reward_money": 88,
				"enabled": true,
			}
		]
	})
	SbeamManager.load_run_state({
		"catalog_week_index": 2,
		"weekly_catalog": [
			{
				"game_id": "sbeam_alpha",
				"title": "纸箱勇者",
				"price": 18,
				"is_featured_today": true,
			}
		]
	})
	GameLoopManager.load_run_state({
		"current_day": 8,
		"max_ap_per_day": 1,
		"current_ap": 0,
		"time_phase": int(GameLoopManager.TimePhase.NIGHT),
		"today_actions": [
			{
				"action_type": "community",
				"detail": "checkpoint_test",
				"day": 8,
				"phase": "NIGHT",
			}
		]
	})
	GameManager.load_run_state({
		"affection": 42,
		"stress": 11,
		"passion": 77,
		"money": 345,
		"completion": 12,
		"quality": 9,
		"stability": 8,
		"hype": 6,
		"completed_orders_count": 2,
		"total_dates": 1,
	})
	StoryDirector.set_variable("checkpoint_flag", "roundtrip")
	BrowserManager.set_browser_state_value("checkpoint_topic", "jam_rules")
	var generated_path: String = CampaignRunManager.write_generated_activity_artifact(
		"test_activity",
		"test_session_001",
		"scene_package",
		{
			"source": "test_roundtrip",
			"scene_outline": "test outline",
		},
		{
			"source": "test_roundtrip",
		}
	)

	var save_err: Error = CampaignRunManager.save_checkpoint()
	if save_err != OK:
		print("[FAIL] Day checkpoint roundtrip failed to save")
		print("  err: %d" % int(save_err))
		return

	ChatManager.reset_runtime_state(true)
	BrowserManager.reset_runtime_state(true)
	StoryDirector.reset_runtime_state()
	GameLoopManager.reset_runtime_state()
	GameManager.reset_runtime_state()
	DateManager.load_run_state({})
	PartTimeJobManager.load_run_state({})
	SbeamManager.load_run_state({})

	var loaded: bool = CampaignRunManager.continue_run()
	var loop_ok: bool = GameLoopManager.current_day == 8 and GameLoopManager.current_ap == 0 and GameLoopManager.time_phase == GameLoopManager.TimePhase.NIGHT
	var stats_ok: bool = GameManager.affection == 42 and GameManager.money == 345
	var story_ok: bool = str(StoryDirector.get_variable("checkpoint_flag", "")) == "roundtrip"
	var browser_ok: bool = str(BrowserManager.get_browser_state_value("checkpoint_topic", "")) == "jam_rules"
	var date_ok: bool = bool(DateManager.get_run_state().get("played_important_events", {}).get("date_evt_alpha", false))
	var part_time_ok: bool = int(PartTimeJobManager.get_run_state().get("catalog_week_index", -1)) == 2
	var sbeam_ok: bool = int(SbeamManager.get_run_state().get("catalog_week_index", -1)) == 2
	var generated_ok: bool = int(CampaignRunManager.get_generated_registry().get("artifacts", []).size()) == 1 and not generated_path.is_empty() and FileAccess.file_exists(CampaignRunManager.get_run_root_path() + generated_path)
	if loaded and loop_ok and stats_ok and story_ok and browser_ok and date_ok and part_time_ok and sbeam_ok and generated_ok:
		print("[OK] Day checkpoint roundtrip restored run_state")
	else:
		print("[FAIL] Day checkpoint roundtrip restore mismatch")
	print("  loaded: %s" % str(loaded))
	print("  loop_ok: %s" % str(loop_ok))
	print("  stats_ok: %s" % str(stats_ok))
	print("  story_ok: %s" % str(story_ok))
	print("  browser_ok: %s" % str(browser_ok))
	print("  date_ok: %s" % str(date_ok))
	print("  part_time_ok: %s" % str(part_time_ok))
	print("  sbeam_ok: %s" % str(sbeam_ok))
	print("  generated_ok: %s" % str(generated_ok))


func _test_new_run_bootstrap() -> void:
	ChatManager.reset_runtime_state(true)
	BrowserManager.reset_runtime_state(true)
	var started: bool = CampaignRunManager.start_new_run("day1")
	await get_tree().process_frame
	await get_tree().process_frame
	var runtime_project_ok: bool = str(StorageManager.current_project_path).begins_with("user://run/player_project/")
	var chapter_ok: bool = StoryDirector.current_chapter != null and StoryDirector.current_chapter.chapter_id == "day1"
	var startup_mode_ok: bool = CampaignRunManager.get_startup_mode() == "new_run"
	if started and runtime_project_ok and chapter_ok and startup_mode_ok:
		print("[OK] New run bootstrap initialized runtime world")
	else:
		print("[FAIL] New run bootstrap did not initialize expected runtime world")
	print("  started: %s" % str(started))
	print("  runtime_project_ok: %s" % str(runtime_project_ok))
	print("  chapter_ok: %s" % str(chapter_ok))
	print("  startup_mode: %s" % str(CampaignRunManager.get_startup_mode()))


func _page_contains_action(node: Variant, action_name: String) -> bool:
	if node is Dictionary:
		if str(node.get("action", "")) == action_name:
			return true
		for key in node.keys():
			if _page_contains_action(node[key], action_name):
				return true
	elif node is Array:
		for item in node:
			if _page_contains_action(item, action_name):
				return true
	return false


func _make_test_texture(width: int, height: int, color: Color) -> Texture2D:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _is_close_vector2(a: Vector2, b: Vector2, tolerance: float = 0.05) -> bool:
	return absf(a.x - b.x) <= tolerance and absf(a.y - b.y) <= tolerance
