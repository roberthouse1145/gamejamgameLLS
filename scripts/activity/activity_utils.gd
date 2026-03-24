class_name ActivityUtils
extends RefCounted


static func get_chat_manager() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("/root/ChatManager")


static func get_current_day() -> int:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return 1
	var glm: Node = tree.root.get_node_or_null("/root/GameLoopManager")
	if glm != null and "current_day" in glm:
		return maxi(int(glm.current_day), 1)
	return 1


static func get_phase_name() -> String:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return "UNKNOWN"
	var glm: Node = tree.root.get_node_or_null("/root/GameLoopManager")
	if glm != null and glm.has_method("get_phase_name"):
		return str(glm.get_phase_name(glm.get("time_phase"))).strip_edges()
	return "UNKNOWN"


static func is_test_scene() -> bool:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return false
	return str(tree.current_scene.scene_file_path) == "res://test.tscn"


static func pick_random_event_seed(data: Dictionary) -> String:
	var seeds: Array = data.get("event_seeds", [])
	if seeds.is_empty():
		return ""
	return str(seeds[randi() % seeds.size()]).strip_edges()


static func extract_topic_summary(result: Dictionary) -> String:
	var summary := str(result.get("summary", "")).replace("[TOPIC_COMPLETE]", "").strip_edges()
	if not summary.is_empty():
		return summary
	var messages: Variant = result.get("messages", [])
	if messages is Array and not messages.is_empty():
		var last_msg: Variant = messages[-1]
		if last_msg is Dictionary:
			return str(last_msg.get("content", "")).replace("[TOPIC_COMPLETE]", "").strip_edges()
		return str(last_msg).replace("[TOPIC_COMPLETE]", "").strip_edges()
	return ""


static func extract_ai_text(response: Dictionary) -> String:
	if response.has("choices") and response.choices is Array and response.choices.size() > 0:
		var message_data: Dictionary = response.choices[0].get("message", {})
		var raw_content: Variant = message_data.get("content", "")
		return str(raw_content)
	return ""


static func sanitize_generated_text(text: String) -> String:
	var cleaned := text.strip_edges()
	if cleaned.begins_with("<thinking>") or cleaned.begins_with("<think>"):
		var paired_regex := RegEx.new()
		paired_regex.compile("^\\s*<(thinking|think)>([\\s\\S]*?)</(thinking|think)>\\s*")
		var paired_match := paired_regex.search(cleaned)
		if paired_match:
			cleaned = cleaned.substr(paired_match.get_end()).strip_edges()
		else:
			var content_after_tag := cleaned.substr(cleaned.find(">") + 1)
			var body_start := content_after_tag.find("\n@")
			if body_start == -1:
				body_start = content_after_tag.find("\n{")
			if body_start == -1:
				body_start = content_after_tag.find("\n#")
			if body_start == -1:
				body_start = content_after_tag.find("\n[")
			if body_start == -1:
				body_start = content_after_tag.find("\n>")
			if body_start >= 0:
				cleaned = content_after_tag.substr(body_start).strip_edges()
	if cleaned.begins_with("```"):
		var lines: PackedStringArray = cleaned.split("\n")
		if lines.size() >= 3:
			lines.remove_at(0)
			if lines[lines.size() - 1].strip_edges() == "```":
				lines.remove_at(lines.size() - 1)
			cleaned = "\n".join(lines).strip_edges()
	cleaned = cleaned.trim_prefix("\"").trim_suffix("\"").strip_edges()
	if cleaned.contains("\n"):
		cleaned = cleaned.split("\n", false, 1)[0].strip_edges()
	return cleaned


static func center_window(window: Control, tree: SceneTree) -> void:
	if window == null or not is_instance_valid(window):
		return
	await tree.process_frame
	var parent := window.get_parent_control()
	if parent != null:
		window.position = (parent.size - window.size) / 2.0
