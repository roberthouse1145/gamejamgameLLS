class_name PromptPipeline
extends RefCounted

const LORE_FACTS_KEY: String = "lore_facts"
const LORE_CONSTRAINTS_KEY: String = "lore_constraints"


static func build_prompt(prompt_key: String, vars: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	var prompt_manager: Node = _get_prompt_manager()
	if prompt_manager == null or not prompt_manager.has_method("resolve_with_vars"):
		push_warning("[PromptPipeline] PromptManager unavailable for key '%s'" % prompt_key)
		return {
			"prompt": "",
			"pre_resolved_prompt": "",
			"lore_payload": {},
			"vars": vars.duplicate(true),
		}

	var resolved_vars: Dictionary = vars.duplicate(true)
	_ensure_lore_keys(resolved_vars)

	var pre_resolved_prompt: String = str(prompt_manager.resolve_with_vars(prompt_key, resolved_vars)).strip_edges()
	var lore_payload: Dictionary = _resolve_lore(
		str(options.get("lore_mode", "")).strip_edges(),
		options.get("lore_args", {}),
		pre_resolved_prompt
	)
	resolved_vars.merge(build_lore_vars(lore_payload), true)

	return {
		"prompt": str(prompt_manager.resolve_with_vars(prompt_key, resolved_vars)).strip_edges(),
		"pre_resolved_prompt": pre_resolved_prompt,
		"lore_payload": lore_payload,
		"vars": resolved_vars,
	}


static func build_lore_vars(lore_payload: Dictionary) -> Dictionary:
	return {
		LORE_FACTS_KEY: LoreSystem.build_prompt_block(lore_payload.get("facts", [])),
		LORE_CONSTRAINTS_KEY: LoreSystem.build_prompt_block(lore_payload.get("constraints", [])),
	}


static func _resolve_lore(lore_mode: String, lore_args: Variant, pre_resolved_prompt: String) -> Dictionary:
	var args: Dictionary = lore_args if lore_args is Dictionary else {}
	match lore_mode:
		"", "none":
			return {}
		"chat":
			return LoreSystem.resolve_chat(
				args.get("channel", null),
				args.get("npcs", []),
				args.get("chat_history", []),
				args.get("player_messages", []),
				args.get("topic", null),
				pre_resolved_prompt
			)
		"browser":
			return LoreSystem.resolve_browser(
				str(args.get("url", "")),
				str(args.get("design_prompt", "")),
				str(args.get("page_context", "")),
				pre_resolved_prompt
			)
		"avg":
			return LoreSystem.resolve_avg_scene(
				args.get("session", {}),
				pre_resolved_prompt
			)
		_:
			push_warning("[PromptPipeline] Unknown lore mode '%s'" % lore_mode)
			return {}


static func _ensure_lore_keys(vars: Dictionary) -> void:
	if not vars.has(LORE_FACTS_KEY):
		vars[LORE_FACTS_KEY] = ""
	if not vars.has(LORE_CONSTRAINTS_KEY):
		vars[LORE_CONSTRAINTS_KEY] = ""


static func _get_prompt_manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("PromptManager")
