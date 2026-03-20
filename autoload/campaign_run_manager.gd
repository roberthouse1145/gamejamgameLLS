extends Node
## CampaignRunManager Autoload
## 管理单周目运行目录、当前进度 checkpoint、按天快照和导出版 runtime 工程挂载。

signal run_initialized(run_root_path: String)
signal checkpoint_saved(file_path: String)
signal checkpoint_loaded(success: bool)
signal day_snapshot_saved(day: int, file_path: String)

const SCHEMA_VERSION: int = 1
const RUN_ROOT_PATH: String = "user://run/"
const META_FILE_PATH: String = RUN_ROOT_PATH + "meta.json"
const CURRENT_STATE_FILE_PATH: String = RUN_ROOT_PATH + "current_state.json"
const DAYS_DIR_PATH: String = RUN_ROOT_PATH + "days/"
const PLAYER_PROJECT_DIR_PATH: String = RUN_ROOT_PATH + "player_project/"
const GENERATED_DIR_PATH: String = RUN_ROOT_PATH + "generated/"
const BROWSER_DIR_PATH: String = RUN_ROOT_PATH + "browser/"

const CHECKPOINT_DEBOUNCE_SECONDS: float = 0.2

var auto_save_enabled: bool = true

var _checkpoint_timer: Timer = null
var _checkpoint_dirty: bool = false
var _is_restoring: bool = false
var _is_initialized: bool = false
var _startup_restore_attempted: bool = false
var _startup_restore_succeeded: bool = false
var _startup_mode: String = "pending"
var _generated_registry: Dictionary = {"artifacts": []}


func _ready() -> void:
	_checkpoint_timer = Timer.new()
	_checkpoint_timer.one_shot = true
	_checkpoint_timer.wait_time = CHECKPOINT_DEBOUNCE_SECONDS
	_checkpoint_timer.timeout.connect(_flush_checkpoint_save)
	add_child(_checkpoint_timer)

	_ensure_run_directories()
	_ensure_meta_file()
	_mount_runtime_player_project_if_needed()
	call_deferred("_finish_startup")


func _finish_startup() -> void:
	_connect_state_sources()
	_is_initialized = true
	run_initialized.emit(RUN_ROOT_PATH)
	call_deferred("_attempt_startup_restore")


func get_run_root_path() -> String:
	return RUN_ROOT_PATH


func get_player_project_root_path() -> String:
	return PLAYER_PROJECT_DIR_PATH


func get_browser_history_path() -> String:
	return BROWSER_DIR_PATH + "history.json"


func get_generated_dir_path() -> String:
	return GENERATED_DIR_PATH


func get_generated_registry() -> Dictionary:
	return _generated_registry.duplicate(true)


func write_generated_activity_artifact(activity_type: String, session_id: String, artifact_name: String, data: Dictionary, metadata: Dictionary = {}) -> String:
	var safe_activity_type: String = _sanitize_path_segment(activity_type)
	var safe_session_id: String = _sanitize_path_segment(session_id)
	var safe_artifact_name: String = _sanitize_path_segment(artifact_name)
	if safe_activity_type.is_empty() or safe_session_id.is_empty() or safe_artifact_name.is_empty():
		return ""

	var relative_path: String = "generated/%s/%s/%s.json" % [
		safe_activity_type,
		safe_session_id,
		safe_artifact_name,
	]
	var file_payload: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"activity_type": activity_type.strip_edges(),
		"session_id": session_id.strip_edges(),
		"artifact_name": artifact_name.strip_edges(),
		"saved_at": Time.get_datetime_string_from_system(),
		"day": _get_current_day(),
		"metadata": metadata.duplicate(true),
		"data": data.duplicate(true),
	}
	var write_err: Error = _write_json_dict(RUN_ROOT_PATH + relative_path, file_payload)
	if write_err != OK:
		push_warning("[CampaignRunManager] Failed to persist generated artifact: %s" % relative_path)
		return ""

	var registry_metadata: Dictionary = metadata.duplicate(true)
	registry_metadata["session_id"] = session_id.strip_edges()
	registry_metadata["artifact_name"] = artifact_name.strip_edges()
	register_generated_artifact("%s_%s" % [safe_activity_type, safe_artifact_name], relative_path, registry_metadata)
	return relative_path


