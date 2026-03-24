class_name InputGuard extends Node
## 玩家输入审核器
## 使用 doubao-mini 快速判断玩家消息是否合规
## 返回 true 放行，false 拒绝。超时视为放行。

const GUARD_TIMEOUT: float = 3.0
const PROMPT_PATH: String = "res://prompts/input_guard.md"

signal check_completed(passed: bool)

var enabled: bool = true
var _ai_service: AIService
var _system_prompt: String = ""
var _pending: bool = false


func _ready() -> void:
	_ai_service = AIService.new()
	_ai_service.timeout = GUARD_TIMEOUT
	_ai_service.default_max_tokens = 8
	_ai_service.default_temperature = 0.0
	_ai_service.max_retries = 0
	add_child(_ai_service)

	_ai_service.request_completed.connect(_on_request_completed)
	_ai_service.request_failed.connect(_on_request_failed)

	# 加载 prompt
	if FileAccess.file_exists(PROMPT_PATH):
		var f := FileAccess.open(PROMPT_PATH, FileAccess.READ)
		if f:
			_system_prompt = f.get_as_text().strip_edges()

	# 加载 AI 配置
	var config_mgr := AIConfigManager.new()
	if config_mgr.load_config():
		config_mgr.apply_to_service(_ai_service, "input_guard")


## 审核玩家消息，返回 true（放行）或 false（拒绝）
func check(text: String) -> bool:
	if not enabled:
		return true
	if text.strip_edges().is_empty():
		return true
	if _system_prompt.is_empty():
		return true

	_pending = true
	_ai_service.chat_simple(text, _system_prompt)

	# 等待结果或超时
	var passed: bool = await check_completed
	_pending = false
	return passed


func _on_request_completed(_request_id: String, response: Dictionary) -> void:
	if not _pending:
		return
	var content: String = AIService.extract_content(response).strip_edges().to_lower()
	var passed: bool = content.begins_with("true")
	print("[InputGuard] Result: %s (raw: %s)" % [passed, content])
	check_completed.emit(passed)


func _on_request_failed(_request_id: String, error: String, _error_code: int) -> void:
	if not _pending:
		return
	# 失败时放行，不阻塞玩家
	print("[InputGuard] Request failed, passing through: %s" % error)
	check_completed.emit(true)
