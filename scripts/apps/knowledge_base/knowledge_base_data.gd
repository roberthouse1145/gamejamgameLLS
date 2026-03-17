class_name KnowledgeBaseData extends Resource
## Knowledge Base Data Resource
## Stores the global game design document fields for the AI context.

# --- World & General (Tab 1) ---
@export var game_title: String = "Untitled Project"
@export var synopsis: String = "" # This now acts as the single core concept notes field

# --- Characters (Tab 2) ---
# Array of Dictionaries:
# { "character_id": str, "full_name": str, "notes": str }
@export var characters: Array = []

# --- Story Beats (Tab 3) ---
# Array of Dictionaries:
# { "beat_id": "beat_01", "title": "开场", "scene_id": "scene_01", "status": "draft", "content": "..." }
@export var beats: Array = []

# --- Asset Tags (Tab 4) ---
# Dictionary: asset_name -> Array[String] (tags)
@export var asset_tags: Dictionary = {}

func to_dict() -> Dictionary:
	return {
		"game_title": game_title,
		"synopsis": synopsis,
		"characters": characters,
		"beats": beats,
		"asset_tags": asset_tags
	}

func from_dict(d: Dictionary) -> void:
	game_title = d.get("game_title", "Untitled Project")
	synopsis = d.get("synopsis", "")
	characters = d.get("characters", [])
	beats = d.get("beats", [])
	asset_tags = d.get("asset_tags", {})
