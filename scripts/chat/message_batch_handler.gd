class_name MessageBatchHandler extends Node
## 消息批处理器
## 玩家发送消息后等待10秒，期间可继续输入
## 超时或手动触发后整合所有消息为一次输入

## 批处理就绪，携带所有待发送消息
signal batch_ready(messages: Array[String])

## 批处理状态变化
signal batching_state_changed(is_batching: bool)

## 批处理超时时间（秒）
const BATCH_TIMEOUT: float = 10.0

var pending_messages: Array[String] = []
var _batch_timer: Timer
var _is_batching: bool = false


func _ready() -> void:
	_batch_timer = Timer.new()
	_batch_timer.one_shot = true
	_batch_timer.timeout.connect(_on_batch_timeout)
	add_child(_batch_timer)


## 添加一条玩家消息到批处理队列
func add_message(message: String) -> void:
	if message.strip_edges().is_empty():
		return

	pending_messages.append(message)

	# 重置计时器
	_batch_timer.start(BATCH_TIMEOUT)

	if not _is_batching:
		_is_batching = true
		batching_state_changed.emit(true)


## 强制立即发送（点击发送按钮时）
func force_send() -> void:
	if pending_messages.is_empty():
		return

	_batch_timer.stop()
	_flush()


## 是否正在批处理中
func is_batching() -> bool:
	return _is_batching


## 获取剩余等待时间
func get_remaining_time() -> float:
	if _batch_timer.is_stopped():
		return 0.0
	return _batch_timer.time_left


func _on_batch_timeout() -> void:
	_flush()


func _flush() -> void:
	if pending_messages.is_empty():
		return

	var messages := pending_messages.duplicate()
	pending_messages.clear()

	_is_batching = false
	batching_state_changed.emit(false)

	batch_ready.emit(messages)
