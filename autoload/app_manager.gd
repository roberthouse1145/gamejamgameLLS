extends Node
## AppManager Autoload
## 管理APP的注册、启动、生命周期
## Manages app registration, launching, and lifecycle

# Preload classes (avoid cross-file type issues)
const AppDefinitionClass = preload("res://scripts/pseudo_os/app_definition.gd")
const WindowConstraintsClass = preload("res://scripts/pseudo_os/window_constraints.gd")

# Signals
## Emitted when an app is launched
## @param app_id: The ID of the launched app
## @param window: The window Control containing the app (PseudoWindow)
signal app_launched(app_id: String, window: Control)

## Emitted when an app is closed
## @param app_id: The ID of the closed app
signal app_closed(app_id: String)
signal app_registered(app_id: String, app_definition: Resource)
signal app_unregistered(app_id: String)
signal app_desktop_visibility_changed(app_id: String, desired_visible: bool)

# App registry: app_id -> AppDefinition
var app_registry: Dictionary = {}

# Running apps: app_id -> PseudoWindow (Control)
var running_apps: Dictionary = {}
var _desktop_visibility_overrides: Dictionary = {}

# Reference to WindowManager (set by Desktop)
var window_manager: Node = null

# Story-driven access control
## "none" = 无限制, "whitelist" = 仅允许列表中的, "blacklist" = 禁止列表中的
var _access_mode: String = "none"
var _access_list: Array[String] = []

signal app_access_changed(mode: String, apps: Array[String])


func _ready() -> void:
	_register_all_apps()


## Register all app definitions on startup
func _register_all_apps() -> void:
	# App definition resource paths
	var app_paths: Array[String] = [
		"res://resources/apps/scene_editor_app.tres",
		"res://resources/apps/project_manager_app.tres",
		"res://resources/apps/story_project_manager_app.tres",
		"res://resources/apps/game_previewer_app.tres",
		"res://resources/apps/file_manager_app.tres",
		"res://resources/apps/linkchat_app.tres",
		"res://resources/apps/bithub_app.tres",
		"res://resources/apps/browser_app.tres",
		"res://resources/apps/community_app.tres",
		"res://resources/apps/home_app.tres",
		"res://resources/apps/map_app.tres",
		"res://resources/apps/avg_player_app.tres",
		"res://resources/apps/part_time_app.tres",
		"res://resources/apps/sbeam_app.tres",
		"res://resources/apps/work_order_app.tres",
		"res://resources/apps/knowledge_base_app.tres",
		"res://resources/apps/dev_work_app.tres",
		"res://resources/apps/shop_app.tres",
		"res://resources/apps/desktop_pet_app.tres",
		"res://resources/apps/music_player_app.tres",
	]
	
	for path in app_paths:
		if ResourceLoader.exists(path):
			var app_def: Resource = ResourceLoader.load(path)
			if app_def:
				register_app(app_def)
				print("AppManager: Registered app '%s'" % app_def.app_id)
			else:
				push_warning("AppManager: Failed to load app definition: %s" % path)
		else:
			push_warning("AppManager: App definition not found: %s" % path)


## Register an app definition
## @param definition: The AppDefinition resource to register
func register_app(definition: Resource) -> void:
	# Validate that definition is not null
	if definition == null:
		push_warning("AppManager: Cannot register null app definition")
		return
	
	# Validate required fields exist and are accessible
	if not definition is AppDefinition:
		push_warning("AppManager: App definition missing 'app_id' field")
		return
	
	# Validate app_id is not empty
	var app_id: String = definition.app_id
	if app_id.is_empty():
		push_warning("AppManager: Cannot register app with empty app_id")
		return
	
	# Validate entry_scene is not null
	if definition.entry_scene == null:
		push_warning("AppManager: Cannot register app '%s' with null entry_scene" % app_id)
		return
	
	# Check if app_id already exists
	if app_registry.has(app_id):
		push_warning("AppManager: App '%s' already registered, overwriting" % app_id)
	
	# Add to app_registry with app_id as key
	app_registry[app_id] = definition
	app_registered.emit(app_id, definition)


