extends Control

const PROJECT_RES: Resource = preload("res://narrative_projects/main_story/project.tres")
const APP_ID: String = "avg_player"
const SESSION_ID: String = "stream_realistic_smoke"

var _wm: WindowManager = null


func _ready() -> void:
	print("=== Streaming AVG realistic playback test ===")
	var app_manager: Node = await _setup_window_manager()
	if app_manager == null:
		return

	var window: Control = app_manager.launch_app(APP_ID, true)
	if window == null:
		push_error("FAIL: avg_player app should launch")
		return
	await get_tree().process_frame
	await get_tree().process_frame

	var player: Control = window.get("content") as Control
	if player == null:
		push_error("FAIL: launched avg_player window should expose DateEventPlayer content")
		return
	_assert_real_app_window(window, player)

	for unique_name in ["StreamingPage", "StreamingAVGPlayer"]:
		var node := player.get_node_or_null("%" + unique_name)
		if node == null:
			push_error("FAIL: unique node %s not found" % unique_name)
		else:
			print("  OK: %s -> %s" % [unique_name, node.get_class()])
	var stream_view: Control = player.get_node_or_null("%StreamingAVGPlayer") as Control
	for unique_name in ["StreamTitleLabel", "ChatList", "SkipButton"]:
		var node := stream_view.get_node_or_null("%" + unique_name) if stream_view != null else null
		if node == null:
			push_error("FAIL: streaming unique node %s not found" % unique_name)
		else:
			print("  OK: %s -> %s" % [unique_name, node.get_class()])

	if not player.has_method("play_stream_package"):
		push_error("FAIL: play_stream_package method missing")
		return

	var package := {
		"session_id": SESSION_ID,
		"title": "买了老游嘛",
		"stream_script": _build_long_stream_script(),
		"project": PROJECT_RES.duplicate(true),
		"project_root_path": "res://narrative_projects/main_story/",
	}

	var finish_state := {
		"finished": false,
		"outcome": {},
	}
	player.playback_finished.connect(func(session_id: String, outcome: Dictionary) -> void:
		if session_id != SESSION_ID:
			return
		finish_state["finished"] = true
		finish_state["outcome"] = outcome.duplicate(true)
	)

	player.call("play_stream_package", SESSION_ID, package, false)
	await get_tree().process_frame
	await get_tree().process_frame
	var streaming_page: Control = player.get_node_or_null("%StreamingPage") as Control
	var playback_page: Control = player.get_node_or_null("%PlaybackPage") as Control
	if streaming_page == null or not streaming_page.visible:
		push_error("FAIL: StreamingPage should be visible during stream")
	else:
		print("  OK: StreamingPage visible")
	if playback_page != null and playback_page.visible:
		push_error("FAIL: PlaybackPage should stay hidden during stream")
	else:
		print("  OK: PlaybackPage hidden")

	await _assert_stream_layout(stream_view)
	await _wait_for_chat_count(stream_view, 4, 8.0)
	_assert_midplay_content(stream_view)
	await _wait_for_chat_count(stream_view, 14, 24.0)

	var skip_button: Button = stream_view.get_node_or_null("%SkipButton") as Button if stream_view != null else null
	if skip_button != null:
		skip_button.pressed.emit()
		await get_tree().process_frame
		print("  OK: Skip accepts input during long stream")

	var elapsed := 0.0
	while not bool(finish_state.get("finished", false)) and elapsed < 8.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()

	if not bool(finish_state.get("finished", false)):
		push_error("FAIL: streaming playback did not finish")
		return
	var finished_outcome: Dictionary = finish_state.get("outcome", {})
	if not bool(finished_outcome.get("success", false)):
		push_error("FAIL: streaming outcome should succeed: %s" % str(finished_outcome))
	else:
		print("  OK: streaming playback_finished emitted")

	var chat_list: VBoxContainer = stream_view.get_node_or_null("%ChatList") as VBoxContainer if stream_view != null else null
	if chat_list == null or chat_list.get_child_count() < 14:
		push_error("FAIL: long stream should render many chat messages, got %d" % (chat_list.get_child_count() if chat_list != null else 0))
	else:
		print("  OK: long chat rendered (%d messages)" % chat_list.get_child_count())

	var return_elapsed := 0.0
	while return_elapsed < 1.7:
		await get_tree().process_frame
		return_elapsed += get_process_delta_time()
	if streaming_page == null or not streaming_page.visible:
		push_error("FAIL: player should return to live-room home after stream")
	else:
		print("  OK: returned to live-room home after stream")
	var idle_title: Label = stream_view.get_node_or_null("%StreamTitleLabel") as Label if stream_view != null else null
	var idle_bg: TextureRect = stream_view.get_node_or_null("%BackgroundTexture") as TextureRect if stream_view != null else null
	if idle_title == null or idle_title.text != "Mirai 的直播间":
		push_error("FAIL: live-room home should show idle title")
	elif idle_bg == null or idle_bg.texture == null:
		push_error("FAIL: live-room home should show offline CG")
	else:
		print("  OK: live-room home shows offline CG")

	print("=== Streaming AVG realistic playback test done ===")


