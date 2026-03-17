class_name AVGDevKBTools extends RefCounted

const KBDataResource = preload("res://scripts/apps/knowledge_base/knowledge_base_data.gd")

static func register_all(ai_service: Node) -> void:
	ai_service.register_tool("kb_read", "Read information from the Game Design Knowledge Base. By default reads the finalized LLM KB (confirmed snapshots). Use source=player to read the player's draft notebook instead.", {
		"type": "object",
		"properties": {
			"category": {"type": "string", "enum": ["world", "characters", "beats", "assets"], "description": "The category of knowledge to read"},
			"id": {"type": "string", "description": "Optional ID to fetch a specific character or beat. If empty, lists all items in category."},
			"tags": {"type": "array", "items": {"type": "string"}, "description": "Optional list of tags. Returns only items (characters/beats) containing at least one of these tags in their text."},
			"source": {"type": "string", "enum": ["llm", "player"], "description": "Which KB to read from. 'llm' (default) = finalized snapshots that Worker agents use as ground truth. 'player' = the raw draft notebook."}
		},
		"required": ["category"]
	}, func(args: Dictionary) -> Variant: return _kb_read(args))

	ai_service.register_tool("kb_write", "Write or update information in the generic Game Design Knowledge Base", {
		"type": "object",
		"properties": {
			"category": {"type": "string", "enum": ["world", "characters", "beats", "assets"], "description": "The category to write to"},
			"id": {"type": "string", "description": "ID of character/beat to update. If empty for characters/beats, creates new. Ignored for world."},
			"fields": {"type": "object", "description": "Dictionary of fields to update, for beats use 'content' for the combined script with inline tags."}
		},
		"required": ["category", "fields"]
	}, func(args: Dictionary) -> Variant: return _kb_write(args))

	ai_service.register_tool("kb_add_note", "Act as Lin Xia to drop a sticky note onto the player's canvas", {
		"type": "object",
		"properties": {
			"category": {"type": "string", "enum": ["characters", "beats"], "description": "Which canvas to drop the note on"},
			"content": {"type": "string", "description": "The text content of the note. Feel free to use a cute or encouraging tone."},
			"title": {"type": "string", "description": "The title or name for the note (e.g. '关于男主的一个想法')"}
		},
		"required": ["category", "content", "title"]
	}, func(args: Dictionary) -> Variant: return _kb_add_note(args))

	ai_service.register_tool("kb_confirm", "Confirm (snapshot) a Player KB entry into the LLM KB, marking it as the authoritative version for Worker agents. Call this after aligning with the player.", {
		"type": "object",
		"properties": {
			"category": {"type": "string", "enum": ["world", "characters", "beats"], "description": "Category of entry to confirm"},
			"id": {"type": "string", "description": "ID of the character or beat to confirm. For 'world', leave empty."}
		},
		"required": ["category"]
	}, func(args: Dictionary) -> Variant: return _kb_confirm(args))

static func _get_data() -> KnowledgeBaseData:
	var kbm = Engine.get_main_loop().root.get_node_or_null("/root/KnowledgeBaseManager")
	if kbm:
		return kbm.get("current_data") as KnowledgeBaseData
	return null

static func _save_data() -> void:
	var kbm = Engine.get_main_loop().root.get_node_or_null("/root/KnowledgeBaseManager")
	if kbm and kbm.has_method("save_data"):
		kbm.call("save_data")

static func _get_llm_kb() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("/root/LLMKnowledgeBaseManager")

