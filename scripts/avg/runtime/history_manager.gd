class_name HistoryManager extends RefCounted
## 对话历史记录管理器
## 记录游戏中的对话文本，供历史记录界面显示。

## 单条历史记录
## {speaker: String, text: String, scene_id: String}

## 历史记录列表（最新在末尾）
var _entries: Array[Dictionary] = []

## 最大记录数
var max_entries: int = 500


## 添加一条对话记录
func add_entry(speaker: String, text: String, scene_id: String = "") -> void:
	_entries.append({
		"speaker": speaker,
		"text": text,
		"scene_id": scene_id,
	})
	if _entries.size() > max_entries:
		_entries.pop_front()


## 获取所有记录（最旧在前）
func get_entries() -> Array[Dictionary]:
	return _entries


## 获取最近 N 条记录
func get_recent(count: int) -> Array[Dictionary]:
	if count >= _entries.size():
		return _entries.duplicate()
	return _entries.slice(_entries.size() - count)


## 清空历史
func clear() -> void:
	_entries.clear()


## 序列化为可保存的数据
func to_data() -> Array:
	return _entries.duplicate()


## 从数据恢复
func from_data(data: Array) -> void:
	_entries.clear()
	for entry in data:
		if entry is Dictionary:
			_entries.append(entry)
