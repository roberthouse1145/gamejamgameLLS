extends Node
## KnowledgeBaseManager Autoload
## Handles saving and loading the knowledge base JSON file in the current project directory.

# Signals
signal data_loaded(data: Resource)
signal data_saved(data: Resource)

# State
var current_data: KnowledgeBaseData = null
var _storage_manager: Node = null

const KB_FILE_NAME = "knowledge_base.json"
# Removed redundant KnowledgeBaseData constant preload

func _ready() -> void:
	# Wait one frame for StorageManager to map appropriately if autoloads are scrambling
	call_deferred("_init_manager")

func _init_manager() -> void:
	_storage_manager = get_node_or_null("/root/StorageManager")
	if _storage_manager:
		_storage_manager.current_project_changed.connect(_on_project_changed)
		
		# If a project is already open, load the data now
		if _storage_manager.current_project_path != "":
			load_data()

func _on_project_changed(_project: Resource) -> void:
	load_data()

## Load the knowledge base from the current project directory
func load_data() -> void:
	if _storage_manager == null or _storage_manager.current_project_path.is_empty():
		return
	
	var dir_path: String = _storage_manager.current_project_path.path_join("knowledge_base")
	var file_path: String = dir_path.path_join(KB_FILE_NAME)
	
	current_data = KnowledgeBaseData.new()
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file:
		var json_str = file.get_as_text()
		var json = JSON.new()
		if json.parse(json_str) == OK and typeof(json.data) == TYPE_DICTIONARY:
			current_data.from_dict(json.data)
		else:
			push_warning("[KnowledgeBaseManager] Failed to parse JSON: %s" % file_path)
	else:
		# If file doesn't exist, we just keep the new empty initialized data
		print("[KnowledgeBaseManager] No knowledge base found at %s. Created empty one." % file_path)
		
	# Synchronize game title if project has one
	if _storage_manager.current_project != null and current_data.game_title == "Untitled Project":
		if "project_name" in _storage_manager.current_project:
			current_data.game_title = _storage_manager.current_project.project_name
			
	data_loaded.emit(current_data)

## Save the knowledge base to the current project directory
func save_data() -> void:
	if current_data == null or _storage_manager == null or _storage_manager.current_project_path.is_empty():
		return
		
	var dir_path: String = _storage_manager.current_project_path.path_join("knowledge_base")
	var file_path: String = dir_path.path_join(KB_FILE_NAME)
	
	# Ensure directory exists
	if not DirAccess.dir_exists_absolute(dir_path):
		var err = DirAccess.make_dir_recursive_absolute(dir_path)
		if err != OK:
			push_error("[KnowledgeBaseManager] Failed to create directory: %s" % dir_path)
			return

	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		var dict = current_data.to_dict()
		var json_str = JSON.stringify(dict, "\t")
		file.store_string(json_str)
		data_saved.emit(current_data)
		print("[KnowledgeBaseManager] Saved knowledge base to %s" % file_path)
	else:
		push_error("[KnowledgeBaseManager] Failed to open file for writing: %s" % file_path)