static func _kb_read(args: Dictionary) -> Dictionary:
	var category = args.get("category", "")
	var id = args.get("id", "")
	var source = args.get("source", "llm") # Default: read finalized LLM KB

	# --- Route to LLM KB (default for Worker agents) ---
	if source == "llm" and category != "assets":
		var llm_kb = _get_llm_kb()
		if not llm_kb:
			return {"success": false, "error": "LLMKnowledgeBaseManager not found. Is it registered as Autoload?"}
		if category == "world":
			return {"success": true, "data": llm_kb.get_all("world"), "source": "llm"}
		if not id.is_empty():
			var entry = llm_kb.get_entry(category, id)
			if entry == null:
				return {"success": false, "error": "Entry '%s' not found in LLM KB '%s'. Has it been confirmed yet?" % [id, category]}
			return {"success": true, "data": entry, "source": "llm"}
		else:
			var all_entries = llm_kb.get_all(category)
			var search_tags: Array = args.get("tags", [])
			if search_tags.size() > 0:
				all_entries = all_entries.filter(func(e):
					var text = str(e.values())
					for t in search_tags:
						if t in text: return true
					return false
				)
			return {"success": true, "data": all_entries, "source": "llm"}

	# --- Route to Player KB (draft notebook) ---
	var data = _get_data()
	if not data:
		return {"success": false, "error": "Player Knowledge Base is not currently initialized."}
	
	match category:
		"world":
			return {
				"success": true,
				"data": {
					"game_title": data.game_title,
					"synopsis": data.synopsis
				}
			}
		"characters":
			if id.is_empty():
				var list = []
				var search_tags: Array = args.get("tags", [])
				for c in data.characters:
					if search_tags.size() > 0:
						var found = false
						var text = str(c.values())
						for t in search_tags:
							if t in text:
								found = true
								break
						if not found: continue
						
					var safe_c = c.duplicate()
					safe_c.erase("position_x")
					safe_c.erase("position_y")
					safe_c.erase("author")
					list.append(safe_c)
				return {"success": true, "data": list}
			else:
				for c in data.characters:
					if c.get("character_id") == id:
						var safe_c = c.duplicate()
						safe_c.erase("position_x")
						safe_c.erase("position_y")
						safe_c.erase("author")
						return {"success": true, "data": safe_c}
				return {"success": false, "error": "Character ID not found."}
		"beats":
			if id.is_empty():
				var list = []
				var search_tags: Array = args.get("tags", [])
				for b in data.beats:
					if search_tags.size() > 0:
						var found = false
						var text = str(b.values())
						for t in search_tags:
							if t in text:
								found = true
								break
						if not found: continue
						
					var safe_b = b.duplicate()
					safe_b.erase("position_x")
					safe_b.erase("position_y")
					safe_b.erase("author")
					list.append(safe_b)
				return {"success": true, "data": list}
			else:
				for b in data.beats:
					if b.get("beat_id") == id:
						var safe_b = b.duplicate()
						safe_b.erase("position_x")
						safe_b.erase("position_y")
						safe_b.erase("author")
						return {"success": true, "data": safe_b}
				return {"success": false, "error": "Beat ID not found."}
		"assets":
			return {"success": true, "data": data.asset_tags}
		_:
			return {"success": false, "error": "Unknown category."}

static func _kb_write(args: Dictionary) -> Dictionary:
	var data = _get_data()
	if not data:
		return {"success": false, "error": "Knowledge Base is not currently initialized."}
		
	var category = args.get("category", "")
	var id = args.get("id", "")
	var fields = args.get("fields", {})
	
	match category:
		"world":
			for k in fields.keys():
				if k in ["game_title", "synopsis"]:
					data.set(k, fields[k])
			_save_data()
			return {"success": true}
		"characters":
			if id.is_empty():
				# Create
				fields["character_id"] = "char_" + str(Time.get_ticks_msec()).substr(3, 10)
				fields["author"] = "lin_xia" # Default author from AI tool
				fields["position_x"] = randi_range(50, 800) # Random place so the player sees it
				fields["position_y"] = randi_range(50, 600)
				data.characters.append(fields)
				_save_data()
				return {"success": true, "id": fields["character_id"]}
			else:
				for i in range(data.characters.size()):
					if data.characters[i].get("character_id") == id:
						for k in fields.keys():
							if k != "character_id":
								data.characters[i][k] = fields[k]
						_save_data()
						return {"success": true, "id": id}
				return {"success": false, "error": "Character ID not found."}
		"beats":
			if id.is_empty():
				# Create
				fields["beat_id"] = "beat_" + str(Time.get_ticks_msec()).substr(3, 10)
				fields["author"] = "lin_xia" # Default author from AI tool
				fields["position_x"] = randi_range(50, 800) # Random place so the player sees it
				fields["position_y"] = randi_range(50, 600)
				data.beats.append(fields)
				_save_data()
				return {"success": true, "id": fields["beat_id"]}
			else:
				for i in range(data.beats.size()):
					if data.beats[i].get("beat_id") == id:
						for k in fields.keys():
							if k != "beat_id":
								data.beats[i][k] = fields[k]
						_save_data()
						return {"success": true, "id": id}
				return {"success": false, "error": "Beat ID not found."}
		"assets":
			# fields format: {"asset_name": ["tag1", "tag2"]}
			for k in fields.keys():
				data.asset_tags[k] = fields[k]
			_save_data()
			return {"success": true}
		_:
			return {"success": false, "error": "Unknown category."}

