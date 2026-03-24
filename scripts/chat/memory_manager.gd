class_name MemoryManager extends Node
## 记忆管理器
## 管理NPC对玩家的记忆：存储、检索、压缩

## 记忆存储路径
const MEMORY_BASE_PATH: String = "user://memory/"
const RUN_MEMORY_RELATIVE_PATH: String = "memory/"

## 内存缓存：npc_id -> Array[MemoryEntry]
var _memory_cache: Dictionary = {}

## 记忆索引：npc_id -> {tags: {tag: [memory_id]}, entities: {entity: [memory_id]}}
var _memory_index: Dictionary = {}


func _ready() -> void:
	_ensure_directory(_get_memory_base_path())


func reset_runtime_state(clear_disk: bool = false) -> void:
	_memory_cache.clear()
	_memory_index.clear()
	var base_path: String = _get_memory_base_path()
	if clear_disk and DirAccess.dir_exists_absolute(base_path):
		_remove_directory_recursive(base_path)
	_ensure_directory(base_path)


## 存储一条记忆
func store_memory(entry: MemoryEntry) -> void:
	if entry == null or entry.npc_id.is_empty():
		return

	if entry.memory_id.is_empty():
		entry.memory_id = _generate_id()

	if entry.timestamp == 0:
		entry.timestamp = int(Time.get_unix_time_from_system())

	# 添加到缓存
	if not _memory_cache.has(entry.npc_id):
		_memory_cache[entry.npc_id] = []
	_memory_cache[entry.npc_id].append(entry)

	# 更新索引
	_index_memory(entry)

	# 持久化
	_save_memory_to_disk(entry)


## 从Topic对话中提取并存储记忆（由TopicManager调用）
func store_topic_memory(topic_id: String, npc_id: String, summary: String, tags: Array[String] = [], importance: float = 0.5, emotional_valence: float = 0.0) -> void:
	var entry := MemoryEntry.new()
	entry.npc_id = npc_id
	entry.memory_type = MemoryEntry.MemoryType.EPISODIC
	entry.content = summary
	entry.tags = tags
	entry.importance = importance
	entry.emotional_valence = emotional_valence
	entry.source_topic_id = topic_id
	store_memory(entry)


## 检索相关记忆
func retrieve_memories(npc_id: String, query: String, max_count: int = 5) -> Array[MemoryEntry]:
	_ensure_loaded(npc_id)

	if not _memory_cache.has(npc_id):
		return []

	var memories: Array = _memory_cache[npc_id]
	var scored: Array[Dictionary] = []

	for memory in memories:
		if memory is MemoryEntry:
			var score := _calculate_relevance(memory, query)
			scored.append({"memory": memory, "score": score})

	# 按分数排序
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)

	var result: Array[MemoryEntry] = []
	for i in mini(max_count, scored.size()):
		var mem: MemoryEntry = scored[i].memory
		mem.access_count += 1
		mem.last_access_time = int(Time.get_unix_time_from_system())
		result.append(mem)

	return result


## 获取NPC的所有记忆
func get_all_memories(npc_id: String) -> Array[MemoryEntry]:
	_ensure_loaded(npc_id)
	if not _memory_cache.has(npc_id):
		return []

	var result: Array[MemoryEntry] = []
	for mem in _memory_cache[npc_id]:
		if mem is MemoryEntry:
			result.append(mem)
	return result


## 删除一条记忆
func remove_memory(npc_id: String, memory_id: String) -> void:
	if not _memory_cache.has(npc_id):
		return

	var memories: Array = _memory_cache[npc_id]
	for i in range(memories.size() - 1, -1, -1):
		if memories[i] is MemoryEntry and memories[i].memory_id == memory_id:
			var mem: MemoryEntry = memories[i]
			_unindex_memory(mem)
			memories.remove_at(i)
			_delete_memory_from_disk(mem)
			break


## 清理低强度旧记忆
func clean_weak_memories(npc_id: String, age_days: int = 30, strength_threshold: float = 0.1) -> int:
	_ensure_loaded(npc_id)
	if not _memory_cache.has(npc_id):
		return 0

	var cutoff_time: int = int(Time.get_unix_time_from_system()) - age_days * 86400
	var removed_count: int = 0
	var memories: Array = _memory_cache[npc_id]

	for i in range(memories.size() - 1, -1, -1):
		var mem: MemoryEntry = memories[i]
		if mem.timestamp < cutoff_time and mem.get_memory_strength() < strength_threshold:
			_unindex_memory(mem)
			_delete_memory_from_disk(mem)
			memories.remove_at(i)
			removed_count += 1

	return removed_count


# --- 相关性计算 ---

func _calculate_relevance(memory: MemoryEntry, query: String) -> float:
	var score: float = 0.0

	# 文本相似度（关键词匹配）
	score += _text_similarity(memory.content, query) * 0.4

	# 标签匹配
	score += _tag_match(memory.tags, query) * 0.3

	# 记忆强度
	score += memory.get_memory_strength() * 0.2

	# 最近访问加成
	score += _recency_boost(memory.last_access_time) * 0.1

	return score


func _text_similarity(text1: String, text2: String) -> float:
	var words1 := text1.to_lower().split(" ", false)
	var words2 := text2.to_lower().split(" ", false)

	if words1.is_empty() or words2.is_empty():
		return 0.0

	var common: int = 0
	for word in words1:
		if word.length() > 1 and word in words2:
			common += 1

	return float(common) / maxf(float(words1.size()), float(words2.size()))


func _tag_match(tags: Array[String], query: String) -> float:
	if tags.is_empty():
		return 0.0

	var query_lower := query.to_lower()
	var matched: int = 0
	for tag in tags:
		if tag.to_lower() in query_lower:
			matched += 1

	return float(matched) / float(tags.size())