func register_generated_artifact(artifact_type: String, relative_path: String, metadata: Dictionary = {}) -> void:
	var normalized_type: String = artifact_type.strip_edges()
	var normalized_path: String = relative_path.strip_edges()
	if normalized_type.is_empty() or normalized_path.is_empty():
		return

	var artifacts: Array = _generated_registry.get("artifacts", [])
	for i in range(artifacts.size()):
		if not (artifacts[i] is Dictionary):
			continue
		var existing: Dictionary = artifacts[i]
		if str(existing.get("relative_path", "")) != normalized_path:
			continue
		existing["type"] = normalized_type
		existing["metadata"] = metadata.duplicate(true)
		existing["updated_at"] = Time.get_datetime_string_from_system()
		existing["day"] = _get_current_day()
		artifacts[i] = existing
		_generated_registry["artifacts"] = artifacts
		queue_checkpoint_save()
		return

	artifacts.append({
		"type": normalized_type,
		"relative_path": normalized_path,
		"metadata": metadata.duplicate(true),
		"created_at": Time.get_datetime_string_from_system(),
		"day": _get_current_day(),
	})
	_generated_registry["artifacts"] = artifacts
	queue_checkpoint_save()


func has_checkpoint() -> bool:
	return FileAccess.file_exists(CURRENT_STATE_FILE_PATH)


func get_startup_mode() -> String:
	return _startup_mode


func was_restored_on_startup() -> bool:
	return _startup_restore_succeeded


func continue_run() -> bool:
	if not has_checkpoint():
		return false
	var continued: bool = load_checkpoint()
	if continued:
		_startup_mode = "continued"
	return continued


func ensure_campaign_started(starting_chapter_id: String = "day1") -> bool:
	var story: Node = _get_autoload("StoryDirector")
	if story != null and story.has_method("has_active_story") and bool(story.call("has_active_story")):
		return true

	if OS.has_feature("editor"):
		if story != null and story.has_method("start_chapter"):
			_startup_mode = "editor_bootstrap"
			return bool(story.call("start_chapter", starting_chapter_id))
		return false

	if _startup_restore_succeeded:
		return true

	return start_new_run(starting_chapter_id)


func start_new_run(starting_chapter_id: String = "day1") -> bool:
	if not reset_run():
		return false

	var story: Node = _get_autoload("StoryDirector")
	var started: bool = story != null and story.has_method("start_chapter") and bool(story.call("start_chapter", starting_chapter_id))

	if not started:
		push_warning("[CampaignRunManager] Failed to bootstrap new run with chapter: %s" % starting_chapter_id)
		return false

	_startup_mode = "new_run"
	queue_checkpoint_save()
	return true


func reset_run() -> bool:
	if not _can_reset_run():
		push_warning("[CampaignRunManager] Cannot reset run while runtime systems are still busy")
		return false

	if _checkpoint_timer != null:
		_checkpoint_timer.stop()
	_checkpoint_dirty = false
	_is_restoring = true
	_startup_restore_attempted = true
	_startup_restore_succeeded = false
	_generated_registry = {"artifacts": []}

	_reset_all_runtime_state()
	_clear_run_storage()
	_ensure_run_directories()
	_ensure_meta_file()
	_mount_runtime_player_project_force()
	_is_restoring = false
	_startup_mode = "reset"
	return true


func queue_checkpoint_save() -> void:
	if not _is_initialized or not auto_save_enabled or _is_restoring:
		return
	_checkpoint_dirty = true
	if not _can_write_checkpoint():
		return
	if _checkpoint_timer != null:
		_checkpoint_timer.start()


func save_checkpoint() -> Error:
	var state: Dictionary = _build_run_state()
	if state.is_empty():
		return ERR_INVALID_DATA

	var save_err: Error = _write_json_dict(CURRENT_STATE_FILE_PATH, state)
	if save_err == OK:
		_checkpoint_dirty = false
		checkpoint_saved.emit(CURRENT_STATE_FILE_PATH)
	return save_err