## Launch an app by its ID
## @param app_id: The ID of the app to launch
## @return: The created window Control (PseudoWindow), or null if failed
func launch_app(app_id: String, force_launch: bool = false) -> Control:
	# Check if app is registered
	if not app_registry.has(app_id):
		push_warning("AppManager: App '%s' is not registered" % app_id)
		return null

	# Story-driven access control
	if not force_launch and not is_app_accessible(app_id):
		push_warning("AppManager: App '%s' is currently restricted by story" % app_id)
		return null

	# Check if app is already running - focus existing window
	if is_app_running(app_id):
		var existing_window: Control = running_apps[app_id]
		if window_manager:
			window_manager.focus_window(existing_window)
		return existing_window
	
	# Get the app definition
	var definition: Resource = app_registry[app_id]
	
	# Instantiate entry_scene
	var content: Control = definition.entry_scene.instantiate() as Control
	if content == null:
		push_error("AppManager: Failed to instantiate entry_scene for app '%s'" % app_id)
		return null
	
	# Create window via WindowManager
	if window_manager == null:
		push_error("AppManager: WindowManager not set, cannot create window")
		content.queue_free()
		return null
	
	var window: Control = window_manager.create_window(
		definition.app_name,
		content,
		definition.window_constraints
	)
	
	if window == null:
		push_error("AppManager: Failed to create window for app '%s'" % app_id)
		content.queue_free()
		return null
	
	# Track in running_apps
	running_apps[app_id] = window
	
	# Connect window close signal to handle app closure
	window.close_requested.connect(_on_app_window_closed.bind(app_id))
	
	# Emit app_launched signal
	app_launched.emit(app_id, window)
	
	return window


## Handle window close for an app
func _on_app_window_closed(app_id: String) -> void:
	# Remove from running_apps
	if running_apps.has(app_id):
		running_apps.erase(app_id)
	# Emit app_closed signal
	app_closed.emit(app_id)


## Close a running app by its ID
## @param app_id: The ID of the app to close
func close_app(app_id: String, force_close: bool = false) -> bool:
	# Check if app is running
	if not is_app_running(app_id):
		if not force_close:
			push_warning("AppManager: App '%s' is not running" % app_id)
		return false
	
	# Get the window
	var window: Control = running_apps[app_id]
	if not force_close and "close_locked" in window and bool(window.close_locked):
		push_warning("AppManager: App '%s' window is locked" % app_id)
		return false

	if force_close:
		if window.has_method("set_close_locked"):
			window.set_close_locked(false)
		if window.has_method("set_minimize_locked"):
			window.set_minimize_locked(false)
	
	# Close window via WindowManager
	if window_manager:
		window_manager.close_window(window)
	else:
		# Fallback: directly free the window
		window.queue_free()
	
	# Remove from running_apps
	running_apps.erase(app_id)
	
	# Emit app_closed signal
	app_closed.emit(app_id)
	return true


## Check if an app is currently running
## @param app_id: The ID of the app to check
## @return: True if the app is running
func is_app_running(app_id: String) -> bool:
	return running_apps.has(app_id) and is_instance_valid(running_apps[app_id])


## Get the window of a running app
## @param app_id: The ID of the app
## @return: The window Control (PseudoWindow), or null if not running
func get_app_window(app_id: String) -> Control:
	if is_app_running(app_id):
		return running_apps[app_id]
	return null


func focus_app(app_id: String, force_launch: bool = false) -> Control:
	if is_app_running(app_id):
		var window: Control = running_apps[app_id]
		if window_manager != null and window_manager.has_method("focus_window"):
			window_manager.focus_window(window)
		return window
	if force_launch:
		return launch_app(app_id, true)
	return null


func lock_app_window(app_id: String) -> bool:
	var window := get_app_window(app_id)
	if window == null:
		return false
	if window.has_method("set_close_locked"):
		window.set_close_locked(true)
	if window.has_method("set_minimize_locked"):
		window.set_minimize_locked(true)
	return true


func unlock_app_window(app_id: String) -> bool:
	var window := get_app_window(app_id)
	if window == null:
		return false
	if window.has_method("set_close_locked"):
		window.set_close_locked(false)
	if window.has_method("set_minimize_locked"):
		window.set_minimize_locked(false)
	return true


## Get all registered app definitions
## @return: Array of AppDefinition resources
func get_registered_apps() -> Array:
	return app_registry.values()


