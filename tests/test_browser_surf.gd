extends Control
## 摸鱼冲浪 Surf Action 集成测试场景
##
## 启动后自动打开 Browser APP，由用户手动验证：
##   1. 主页应是 Browser 起始页（品牌区 + 快捷入口），不显示搜索框
##   2. 旧 surf 页面动作若被触发，应快速进入关闭提示
##   3. AP 不应因 Browser surf 扣除，林夏 DM 不应新增冲浪卡片

var _wm: WindowManager = null


func _ready() -> void:
	print("\n========================================")
	print("=== 摸鱼冲浪 Surf Action 集成测试 ===")
	print("========================================\n")

	_wm = WindowManager.new()
	_wm.name = "WindowManager"
	add_child(_wm)

	var container := Control.new()
	container.name = "WindowContainer"
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	_wm.window_container = container

	var am: Node = get_node_or_null("/root/AppManager")
	if am == null:
		push_error("TestBrowserSurf: AppManager 不存在")
		return
	am.window_manager = _wm

	var bm: Node = get_node_or_null("/root/BrowserManager")
	if bm == null:
		push_error("TestBrowserSurf: BrowserManager 不存在")
		return

	bm.surf_started.connect(_on_surf_started)
	bm.surf_completed.connect(_on_surf_completed)
	bm.surf_failed.connect(_on_surf_failed)

	var glm: Node = get_node_or_null("/root/GameLoopManager")
	if glm != null and glm.has_signal("ap_changed"):
		glm.ap_changed.connect(_on_ap_changed)

	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null and gm.has_signal("stats_changed"):
		gm.stats_changed.connect(_on_stats_changed)

	var chat: Node = get_node_or_null("/root/ChatManager")
	if chat != null and chat.has_signal("message_added"):
		chat.message_added.connect(_on_message_added)

	var window: Control = am.launch_app("browser")
	if window == null:
		push_error("TestBrowserSurf: 启动 browser 失败")
		return

	print("[✓] Browser 已启动，请手动测试：")
	print("  1. 主页应显示 Browser 品牌区和快捷入口，不显示搜索框")
	print("  2. 旧 surf 页面动作若被触发，应输出 surf_failed")
	print("  3. AP 不应扣除，LinChat 林夏 DM 不应新增冲浪卡片")


func _on_surf_started(request_id: String, keyword: String) -> void:
	print("[surf] STARTED  request=%s keyword='%s'" % [request_id, keyword])


func _on_surf_completed(request_id: String, keyword: String, url: String, summary: String, page: Dictionary) -> void:
	print("[surf] COMPLETED request=%s keyword='%s'" % [request_id, keyword])
	print("       url=%s" % url)
	print("       summary=%s" % summary)
	print("       page keys=%s" % str(page.keys()))


func _on_surf_failed(request_id: String, keyword: String, error: String) -> void:
	print("[surf] FAILED   request=%s keyword='%s' error='%s'" % [request_id, keyword, error])


func _on_ap_changed(current: int, max_ap: int) -> void:
	print("[AP] %d / %d" % [current, max_ap])


func _on_stats_changed(stats: Dictionary) -> void:
	print("[stats] changed: %s" % str(stats))


func _on_message_added(channel_id: String, msg_data: Dictionary) -> void:
	if channel_id != "dm_lin_xia":
		return
	var card: Dictionary = msg_data.get("card", {})
	if card.is_empty():
		print("[chat] 林夏: %s" % str(msg_data.get("content", "")))
	else:
		print("[chat] 林夏 DM 收到卡片: type=%s title='%s' url='%s'" % [
			str(card.get("type", "")),
			str(card.get("title", "")),
			str(card.get("url", "")),
		])