func load_checkpoint() -> bool:
	if not has_checkpoint():
		checkpoint_loaded.emit(false)
		return false

	var state: Dictionary = _read_json_dict(CURRENT_STATE_FILE_PATH)
	if state.is_empty():
		checkpoint_loaded.emit(false)
		return false

	_is_restoring = true
	var ok: bool = _apply_run_state(state)
	_is_restoring = false
	checkpoint_loaded.emit(ok)
	return ok


func save_day_snapshot(day: int = -1) -> Error:
	var snapshot_day: int = day if day > 0 else _get_current_day()
	if snapshot_day <= 0:
		return ERR_INVALID_PARAMETER

	var state: Dictionary = _build_run_state()
	if state.is_empty():
		return ERR_INVALID_DATA

	state["snapshot_day"] = snapshot_day
	var file_path: String = DAYS_DIR_PATH + "day_%03d.json" % snapshot_day
	var save_err: Error = _write_json_dict(file_path, state)
	if save_err == OK:
		day_snapshot_saved.emit(snapshot_day, file_path)
	return save_err


func _ensure_run_directories() -> void:
	var directories: Array[String] = [
		RUN_ROOT_PATH,
		DAYS_DIR_PATH,
		PLAYER_PROJECT_DIR_PATH,
		GENERATED_DIR_PATH,
		BROWSER_DIR_PATH,
	]
	for dir_path in directories:
		if DirAccess.dir_exists_absolute(dir_path):
			continue
		var dir_err: Error = DirAccess.make_dir_recursive_absolute(dir_path)
		if dir_err != OK:
			push_warning("[CampaignRunManager] Failed to create directory: %s" % dir_path)


func _ensure_meta_file() -> void:
	if FileAccess.file_exists(META_FILE_PATH):
		return
	var meta: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"seed_version": _get_seed_version(),
		"created_at": Time.get_datetime_string_from_system(),
		"run_root_path": RUN_ROOT_PATH,
		"player_project_path": PLAYER_PROJECT_DIR_PATH,
	}
	var save_err: Error = _write_json_dict(META_FILE_PATH, meta)
	if save_err != OK:
		push_warning("[CampaignRunManager] Failed to write meta.json")


func _mount_runtime_player_project_if_needed() -> void:
	var storage: Node = _get_autoload("StorageManager")
	if storage == null or not storage.has_method("mount_runtime_project"):
		return
	if bool(storage.get("developer_mode")):
		return
	if storage.get("current_project") != null:
		return
	var mount_err: Error = storage.mount_runtime_project()
	if mount_err != OK:
		push_warning("[CampaignRunManager] Failed to mount runtime player project: %d" % mount_err)


func _connect_state_sources() -> void:
	var glm: Node = _get_autoload("GameLoopManager")
	if glm != null:
		_connect_signal(glm, "day_changed", Callable(self, "_on_day_changed"))
		_connect_signal(glm, "phase_changed", Callable(self, "_on_state_changed"))
		_connect_signal(glm, "game_over", Callable(self, "_on_game_over"))

	var gm: Node = _get_autoload("GameManager")
	if gm != null:
		_connect_signal(gm, "stats_changed", Callable(self, "_on_state_changed"))

	var story: Node = _get_autoload("StoryDirector")
	if story != null:
		_connect_signal(story, "step_completed", Callable(self, "_on_state_changed"))
		_connect_signal(story, "chapter_completed", Callable(self, "_on_state_changed"))
		_connect_signal(story, "story_variable_changed", Callable(self, "_on_state_changed"))

	var browser: Node = _get_autoload("BrowserManager")
	if browser != null:
		_connect_signal(browser, "browser_history_updated", Callable(self, "_on_state_changed"))
		_connect_signal(browser, "browser_state_changed", Callable(self, "_on_state_changed"))
		_connect_signal(browser, "search_completed", Callable(self, "_on_state_changed"))
		_connect_signal(browser, "search_failed", Callable(self, "_on_state_changed"))
		_connect_signal(browser, "page_generated", Callable(self, "_on_state_changed"))
		_connect_signal(browser, "page_failed", Callable(self, "_on_state_changed"))
		_connect_signal(browser, "browser_action_completed", Callable(self, "_on_state_changed"))
		_connect_signal(browser, "browser_action_failed", Callable(self, "_on_state_changed"))

	var shop: Node = _get_autoload("ShopManager")
	if shop != null:
		_connect_signal(shop, "shop_state_changed", Callable(self, "_on_state_changed"))
		_connect_signal(shop, "catalog_generation_failed", Callable(self, "_on_state_changed"))

	var chat: Node = _get_autoload("ChatManager")
	if chat != null:
		_connect_signal(chat, "chat_state_changed", Callable(self, "_on_state_changed"))
		_connect_signal(chat, "waiting_for_ai_changed", Callable(self, "_on_chat_waiting_changed"))

	var storage: Node = _get_autoload("StorageManager")
	if storage != null:
		_connect_signal(storage, "current_project_changed", Callable(self, "_on_state_changed"))

	_connect_activity_manager("DateManager")
	_connect_activity_manager("PartTimeJobManager")
	_connect_activity_manager("SbeamManager")
	_connect_activity_manager("HomeActivityManager")


