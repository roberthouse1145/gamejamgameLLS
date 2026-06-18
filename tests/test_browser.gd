extends Control
## 浏览器主流程测试场景
## 启动后自动打开浏览器 APP，由用户手动测试：
##   1. 主页不再显示动态搜索框和“开始冲浪”按钮
##   2. 点击首页快捷入口 → 验证预制页面打开
##   3. 输入未知 URL → 验证快速显示“网页生成暂时关闭”

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
	print("1. 主页不应显示动态搜索框和“开始冲浪”按钮")
	print("2. 点击首页快捷入口，检查预制页面能直接打开")
	print("3. 在地址栏输入未知 URL，检查是否快速显示“网页生成暂时关闭”")
	print("4. 点击刷新按钮，检查预制页面仍在当前标签页内刷新")
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