func _setup_window_manager() -> Node:
	_wm = WindowManager.new()
	_wm.name = "WindowManager"
	add_child(_wm)

	var container := Control.new()
	container.name = "WindowContainer"
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	await get_tree().process_frame
	_wm.window_container = container

	var app_manager: Node = get_node_or_null("/root/AppManager")
	if app_manager == null:
		push_error("FAIL: AppManager autoload missing")
		return null
	app_manager.window_manager = _wm
	if not app_manager.app_registry.has(APP_ID):
		push_error("FAIL: avg_player app should be registered")
		return null
	return app_manager


func _assert_real_app_window(window: Control, player: Control) -> void:
	if _wm == null or _wm.get_windows().is_empty():
		push_error("FAIL: avg_player should be opened through WindowManager")
		return
	if _wm.get_windows()[0] != window:
		push_error("FAIL: launched window should be tracked by WindowManager")

	var content_container: Control = window.get_node_or_null("ContentContainer") as Control
	if content_container == null:
		push_error("FAIL: PseudoWindow ContentContainer missing")
		return
	if window.size.x < 1024.0 or window.size.y < 768.0:
		push_error("FAIL: dilidili window should respect app min size, got %s" % str(window.size))
	else:
		print("  OK: launched through real dilidili window size %s" % str(window.size))

	if absf((content_container.size.x / maxf(content_container.size.y, 1.0)) - (16.0 / 9.0)) > 0.02:
		push_error("FAIL: dilidili content area should stay 16:9, got %s" % str(content_container.size))
	else:
		print("  OK: dilidili content area is 16:9 at %s" % str(content_container.size))

	if player.size.distance_to(content_container.size) > 2.0:
		push_error("FAIL: DateEventPlayer should fill PseudoWindow content, player=%s content=%s" % [str(player.size), str(content_container.size)])
	else:
		print("  OK: DateEventPlayer fills real window content")


func _build_long_stream_script() -> String:
	return """
@stream "买了老游嘛" host=LinXia viewers=228 day="第3天"
bg bg_apartment_living
host LinXia happy casual
say "大家好，今天不是新游首播，今天我们回去补一款很老、但我一直没舍得删的游戏。"
chat "爷青回！"
chat "这游戏我小时候看我哥玩过"
chat "主播终于要补这个系列了"
emotion soft_smile
say "我以前只玩过第二作，第一作一直躺在收藏夹里，封面都快被我看出包浆了。"
chat "封面包浆是什么形容啦"
chat "老游戏的启动器才是第一关"
say "刚才开播前我试了一下，分辨率只能选四比三，鼠标灵敏度还像在冰上滑。"
chat "味儿对了"
chat "四比三才有灵魂"
emotion happy
say "但它的标题音乐一响，我就突然明白为什么那么多人会记住它。"
chat "BGM爱了"
chat "老游戏音乐真的很敢写"
say "等下我会先跑一遍开场，不查攻略，卡住了再求助弹幕。"
chat "已准备搜索引擎"
chat "不要查！先吃瘪！"
emotion default
say "你们这个不要查的语气，好像已经等着看我被第一个机关教育了。"
chat "懂你"
chat "第一个机关很经典"
say "不过今天重点不是速通，是想看看这套系统为什么到现在还会被人提起。"
chat "认真模式启动"
chat "我喜欢这种慢慢看的直播"
emotion soft_smile
say "如果有机会，我想把整个系列都按发售顺序玩一遍，然后做一期整理视频。"
chat "支持！"
chat "可以顺便讲讲版本差异吗"
say "可以。今天先从这里开始，开场动画不要跳，我想听完整。"
chat "不跳OP，好文明"
chat "开灯关灯，仪式感拉满"
wait 2.0
end
"""