func _attempt_startup_restore() -> void:
	_startup_restore_attempted = true
	if not _should_restore_on_startup():
		_startup_mode = "no_checkpoint"
		return
	_startup_restore_succeeded = load_checkpoint()
	if _startup_restore_succeeded:
		_startup_mode = "restored"
		print("[CampaignRunManager] Restored checkpoint from startup")
	else:
		_startup_mode = "restore_failed"


func _should_restore_on_startup() -> bool:
	if OS.has_feature("editor"):
		return false
	return has_checkpoint()


func _connect_signal(node: Node, signal_name: String, callable: Callable) -> void:
	if node == null or not node.has_signal(signal_name):
		return
	if node.is_connected(signal_name, callable):
		return
	node.connect(signal_name, callable)


func _connect_activity_manager(node_name: String) -> void:
	var node: Node = _get_autoload(node_name)
	if node == null:
		return
	_connect_signal(node, "session_completed", Callable(self, "_on_activity_session_completed"))
	_connect_signal(node, "session_failed", Callable(self, "_on_activity_session_failed"))


func _on_day_changed(new_day: int) -> void:
	if _is_restoring:
		return
	var save_err: Error = save_day_snapshot(new_day)
	if save_err != OK:
		push_warning("[CampaignRunManager] Failed to save day snapshot for day %d" % new_day)
	queue_checkpoint_save()


func _on_game_over() -> void:
	if _is_restoring:
		return
	save_day_snapshot(_get_current_day())
	queue_checkpoint_save()


func _on_state_changed(_arg1: Variant = null, _arg2: Variant = null, _arg3: Variant = null) -> void:
	queue_checkpoint_save()


func _on_chat_waiting_changed(is_waiting: bool) -> void:
	if is_waiting:
		return
	if _checkpoint_dirty:
		queue_checkpoint_save()


func _on_activity_session_completed(_session_id: String, _payload: Dictionary) -> void:
	if _checkpoint_dirty:
		queue_checkpoint_save()


func _on_activity_session_failed(_error_message: String) -> void:
	if _checkpoint_dirty:
		queue_checkpoint_save()


func _flush_checkpoint_save() -> void:
	if not _checkpoint_dirty:
		return
	if not _can_write_checkpoint():
		return
	var save_err: Error = save_checkpoint()
	if save_err != OK:
		push_warning("[CampaignRunManager] Failed to save checkpoint: %d" % save_err)