static func _kb_add_note(args: Dictionary) -> Dictionary:
	var data = _get_data()
	if not data:
		return {"success": false, "error": "Knowledge Base is not currently initialized."}
		
	var category = args.get("category", "")
	var content = args.get("content", "")
	var title = args.get("title", "Lin Xia's Note")
	
	if category == "characters":
		var new_id = "char_" + str(Time.get_ticks_msec()).substr(3, 10)
		data.characters.append({
			"character_id": new_id,
			"full_name": title,
			"personality": content,
			"author": "lin_xia",
			"position_x": randi_range(200, 600) + randf_range(-50, 50),
			"position_y": randi_range(200, 400) + randf_range(-50, 50)
		})
		_save_data()
		return {"success": true, "id": new_id, "message": "Note added to Characters canvas!"}
	elif category == "beats":
		var new_id = "beat_" + str(Time.get_ticks_msec()).substr(3, 10)
		data.beats.append({
			"beat_id": new_id,
			"title": title,
			"content": content,
			"author": "lin_xia",
			"position_x": randi_range(200, 600) + randf_range(-50, 50),
			"position_y": randi_range(200, 400) + randf_range(-50, 50)
		})
		_save_data()
		return {"success": true, "id": new_id, "message": "Note added to Beats canvas!"}
	else:
		return {"success": false, "error": "Invalid category for notes. Use 'characters' or 'beats'."}

static func _kb_confirm(args: Dictionary) -> Dictionary:
	var category = args.get("category", "")
	var id = args.get("id", "")

	var player_data = _get_data()
	if not player_data:
		return {"success": false, "error": "Player Knowledge Base is not initialized."}

	var llm_kb = _get_llm_kb()
	if not llm_kb:
		return {"success": false, "error": "LLMKnowledgeBaseManager not found. Is it registered as Autoload?"}

	match category:
		"world":
			# Snapshot world info
			var world_snapshot = {
				"game_title": player_data.game_title,
				"synopsis": player_data.synopsis
			}
			llm_kb.snapshot_entry("world", "", world_snapshot)
			return {"success": true, "message": "World info confirmed to LLM KB."}
		"characters":
			if id.is_empty():
				return {"success": false, "error": "id required to confirm a character."}
			for c in player_data.characters:
				if c.get("character_id") == id:
					# Strip UI-only fields for the LLM snapshot
					var snapshot = c.duplicate(true)
					snapshot.erase("position_x")
					snapshot.erase("position_y")
					snapshot.erase("author")
					llm_kb.snapshot_entry("characters", id, snapshot)
					return {"success": true, "message": "Character '%s' confirmed to LLM KB." % id}
			return {"success": false, "error": "Character ID '%s' not found in Player KB." % id}
		"beats":
			if id.is_empty():
				return {"success": false, "error": "id required to confirm a beat."}
			for b in player_data.beats:
				if b.get("beat_id") == id:
					var snapshot = b.duplicate(true)
					snapshot.erase("position_x")
					snapshot.erase("position_y")
					snapshot.erase("author")
					llm_kb.snapshot_entry("beats", id, snapshot)
					return {"success": true, "message": "Beat '%s' confirmed to LLM KB." % id}
			return {"success": false, "error": "Beat ID '%s' not found in Player KB." % id}
		_:
			return {"success": false, "error": "Unknown category for kb_confirm."}