func _assert_stream_layout(stream_view: Control) -> void:
	if stream_view == null:
		push_error("FAIL: StreamingAVGPlayer missing")
		return
	var video_frame: Control = stream_view.get_node_or_null("%VideoFrame") as Control
	var stream_layout: Control = stream_view.get_node_or_null("%StreamLayout") as Control
	var chat_panel: PanelContainer = stream_view.get_node_or_null("%ChatPanel") as PanelContainer
	var stage_design: Control = stream_view.get_node_or_null("%StageDesign") as Control
	var subtitle_panel: Control = stream_view.get_node_or_null("%SubtitlePanel") as Control
	var chat_scroll: ScrollContainer = stream_view.get_node_or_null("%ChatScroll") as ScrollContainer
	if video_frame == null or stream_layout == null or chat_panel == null or stage_design == null or subtitle_panel == null or chat_scroll == null:
		push_error("FAIL: required streaming layout nodes missing")
		return
	await get_tree().process_frame
	var ratio := video_frame.size.x / maxf(video_frame.size.y, 1.0)
	if absf(ratio - (4.0 / 3.0)) > 0.01:
		push_error("FAIL: video frame should stay 4:3 in real dilidili window, got size=%s ratio=%.3f" % [str(video_frame.size), ratio])
	else:
		print("  OK: video frame stays 4:3 at %s" % str(video_frame.size))
	if video_frame.size.x > 980.0 or video_frame.size.y > 740.0:
		push_error("FAIL: video frame should stay compact, got %s" % str(video_frame.size))
	if chat_panel.size.x < 420.0 or chat_panel.size.x > 500.0:
		push_error("FAIL: chat panel should stay compact, got %s" % str(chat_panel.size))
	else:
		print("  OK: chat panel stays compact at %s" % str(chat_panel.size))
	if stream_layout.size.x > 1520.0:
		push_error("FAIL: streaming content should not fill the whole app width, got %s" % str(stream_layout.size))
	else:
		print("  OK: streaming content width is constrained at %.1f" % stream_layout.size.x)
	if stage_design.size != Vector2(1024, 768):
		push_error("FAIL: stage design should stay 1024x768, got %s" % str(stage_design.size))
	else:
		print("  OK: stage design uses 1024x768")
	if subtitle_panel.size.x < 650.0:
		push_error("FAIL: subtitle panel too narrow for real subtitle text: %s" % str(subtitle_panel.size))
	if chat_scroll.size.y < 430.0 or chat_scroll.size.y > 680.0:
		push_error("FAIL: chat panel height should follow compact video area: %s" % str(chat_scroll.size))


func _assert_midplay_content(stream_view: Control) -> void:
	if stream_view == null:
		return
	var subtitle_label: Label = stream_view.get_node_or_null("%SubtitleLabel") as Label
	var chat_list: VBoxContainer = stream_view.get_node_or_null("%ChatList") as VBoxContainer
	if subtitle_label == null or subtitle_label.text.strip_edges().is_empty():
		push_error("FAIL: long subtitle text should be visible during playback")
	else:
		print("  OK: long subtitle visible during playback")
	if chat_list == null or chat_list.get_child_count() < 4:
		push_error("FAIL: chat should accumulate during playback")
	else:
		print("  OK: chat accumulates during playback")


func _wait_for_chat_count(stream_view: Control, target_count: int, timeout: float) -> void:
	var elapsed := 0.0
	while elapsed < timeout:
		var chat_list: VBoxContainer = stream_view.get_node_or_null("%ChatList") as VBoxContainer if stream_view != null else null
		if chat_list != null and chat_list.get_child_count() >= target_count:
			return
		await get_tree().process_frame
		elapsed += get_process_delta_time()