func _build_run_state() -> Dictionary:
	var game_loop_state: Dictionary = _collect_manager_state("GameLoopManager")
	var game_state: Dictionary = _collect_manager_state("GameManager")
	var story_state: Dictionary = _collect_manager_state("StoryDirector")
	var chat_state: Dictionary = _collect_manager_state("ChatManager")
	var browser_state: Dictionary = _collect_manager_state("BrowserManager")
	var shop_state: Dictionary = _collect_manager_state("ShopManager")
	var date_state: Dictionary = _collect_manager_state("DateManager")
	var part_time_state: Dictionary = _collect_manager_state("PartTimeJobManager")
	var sbeam_state: Dictionary = _collect_manager_state("SbeamManager")
	var home_activity_state: Dictionary = _collect_manager_state("HomeActivityManager")
	var player_project_path: String = PLAYER_PROJECT_DIR_PATH
	var storage: Node = _get_autoload("StorageManager")
	if storage != null:
		var runtime_project_path: String = str(storage.get("runtime_project_path")).strip_edges()
		if not runtime_project_path.is_empty():
			player_project_path = runtime_project_path

	if game_loop_state.is_empty() and game_state.is_empty() and story_state.is_empty() and chat_state.is_empty() and browser_state.is_empty() and shop_state.is_empty() and date_state.is_empty() and part_time_state.is_empty() and sbeam_state.is_empty() and home_activity_state.is_empty() and _generated_registry.is_empty():
		return {}

	return {
		"schema_version": SCHEMA_VERSION,
		"seed_version": _get_seed_version(),
		"saved_at": Time.get_datetime_string_from_system(),
		"current_day": _get_current_day(),
		"time_phase": int(game_loop_state.get("time_phase", 0)),
		"player_project_path": player_project_path,
		"browser_history_path": get_browser_history_path(),
		"game_stats": game_state.duplicate(true),
		"game_loop_state": game_loop_state,
		"game_state": game_state,
		"story_state": story_state,
		"chat_state": chat_state,
		"browser_state": browser_state,
		"shop_state": shop_state,
		"date_state": date_state,
		"part_time_state": part_time_state,
		"sbeam_state": sbeam_state,
		"home_activity_state": home_activity_state,
		"generated_registry": _generated_registry.duplicate(true),
	}


func _apply_run_state(state: Dictionary) -> bool:
	var ok: bool = true
	ok = _apply_manager_state("GameLoopManager", state.get("game_loop_state", {})) and ok
	ok = _apply_manager_state("GameManager", state.get("game_state", state.get("game_stats", {}))) and ok
	ok = _apply_manager_state("StoryDirector", state.get("story_state", {})) and ok
	ok = _apply_manager_state("ChatManager", state.get("chat_state", {})) and ok
	ok = _apply_manager_state("BrowserManager", state.get("browser_state", {})) and ok
	ok = _apply_manager_state("ShopManager", state.get("shop_state", {})) and ok
	ok = _apply_manager_state("DateManager", state.get("date_state", {})) and ok
	ok = _apply_manager_state("PartTimeJobManager", state.get("part_time_state", {})) and ok
	ok = _apply_manager_state("SbeamManager", state.get("sbeam_state", {})) and ok
	ok = _apply_manager_state("HomeActivityManager", state.get("home_activity_state", {})) and ok
	var registry_state: Variant = state.get("generated_registry", {})
	if registry_state is Dictionary:
		_generated_registry = (registry_state as Dictionary).duplicate(true)
	else:
		_generated_registry = {"artifacts": []}
	return ok


func _collect_manager_state(node_name: String) -> Dictionary:
	var node: Node = _get_autoload(node_name)
	if node == null:
		return {}
	if node.has_method("get_run_state"):
		var result: Variant = node.call("get_run_state")
		if result is Dictionary:
			return (result as Dictionary).duplicate(true)
	if node_name == "GameManager" and node.has_method("to_dict"):
		var fallback: Variant = node.call("to_dict")
		if fallback is Dictionary:
			return (fallback as Dictionary).duplicate(true)
	if node_name == "StoryDirector" and node.has_method("get_save_data"):
		var legacy: Variant = node.call("get_save_data")
		if legacy is Dictionary:
			return (legacy as Dictionary).duplicate(true)
	return {}


func _apply_manager_state(node_name: String, state: Variant) -> bool:
	if not state is Dictionary:
		return true
	var state_dict: Dictionary = state
	if state_dict.is_empty():
		return true
	var node: Node = _get_autoload(node_name)
	if node == null:
		return false
	if node.has_method("load_run_state"):
		return bool(node.call("load_run_state", state_dict))
	if node_name == "GameManager" and node.has_method("from_dict"):
		node.call("from_dict", state_dict)
		return true
	if node_name == "StoryDirector" and node.has_method("load_save_data"):
		return bool(node.call("load_save_data", state_dict))
	return true


