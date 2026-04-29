class_name StoryCompiler
## 剧本编译器
## 扫描 .txt/.json 源文件 → 编译为 .tres 资源 → 生成索引
## 编辑器/调试模式下自动调用，导出版直接读取编译产物

const StoryStepClass = preload("res://scripts/story/resources/story_step.gd")
const StoryChapterClass = preload("res://scripts/story/resources/story_chapter.gd")
const StoryChapterIndexClass = preload("res://scripts/story/resources/story_chapter_index.gd")
const StoryScriptParserClass = preload("res://scripts/story/story_script_parser.gd")

const CHAPTERS_DIR := "res://resources/story/chapters/"
const GENERATED_DIR := "res://resources/story/generated/"
const INDEX_PATH := "res://resources/story/story_index.tres"


## 编译所有章节源文件 → .tres + 索引
## 返回 StoryChapterIndex 资源
static func compile_all() -> Resource:
	var index := StoryChapterIndexClass.new()

	# 确保输出目录存在
	if not DirAccess.dir_exists_absolute(GENERATED_DIR):
		DirAccess.make_dir_recursive_absolute(GENERATED_DIR)
	_clear_generated_outputs()

	var source_files: Dictionary = _scan_sources()
	if source_files.is_empty():
		print("[StoryCompiler] No chapter sources found in %s" % CHAPTERS_DIR)
		_write_index(index)
		return index

	var base_names: Array = source_files.keys()
	base_names.sort()
	for base_name in base_names:
		var src_path: String = source_files[base_name]
		var data: Dictionary = _parse_source(src_path)
		if data.is_empty():
			push_warning("[StoryCompiler] Failed to parse: %s" % src_path)
			continue

		var chapter: Resource = build_chapter_from_dict(data)
		if chapter == null or chapter.chapter_id.is_empty():
			push_warning("[StoryCompiler] Invalid chapter data in: %s" % src_path)
			continue

		var out_path: String = GENERATED_DIR + chapter.chapter_id + ".tres"
		var err: Error = ResourceSaver.save(chapter, out_path)
		if err != OK:
			push_warning("[StoryCompiler] Failed to save: %s (error %d)" % [out_path, err])
			continue

		var compiled_chapter: Resource = ResourceLoader.load(out_path)
		if compiled_chapter == null:
			push_warning("[StoryCompiler] Failed to reload compiled chapter: %s" % out_path)
			continue

		index.chapters.append(compiled_chapter)
		index.chapter_sources[chapter.chapter_id] = src_path
		index.compiled_paths[chapter.chapter_id] = out_path
		print("[StoryCompiler] Compiled: %s → %s" % [src_path, out_path])

	_write_index(index)
	return index


## 读取编译后的索引资源
static func load_index_resource() -> Resource:
	if not ResourceLoader.exists(INDEX_PATH):
		return null
	return ResourceLoader.load(INDEX_PATH)


## 从 Dictionary 构建 StoryChapter 资源（公开供外部复用）
static func build_chapter_from_dict(data: Dictionary) -> Resource:
	var chapter := StoryChapterClass.new()
	chapter.chapter_id = str(data.get("chapter_id", ""))
	chapter.chapter_name = str(data.get("chapter_name", ""))
	chapter.description = str(data.get("description", ""))
	var trigger_raw: Variant = data.get("trigger", {})
	if trigger_raw is Dictionary:
		chapter.trigger = (trigger_raw as Dictionary).duplicate(true)
	chapter.priority = int(data.get("priority", 0))
	chapter.next_chapter = str(data.get("next_chapter", ""))

	var steps_data: Array = data.get("steps", [])
	for step_data in steps_data:
		if not step_data is Dictionary:
			continue
		var step := StoryStepClass.new()
		step.step_id = str(step_data.get("step_id", ""))
		step.description = str(step_data.get("description", ""))
		step.next = str(step_data.get("next", ""))

		var actions_raw: Array = step_data.get("actions", [])
		for a in actions_raw:
			if a is Dictionary:
				step.actions.append(a)

		var wait_raw: Variant = step_data.get("wait_for", {})
		if wait_raw is Dictionary:
			step.wait_for = wait_raw

		var capture_raw: Variant = step_data.get("capture", {})
		if capture_raw is Dictionary:
			step.capture = capture_raw

		var nc_raw: Array = step_data.get("next_conditions", [])
		for nc in nc_raw:
			if nc is Dictionary:
				step.next_conditions.append(nc)

		chapter.steps.append(step)

	return chapter


# ─── Internal ────────────────────────────────────────────────────────────────

static func _clear_generated_outputs() -> void:
	var dir := DirAccess.open(GENERATED_DIR)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var full_path := GENERATED_DIR + file_name
			var err := DirAccess.remove_absolute(full_path)
			if err != OK:
				push_warning("[StoryCompiler] Failed to remove stale output: %s (error %d)" % [full_path, err])
		file_name = dir.get_next()
	dir.list_dir_end()

## 扫描源目录（.txt 优先于同名 .json）
static func _scan_sources() -> Dictionary:
	var sources: Dictionary = {}
	var source_types: Dictionary = {}
	if not DirAccess.dir_exists_absolute(CHAPTERS_DIR):
		return sources

	var dir := DirAccess.open(CHAPTERS_DIR)
	if dir == null:
		return sources

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var base := file_name.get_basename()
			if file_name.ends_with(".txt"):
				if source_types.get(base, "") == "json":
					push_warning("[StoryCompiler] Duplicate chapter source found for '%s'. Preferring .txt over .json" % base)
				sources[base] = CHAPTERS_DIR + file_name
				source_types[base] = "txt"
			elif file_name.ends_with(".json"):
				if not sources.has(base):
					sources[base] = CHAPTERS_DIR + file_name
					source_types[base] = "json"
				else:
					push_warning("[StoryCompiler] Duplicate chapter source found for '%s'. Keeping existing %s source" % [base, source_types.get(base, "unknown")])
		file_name = dir.get_next()
	dir.list_dir_end()
	return sources


## 解析单个源文件
static func _parse_source(path: String) -> Dictionary:
	if path.ends_with(".txt"):
		return StoryScriptParserClass.parse_file(path)

	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return parsed
	return {}


## 写入索引资源
static func _write_index(index: Resource) -> void:
	var err := ResourceSaver.save(index, INDEX_PATH)
	if err != OK:
		push_warning("[StoryCompiler] Failed to write index: %s (error %d)" % [INDEX_PATH, err])
		return
	var chapter_count := 0
	if index is StoryChapterIndexClass:
		chapter_count = index.chapters.size()
	print("[StoryCompiler] Index written: %s (%d chapters)" % [INDEX_PATH, chapter_count])
