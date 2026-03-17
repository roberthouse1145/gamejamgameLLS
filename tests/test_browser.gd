extends Control
## 浏览器主流程测试场景
## 启动后自动打开浏览器 APP，由用户手动测试：
##   1. 在地址栏输入关键词 → 点搜索 → 验证搜索结果
##   2. 点击搜索结果的"打开网页"→ 验证网页生成渲染
##   3. 点刷新 → 验证重新生成（不会创建新标签页）

var _wm: WindowManager = null


func _ready() -> void:
	print("\n================================")
	print("=== Browser 主流程测试场景 ===")
	print("================================\n")

	# 设置 WindowManager
	_wm = WindowManager.new()
	_wm.name = "WindowManager"
	add_child(_wm)

	# 设置 window_container（窗口将添加到这里）
	var container := Control.new()
	container.name = "WindowContainer"
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	_wm.window_container = container

	# 连接 AppManager
	var am: Node = get_node_or_null("/root/AppManager")
	if am == null:
		push_error("TestBrowser: AppManager autoload 不存在")
		return
	am.window_manager = _wm

	# 检查 BrowserManager
	var bm: Node = get_node_or_null("/root/BrowserManager")
	if bm == null:
		push_error("TestBrowser: BrowserManager autoload 不存在")
		return

	print("[✓] WindowManager 已创建")
	print("[✓] AppManager.window_manager 已设置")
	print("[✓] BrowserManager 已加载")

	# 连接 BrowserManager 信号用于日志
	bm.search_completed.connect(_on_search_completed)
	bm.search_failed.connect(_on_search_failed)
	bm.page_generated.connect(_on_page_generated)
	bm.page_failed.connect(_on_page_failed)

	# 启动浏览器
	print("\n[启动] 正在打开 Browser APP...")
	var window: Control = am.launch_app("browser")
	if window == null:
		push_error("TestBrowser: 启动 browser 失败")
		return

	print("[✓] Browser APP 已启动")
	print("\n========== 手动测试步骤 ==========")
	print("1. 在地址栏输入关键词(如: 新闻), 点击搜索")
	print("2. 等待搜索结果卡片出现")
	print("3. 点击某个结果的[打开网页]按钮")
	print("4. 等待网页 JSON 渲染完成")
	print("5. 点击刷新按钮, 检查是否在当前标签页内刷新")
	print("====================================\n")


func _on_search_completed(_request_id: String, keyword: String, results: Array) -> void:
	print("[BM-LOG] 搜索完成: keyword='%s', 结果数=%d" % [keyword, results.size()])
	for i in range(results.size()):
		var r: Dictionary = results[i]
		print("  [%d] %s → %s" % [i, r.get("title", "?"), r.get("url", "?")])


func _on_search_failed(_request_id: String, keyword: String, error: String) -> void:
	print("[BM-LOG] 搜索失败: keyword='%s', error='%s'" % [keyword, error])


func _on_page_generated(_request_id: String, url: String, content: Dictionary) -> void:
	print("[BM-LOG] 网页生成: url='%s', title='%s', keys=%s" % [
		url,
		content.get("title", "无"),
		str(content.keys())
	])


func _on_page_failed(_request_id: String, url: String, error: String) -> void:
	print("[BM-LOG] 网页生成失败: url='%s', error='%s'" % [url, error])