func _get_current_day() -> int:
	var glm: Node = _get_autoload("GameLoopManager")
	if glm == null:
		return 0
	return int(glm.get("current_day"))


func _can_write_checkpoint() -> bool:
	return not _has_pending_activity_sessions() and not _is_chat_waiting_for_ai() and not _has_pending_browser_requests() and not _has_pending_shop_requests()


func _can_reset_run() -> bool:
	return _can_write_checkpoint()


func _has_pending_activity_sessions() -> bool:
	var activity_managers: Array[String] = ["DateManager", "PartTimeJobManager", "SbeamManager", "HomeActivityManager"]
	for node_name in activity_managers:
		var node: Node = _get_autoload(node_name)
		if node == null or not node.has_method("has_any_pending_sessions"):
			continue
		if bool(node.call("has_any_pending_sessions")):
			return true
	return false


func _is_chat_waiting_for_ai() -> bool:
	var chat: Node = _get_autoload("ChatManager")
	if chat == null or not chat.has_method("is_waiting_for_ai"):
		return false
	return bool(chat.call("is_waiting_for_ai"))


func _has_pending_browser_requests() -> bool:
	var browser: Node = _get_autoload("BrowserManager")
	if browser == null or not browser.has_method("has_pending_requests"):
		return false
	return bool(browser.call("has_pending_requests"))


func _has_pending_shop_requests() -> bool:
	var shop: Node = _get_autoload("ShopManager")
	if shop == null or not shop.has_method("has_pending_requests"):
		return false
	return bool(shop.call("has_pending_requests"))


func _get_seed_version() -> String:
	var version: String = str(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	return version if not version.is_empty() else "dev"


func _sanitize_path_segment(value: String) -> String:
	var sanitized: String = value.strip_edges()
	if sanitized.is_empty():
		return ""
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", " "]:
		sanitized = sanitized.replace(ch, "_")
	while sanitized.begins_with("_"):
		sanitized = sanitized.substr(1)
	while sanitized.ends_with("_"):
		sanitized = sanitized.substr(0, sanitized.length() - 1)
	return sanitized


func _write_json_dict(file_path: String, data: Dictionary) -> Error:
	var dir_path: String = file_path.get_base_dir() + "/"
	if not DirAccess.dir_exists_absolute(dir_path):
		var dir_err: Error = DirAccess.make_dir_recursive_absolute(dir_path)
		if dir_err != OK:
			return dir_err

	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return OK


func _read_json_dict(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {}
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_warning("[CampaignRunManager] Failed to open json file: %s" % file_path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_warning("[CampaignRunManager] Invalid json data: %s" % file_path)
		return {}
	return (parsed as Dictionary).duplicate(true)


func _get_autoload(node_name: String) -> Node:
	return get_node_or_null("/root/%s" % node_name)


func _mount_runtime_player_project_force() -> void:
	var storage: Node = _get_autoload("StorageManager")
	if storage == null or not storage.has_method("mount_runtime_project"):
		return
	var mount_err: Error = storage.mount_runtime_project()
	if mount_err != OK:
		push_warning("[CampaignRunManager] Failed to mount runtime player project: %d" % mount_err)


func _reset_all_runtime_state() -> void:
	_reset_manager_state("StorageManager", [true])
	_reset_manager_state("GameLoopManager")
	_reset_manager_state("GameManager")
	_reset_manager_state("StoryDirector")
	_reset_manager_state("ChatManager", [true])
	_reset_manager_state("BrowserManager", [true])
	_reset_manager_state("ShopManager")
	_reset_manager_state("DateManager")
	_reset_manager_state("PartTimeJobManager")
	_reset_manager_state("SbeamManager")
	_reset_manager_state("HomeActivityManager")


func _reset_manager_state(node_name: String, args: Array = []) -> void:
	var node: Node = _get_autoload(node_name)
	if node == null or not node.has_method("reset_runtime_state"):
		return
	node.callv("reset_runtime_state", args)


func _clear_run_storage() -> void:
	if not DirAccess.dir_exists_absolute(RUN_ROOT_PATH):
		return
	_remove_directory_recursive(RUN_ROOT_PATH)


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