func is_app_registered(app_id: String) -> bool:
	return app_registry.has(app_id)


func get_app_definition(app_id: String) -> Resource:
	return app_registry.get(app_id, null)


func install_app_from_path(resource_path: String) -> bool:
	var normalized_path := resource_path.strip_edges()
	if normalized_path.is_empty():
		return false
	if not ResourceLoader.exists(normalized_path):
		push_warning("AppManager: App definition not found: %s" % normalized_path)
		return false
	var app_def: Resource = ResourceLoader.load(normalized_path)
	if app_def == null:
		push_warning("AppManager: Failed to load app definition: %s" % normalized_path)
		return false
	register_app(app_def)
	return true


func unregister_app(app_id: String, close_running: bool = true) -> bool:
	var normalized_app_id := app_id.strip_edges()
	if normalized_app_id.is_empty() or not app_registry.has(normalized_app_id):
		return false
	if close_running and is_app_running(normalized_app_id):
		close_app(normalized_app_id, true)
	app_registry.erase(normalized_app_id)
	_desktop_visibility_overrides.erase(normalized_app_id)
	app_unregistered.emit(normalized_app_id)
	return true


func set_app_desktop_visible(app_id: String, desired_visible: bool) -> bool:
	var normalized_app_id := app_id.strip_edges()
	if normalized_app_id.is_empty() or not app_registry.has(normalized_app_id):
		return false
	_desktop_visibility_overrides[normalized_app_id] = desired_visible
	app_desktop_visibility_changed.emit(normalized_app_id, desired_visible)
	return true


func clear_app_desktop_visibility_override(app_id: String) -> void:
	var normalized_app_id := app_id.strip_edges()
	if normalized_app_id.is_empty() or not _desktop_visibility_overrides.has(normalized_app_id):
		return
	_desktop_visibility_overrides.erase(normalized_app_id)
	app_desktop_visibility_changed.emit(normalized_app_id, is_app_desktop_visible(normalized_app_id))


func is_app_desktop_visible(app_id: String) -> bool:
	if _desktop_visibility_overrides.has(app_id):
		return bool(_desktop_visibility_overrides[app_id])
	var app_def: Resource = app_registry.get(app_id, null)
	if app_def != null and "show_on_desktop" in app_def:
		return bool(app_def.show_on_desktop)
	return app_def != null


## Get all registered app IDs
## @return: Array of app ID strings
func get_registered_app_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in app_registry.keys():
		ids.append(key)
	return ids


## Set the WindowManager reference
## @param manager: The WindowManager node
func set_window_manager(manager: Node) -> void:
	window_manager = manager


# =============================================================================
# Story-driven Access Control
# =============================================================================

## 检查 APP 是否可访问（受 StoryDirector 控制）
func is_app_accessible(app_id: String) -> bool:
	match _access_mode:
		"whitelist":
			return app_id in _access_list
		"blacklist":
			return app_id not in _access_list
	return true


## 设置白名单模式：仅允许列表中的 APP
func set_app_whitelist(app_ids: Array[String]) -> void:
	_access_mode = "whitelist"
	_access_list = app_ids.duplicate()
	app_access_changed.emit(_access_mode, _access_list)
	print("[AppManager] Whitelist set: %s" % str(app_ids))


## 设置黑名单模式：禁止列表中的 APP
func set_app_blacklist(app_ids: Array[String]) -> void:
	_access_mode = "blacklist"
	_access_list = app_ids.duplicate()
	app_access_changed.emit(_access_mode, _access_list)
	print("[AppManager] Blacklist set: %s" % str(app_ids))


## 清除访问限制
func clear_app_access_restriction() -> void:
	_access_mode = "none"
	_access_list.clear()
	app_access_changed.emit(_access_mode, _access_list)
	print("[AppManager] Access restriction cleared")


## 获取当前可访问的 APP 列表（供 UI 使用）
func get_accessible_app_ids() -> Array[String]:
	var all_ids: Array[String] = get_registered_app_ids()
	if _access_mode == "none":
		return all_ids
	var result: Array[String] = []
	for app_id in all_ids:
		if is_app_accessible(app_id):
			result.append(app_id)
	return result
