extends PanelContainer
class_name DeepCodeDebugPanel
## Debug 面板 — 显示当前 system prompt、tool 调用记录、active skills

signal visibility_toggled(visible: bool)

@onready var tab_bar: TabBar = %DebugTabBar
@onready var prompt_text: RichTextLabel = %PromptText
@onready var tool_log_text: RichTextLabel = %ToolLogText
@onready var prompt_page: ScrollContainer = %PromptPage
@onready var tool_log_page: ScrollContainer = %ToolLogPage

var _tool_log_entries: Array[String] = []
const MAX_LOG_ENTRIES: int = 200


func _ready() -> void:
	_apply_theme()
	if tab_bar:
		tab_bar.add_tab("System Prompt")
		tab_bar.add_tab("Tool Log")
		tab_bar.current_tab = 0
		tab_bar.tab_changed.connect(_on_tab_changed)
	_show_page(0)


func _apply_theme() -> void:
	# Panel stylebox — 由 deepcode_dark.tres Theme 提供，无需 override
	# TabBar 颜色、RichTextLabel 颜色 — 由 Theme 提供，无需 override
	pass


## 更新 system prompt 显示
func update_prompt(prompt: String) -> void:
	if prompt_text:
		prompt_text.clear()
		if prompt.is_empty():
			prompt_text.append_text("[color=#707070](prompt 尚未初始化)[/color]")
		else:
			# 高亮 {%skill_prompt%} 标记和 # 标题
			var display: String = prompt.replace("{%skill_prompt%}", "[color=#d4a574]{%skill_prompt%}[/color]")
			prompt_text.append_text(display)


## 添加 tool 调用日志
func add_tool_log(tool_name: String, args: String, result: String = "") -> void:
	var timestamp: String = Time.get_time_string_from_system()
	var entry: String = "[color=#707070]%s[/color] [color=#d4a574]%s[/color]" % [timestamp, tool_name]
	if not args.is_empty():
		entry += "\n  args: %s" % args.left(300)
	if not result.is_empty():
		entry += "\n  [color=#98c379]→ %s[/color]" % result.left(300)

	_tool_log_entries.append(entry)
	if _tool_log_entries.size() > MAX_LOG_ENTRIES:
		_tool_log_entries.pop_front()

	_refresh_tool_log()


## 添加通用日志条目
func add_log(text: String, color: String = "#a0a0a0") -> void:
	var timestamp: String = Time.get_time_string_from_system()
	var entry: String = "[color=#707070]%s[/color] [color=%s]%s[/color]" % [timestamp, color, text]
	_tool_log_entries.append(entry)
	if _tool_log_entries.size() > MAX_LOG_ENTRIES:
		_tool_log_entries.pop_front()
	_refresh_tool_log()


## 清空日志
func clear_log() -> void:
	_tool_log_entries.clear()
	_refresh_tool_log()


func _refresh_tool_log() -> void:
	if tool_log_text == null:
		return
	tool_log_text.clear()
	if _tool_log_entries.is_empty():
		tool_log_text.append_text("[color=#707070](暂无日志)[/color]")
	else:
		tool_log_text.append_text("\n".join(_tool_log_entries))
	# 自动滚到底部
	if tool_log_page:
		tool_log_page.scroll_vertical = int(tool_log_page.get_v_scroll_bar().max_value)


func _on_tab_changed(tab: int) -> void:
	_show_page(tab)


func _show_page(index: int) -> void:
	if prompt_page:
		prompt_page.visible = (index == 0)
	if tool_log_page:
		tool_log_page.visible = (index == 1)