func _recency_boost(last_access: int) -> float:
	if last_access == 0:
		return 0.0
	var hours_ago := float(Time.get_unix_time_from_system() - last_access) / 3600.0
	return clampf(1.0 - hours_ago / 168.0, 0.0, 1.0)  # 7天内衰减


# --- 索引管理 ---

func _index_memory(entry: MemoryEntry) -> void:
	if not _memory_index.has(entry.npc_id):
		_memory_index[entry.npc_id] = {"tags": {}, "entities": {}}

	var index: Dictionary = _memory_index[entry.npc_id]

	for tag in entry.tags:
		if not index.tags.has(tag):
			index.tags[tag] = []
		index.tags[tag].append(entry.memory_id)

	for entity in entry.related_entities:
		if not index.entities.has(entity):
			index.entities[entity] = []
		index.entities[entity].append(entry.memory_id)


func _unindex_memory(entry: MemoryEntry) -> void:
	if not _memory_index.has(entry.npc_id):
		return

	var index: Dictionary = _memory_index[entry.npc_id]

	for tag in entry.tags:
		if index.tags.has(tag):
			index.tags[tag].erase(entry.memory_id)

	for entity in entry.related_entities:
		if index.entities.has(entity):
			index.entities[entity].erase(entry.memory_id)


# --- 持久化 ---

func _ensure_loaded(npc_id: String) -> void:
	if _memory_cache.has(npc_id):
		return
	_load_memories_from_disk(npc_id)


func _load_memories_from_disk(npc_id: String) -> void:
	var dir_path := _get_memory_base_path() + npc_id + "/"
	_memory_cache[npc_id] = []

	var dir := DirAccess.open(dir_path)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var full_path := dir_path + file_name
			var file := FileAccess.open(full_path, FileAccess.READ)
			if file:
				var json_text := file.get_as_text()
				file.close()
				var entry := _deserialize_memory(json_text)
				if entry:
					_memory_cache[npc_id].append(entry)
					_index_memory(entry)
		file_name = dir.get_next()
	dir.list_dir_end()


func _save_memory_to_disk(entry: MemoryEntry) -> void:
	var dir_path := _get_memory_base_path() + entry.npc_id + "/"
	_ensure_directory(dir_path)

	var file_path := dir_path + entry.memory_id + ".json"
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_serialize_memory(entry), "\t"))
		file.close()


func _delete_memory_from_disk(entry: MemoryEntry) -> void:
	var file_path := _get_memory_base_path() + entry.npc_id + "/" + entry.memory_id + ".json"
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)


func _serialize_memory(entry: MemoryEntry) -> Dictionary:
	return {
		"memory_id": entry.memory_id,
		"npc_id": entry.npc_id,
		"memory_type": entry.memory_type,
		"timestamp": entry.timestamp,
		"content": entry.content,
		"tags": entry.tags,
		"related_entities": entry.related_entities,
		"importance": entry.importance,
		"emotional_valence": entry.emotional_valence,
		"access_count": entry.access_count,
		"last_access_time": entry.last_access_time,
		"source_channel_id": entry.source_channel_id,
		"source_topic_id": entry.source_topic_id,
		"source_type": entry.source_type,
	}


func _deserialize_memory(json_text: String) -> MemoryEntry:
	var data: Variant = JSON.parse_string(json_text)
	if data == null or not data is Dictionary:
		return null

	var entry := MemoryEntry.new()
	entry.memory_id = data.get("memory_id", "")
	entry.npc_id = data.get("npc_id", "")
	entry.memory_type = data.get("memory_type", 0)
	entry.timestamp = data.get("timestamp", 0)
	entry.content = data.get("content", "")
	entry.importance = data.get("importance", 0.5)
	entry.emotional_valence = data.get("emotional_valence", 0.0)
	entry.access_count = data.get("access_count", 0)
	entry.last_access_time = data.get("last_access_time", 0)
	entry.source_channel_id = data.get("source_channel_id", "")
	entry.source_topic_id = data.get("source_topic_id", "")
	entry.source_type = data.get("source_type", "")

	var tags_data: Variant = data.get("tags", [])
	if tags_data is Array:
		for tag in tags_data:
			entry.tags.append(str(tag))

	var entities_data: Variant = data.get("related_entities", [])
	if entities_data is Array:
		for entity in entities_data:
			entry.related_entities.append(str(entity))

	return entry


# --- 工具方法 ---

func _generate_id() -> String:
	return "mem_%d_%d" % [Time.get_unix_time_from_system(), randi() % 10000]


func _ensure_directory(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)


func _get_memory_base_path() -> String:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		var run_manager: Node = tree.root.get_node_or_null("/root/CampaignRunManager")
		if run_manager != null and run_manager.has_method("get_run_root_path"):
			var run_root_path: String = str(run_manager.call("get_run_root_path")).strip_edges()
			if not run_root_path.is_empty():
				if not run_root_path.ends_with("/"):
					run_root_path += "/"
				return run_root_path + RUN_MEMORY_RELATIVE_PATH
	return MEMORY_BASE_PATH


func _remove_directory_recursive(dir_path: String) -> Error:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return ERR_CANT_OPEN

	dir.list_dir_begin()
	var item_name: String = dir.get_next()
	while item_name != "":
		if not item_name.begins_with("."):
			var item_path: String = dir_path + item_name
			if dir.current_is_dir():
				_remove_directory_recursive(item_path + "/")
				DirAccess.remove_absolute(item_path)
			else:
				DirAccess.remove_absolute(item_path)
		item_name = dir.get_next()
	dir.list_dir_end()

	return DirAccess.remove_absolute(dir_path)
