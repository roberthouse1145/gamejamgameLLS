extends Control
## 摸鱼冲浪 Surf Action 集成测试场景
##
## 启动后自动打开 Browser APP，由用户手动验证：
##   1. 主页应是 PixelNet 起始页（品牌区 + 搜索框 + 快捷入口）
##   2. 输入任意关键词 → 点 [开始冲浪] → 搜索区进入等待/禁用状态，看 console 出现
##        [surf] STARTED → [surf] COMPLETED；AP 应减 1
##   3. LinChat 林夏 DM 应收到一张 web_page 卡片 + 一条短消息
##   4. 同关键词再点一次 → 秒开（缓存命中）→ AP 不变 → 林夏 DM 不增加新卡片

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
	print("  1. 主页应显示 PixelNet 品牌区、搜索框和快捷入口")
	print("  2. 输入任意关键词（如『红烧肉』）→ 点击 [开始冲浪]")
	print("  3. 等待期间应出现动画 loading，搜索入口不可重复提交")
	print("  4. 观察 console: surf_started → surf_completed，AP 应减 1")
	print("  5. LinChat 林夏 DM 应收到一张 web_page 卡片 + 一句短消息")
	print("  6. 同关键词再点一次 → 应秒开（缓存命中）→ AP 不变")


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
