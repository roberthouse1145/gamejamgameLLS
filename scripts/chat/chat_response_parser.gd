class_name ChatResponseParser extends RefCounted
## LinkChat AI 响应解析器
## 负责结构化回复、行协议、卡片与完成标记的解析

var _sanitize_message_card: Callable = Callable()
var _protocol_direct_action_commands: Array[String] = []


func setup(sanitize_message_card: Callable, protocol_direct_action_commands: Array[String]) -> ChatResponseParser:
	_sanitize_message_card = sanitize_message_card
	_protocol_direct_action_commands.assign(protocol_direct_action_commands)
	return self


func strip_thinking_tags(text: String) -> Dictionary:
	var regex := RegEx.new()
	regex.compile("<(thinking|think)>([\\s\\S]*?)</(thinking|think)>")
	var match := regex.search(text)
	if match:
		var opening_tag := match.get_string(1).strip_edges().to_lower()
		var closing_tag := match.get_string(3).strip_edges().to_lower()
		if opening_tag == closing_tag or (opening_tag == "thinking" and closing_tag == "think"):
			var thinking := match.get_string(2).strip_edges()
			var body := text.substr(match.get_end()).strip_edges()
			return {"thinking": thinking, "body": body}
	var fallback_regex := RegEx.new()
	fallback_regex.compile("<thinking>([\\s\\S]*?)</think>")
	var fallback_match := fallback_regex.search(text)
	if fallback_match:
		var fallback_thinking := fallback_match.get_string(1).strip_edges()
		var fallback_body := text.substr(fallback_match.get_end()).strip_edges()
		return {"thinking": fallback_thinking, "body": fallback_body}
	var truncated_regex := RegEx.new()
	truncated_regex.compile("^\\s*<(thinking|think)>([\\s\\S]*)$")
	var truncated_match := truncated_regex.search(text)
	if truncated_match:
		var content_after_tag := truncated_match.get_string(2)
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
			var truncated_thinking := content_after_tag.substr(0, body_start).strip_edges()
			var truncated_body := content_after_tag.substr(body_start).strip_edges()
			return {"thinking": truncated_thinking, "body": truncated_body}
	return {"thinking": "", "body": text}


func parse_ai_response_text(text: String, fallback_npc_id: String) -> Dictionary:
	var clean_text := _strip_response_code_fence(text.strip_edges())
	if clean_text.is_empty():
		return _empty_parse_result()

	var line_protocol_result := parse_line_protocol_response(clean_text, fallback_npc_id)
	if bool(line_protocol_result.get("valid", false)):
		line_protocol_result.erase("valid")
		return line_protocol_result

	var has_complete_marker: bool = "[TOPIC_COMPLETE]" in clean_text
	var has_failed_marker: bool = "[TOPIC_FAILED]" in clean_text
	var parse_source: String = clean_text.replace("[TOPIC_COMPLETE]", "").replace("[TOPIC_FAILED]", "")
	var json_str := _extract_json_from_text(parse_source)
	var _json := JSON.new()
	var response_json: Variant = _json.data if _json.parse(json_str) == OK else null
	if response_json != null and response_json is Dictionary:
		var result := _parse_json_response_dict(response_json as Dictionary, fallback_npc_id, has_complete_marker)
		if has_failed_marker:
			result["topic_failed"] = true
			result["topic_complete"] = true
		return result

	push_warning("[ChatResponseParser] Failed to parse structured AI response. Fallback to raw text message.")
	return {
		"messages": [{
			"speaker": fallback_npc_id,
			"content": _build_fallback_ai_message(clean_text),
		}],
		"recommended_replies": [],
		"topic_complete": has_complete_marker or has_failed_marker,
		"topic_failed": has_failed_marker,
		"topic_summary": "",
		"events": [],
		"actions": [],
	}


func parse_line_protocol_response(text: String, fallback_npc_id: String) -> Dictionary:
	var parsed_messages: Array[Dictionary] = []
	var recommended_replies: Array[String] = []
	var has_complete_marker: bool = false
	var has_failed_marker: bool = false
	var has_explicit_complete_command: bool = false
	var complete_summary: String = ""
	var parsed_events: Array[Dictionary] = []
	var parsed_actions: Array[Dictionary] = []
	var saw_protocol_line: bool = false
	var saw_message_line: bool = false

	for raw_line in text.split("\n"):
		var line := str(raw_line).strip_edges()
		if line.is_empty():
			continue
		if line == "[TOPIC_COMPLETE]":
			has_complete_marker = true
			saw_protocol_line = true
			continue
		if line == "[TOPIC_FAILED]":
			has_complete_marker = true
			has_failed_marker = true
			saw_protocol_line = true
			continue
		var bracket_command := _parse_bracket_command(line)
		if not bracket_command.is_empty():
			var cmd_name := str(bracket_command.get("name", ""))
			var cmd_params: Dictionary = bracket_command.get("params", {})
			match cmd_name:
				"event":
					var parsed_event := _parse_protocol_event(cmd_params)
					if not parsed_event.is_empty():
						parsed_events.append(parsed_event)
						saw_protocol_line = true
				"complete":
					has_complete_marker = true
					has_explicit_complete_command = true
					complete_summary = str(cmd_params.get("summary", cmd_params.get("text", ""))).strip_edges()
					saw_protocol_line = true
				_:
					var parsed_action := _parse_protocol_action(_normalize_protocol_action_command(cmd_name, cmd_params))
					if not parsed_action.is_empty():
						parsed_actions.append(parsed_action)
						saw_protocol_line = true
			continue
		if line.begins_with("!"):
			var command := _parse_line_protocol_command(line)
			var command_name := str(command.get("name", ""))
			var command_params: Dictionary = command.get("params", {})
			match command_name:
				"complete":
					has_complete_marker = true
					has_explicit_complete_command = true
					complete_summary = str(command_params.get("summary", command_params.get("text", ""))).strip_edges()
					saw_protocol_line = true
				"event":
					var parsed_event := _parse_protocol_event(command_params)
					if not parsed_event.is_empty():
						parsed_events.append(parsed_event)
						saw_protocol_line = true
				_:
					var parsed_action := _parse_protocol_action(_normalize_protocol_action_command(command_name, command_params))
					if not parsed_action.is_empty():
						parsed_actions.append(parsed_action)
						saw_protocol_line = true
			continue
		if line.begins_with(">"):
			var reply := line.trim_prefix("> ").trim_prefix(">\t").trim_prefix(">")
			reply = reply.strip_edges()
			if not reply.is_empty():
				recommended_replies.append(reply)
				saw_protocol_line = true
			continue
		if line.begins_with("@"):
			var parsed_message := _parse_line_protocol_message(line, fallback_npc_id)
			if parsed_message.is_empty():
				continue
			var parsed_content := str(parsed_message.get("content", ""))
			if "[TOPIC_COMPLETE]" in parsed_content:
				has_complete_marker = true
			if "[TOPIC_FAILED]" in parsed_content:
				has_complete_marker = true
				has_failed_marker = true
			parsed_messages.append(parsed_message)
			saw_protocol_line = true
			saw_message_line = true
			continue
		if saw_message_line and _attach_standalone_card_line(parsed_messages, line):
			saw_protocol_line = true
			continue
		if saw_message_line and not parsed_messages.is_empty():
			var last_message := parsed_messages[parsed_messages.size() - 1]
			var last_content := str(last_message.get("content", ""))
			last_message["content"] = line if last_content.is_empty() else "%s\n%s" % [last_content, line]
			if "[TOPIC_COMPLETE]" in line:
				has_complete_marker = true
			if "[TOPIC_FAILED]" in line:
				has_complete_marker = true
				has_failed_marker = true
			parsed_messages[parsed_messages.size() - 1] = last_message

	if has_complete_marker and not has_failed_marker:
		_attach_complete_marker_to_messages(parsed_messages)

	return {
		"valid": saw_protocol_line and (
			saw_message_line
			or not recommended_replies.is_empty()
			or has_explicit_complete_command
			or not parsed_events.is_empty()
			or not parsed_actions.is_empty()
		),
		"messages": parsed_messages,
		"recommended_replies": recommended_replies,
		"topic_complete": has_complete_marker,
		"topic_failed": has_failed_marker,
		"topic_summary": complete_summary,
		"events": parsed_events,
		"actions": parsed_actions,
	}


func messages_have_complete_marker(messages: Array[Dictionary]) -> bool:
	for i in range(messages.size() - 1, -1, -1):
		var content_text := str(messages[i].get("content", ""))
		if "[TOPIC_COMPLETE]" in content_text:
			return true
	return false


func _empty_parse_result() -> Dictionary:
	return {
		"messages": [],
		"recommended_replies": [],
		"topic_complete": false,
		"topic_summary": "",
		"events": [],
		"actions": [],
	}


func _extract_json_from_text(text: String) -> String:
	var clean_text := text.strip_edges()
	if clean_text.begins_with("{") and clean_text.ends_with("}"):
		return clean_text

	var regex := RegEx.new()
	regex.compile("```(?:json)?\\n?([\\s\\S]*?)\\n?```")
	var match := regex.search(clean_text)
	if match:
		var extracted := match.get_string(1).strip_edges()
		if extracted.begins_with("{") and extracted.ends_with("}"):
			return extracted

	var first_brace := clean_text.find("{")
	var last_brace := clean_text.rfind("}")
	if first_brace != -1 and last_brace != -1 and last_brace > first_brace:
		return clean_text.substr(first_brace, last_brace - first_brace + 1)

	return clean_text


func _parse_json_response_dict(response_json: Dictionary, fallback_npc_id: String, has_complete_marker: bool) -> Dictionary:
	var parsed_messages := _parse_response_messages_array(response_json.get("messages", []), fallback_npc_id)
	var topic_complete: bool = has_complete_marker or bool(response_json.get("topic_complete", false))
	var topic_summary: String = str(response_json.get("topic_summary", response_json.get("summary", ""))).strip_edges()
	if topic_complete:
		_attach_complete_marker_to_messages(parsed_messages)

	var recommended_replies: Array[String] = []
	var raw_replies: Variant = response_json.get("recommended_replies", [])
	if raw_replies is Array:
		for reply in raw_replies:
			if reply is String and not reply.is_empty():
				recommended_replies.append(str(reply))

	var parsed_events := _parse_response_events_array(response_json.get("events", []))
	var parsed_actions := _parse_response_actions_array(response_json.get("actions", []))

	return {
		"messages": parsed_messages,
		"recommended_replies": recommended_replies,
		"topic_complete": topic_complete,
		"topic_summary": topic_summary,
		"events": parsed_events,
		"actions": parsed_actions,
	}


func _parse_response_messages_array(raw_messages: Variant, fallback_npc_id: String) -> Array[Dictionary]:
	var parsed_messages: Array[Dictionary] = []
	if not (raw_messages is Array):
		return parsed_messages

	for msg in raw_messages:
		if msg is Dictionary and (msg.has("content") or msg.has("card")):
			var parsed_msg := {
				"speaker": msg.get("speaker", fallback_npc_id),
				"content": str(msg.get("content", "")),
			}
			if msg.has("card") and msg["card"] is Dictionary:
				var card := _sanitize_card(msg["card"])
				if not card.is_empty():
					parsed_msg["card"] = card
			parsed_messages.append(parsed_msg)
		elif msg is String:
			parsed_messages.append({
				"speaker": fallback_npc_id,
				"content": str(msg),
			})
	return parsed_messages


func _parse_response_events_array(raw_events: Variant) -> Array[Dictionary]:
	var parsed_events: Array[Dictionary] = []
	if not (raw_events is Array):
		return parsed_events

	for raw_event in raw_events:
		if not (raw_event is Dictionary):
			continue
		var event_data := _parse_protocol_event(raw_event as Dictionary)
		if event_data.is_empty():
			continue
		parsed_events.append(event_data)

	return parsed_events


func _parse_response_actions_array(raw_actions: Variant) -> Array[Dictionary]:
	var parsed_actions: Array[Dictionary] = []
	if not (raw_actions is Array):
		return parsed_actions

	for raw_action in raw_actions:
		if not (raw_action is Dictionary):
			continue
		var action_data := _parse_protocol_action(raw_action as Dictionary)
		if action_data.is_empty():
			continue
		parsed_actions.append(action_data)

	return parsed_actions


func _parse_bracket_command(line: String) -> Dictionary:
	if not line.begins_with("[") or not line.ends_with("]"):
		return {}
	var inner := line.substr(1, line.length() - 2).strip_edges()
	if inner.is_empty():
		return {}
	if inner.begins_with("card:"):
		return {}
	var first_space := inner.find(" ")
	var command_name := inner
	var params_text := ""
	if first_space != -1:
		command_name = inner.substr(0, first_space).strip_edges()
		params_text = inner.substr(first_space + 1).strip_edges()
	command_name = command_name.to_lower()
	if command_name not in ["action", "event", "complete"] and command_name not in _protocol_direct_action_commands:
		return {}
	return {
		"name": command_name,
		"params": _parse_protocol_key_values(params_text),
	}


func _parse_line_protocol_command(line: String) -> Dictionary:
	if not line.begins_with("!"):
		return {}

	var content := line.substr(1).strip_edges()
	if content.is_empty():
		return {}

	var first_space := content.find(" ")
	var command_name := content
	var params_text := ""
	if first_space != -1:
		command_name = content.substr(0, first_space).strip_edges()
		params_text = content.substr(first_space + 1).strip_edges()

	return {
		"name": command_name.to_lower(),
		"params": _parse_protocol_key_values(params_text),
	}


func _normalize_protocol_action_command(command_name: String, params: Dictionary) -> Dictionary:
	var normalized_name := command_name.strip_edges().to_lower()
	if normalized_name.is_empty():
		return {}

	if normalized_name == "action":
		return params.duplicate(true)

	if normalized_name not in _protocol_direct_action_commands:
		return {}

	var action_data := params.duplicate(true)
	action_data["type"] = normalized_name
	return action_data


func _parse_protocol_event(raw_data: Dictionary) -> Dictionary:
	var event_id := str(raw_data.get("id", raw_data.get("event_id", ""))).strip_edges()
	if event_id.is_empty():
		return {}

	var payload := raw_data.duplicate(true)
	payload.erase("id")
	payload.erase("event_id")
	var timing := _normalize_protocol_timing(str(payload.get("timing", "after_messages")))
	payload.erase("timing")

	return {
		"id": event_id,
		"timing": timing,
		"payload": payload,
	}


func _parse_protocol_action(raw_data: Dictionary) -> Dictionary:
	var action_type := str(raw_data.get("type", "")).strip_edges().to_lower()
	if action_type.is_empty():
		return {}

	var action := raw_data.duplicate(true)
	action["type"] = action_type
	action["timing"] = _normalize_protocol_timing(str(action.get("timing", "after_messages")))
	return action


func _parse_line_protocol_message(line: String, fallback_npc_id: String) -> Dictionary:
	var colon_index := line.find(":")
	if colon_index <= 1:
		return {}

	var speaker := line.substr(1, colon_index - 1).strip_edges()
	if speaker.is_empty():
		speaker = fallback_npc_id

	var body := line.substr(colon_index + 1).strip_edges()
	var card_payload := _extract_inline_card_from_text(body)
	var content := str(card_payload.get("content", "")).strip_edges()
	var card: Dictionary = card_payload.get("card", {})
	if content.is_empty() and card.is_empty():
		return {}

	var parsed_message := {
		"speaker": speaker,
		"content": content,
	}
	if not card.is_empty():
		parsed_message["card"] = card
	return parsed_message


func _attach_standalone_card_line(parsed_messages: Array[Dictionary], line: String) -> bool:
	if parsed_messages.is_empty():
		return false

	var card_payload := _extract_inline_card_from_text(line)
	var card: Dictionary = card_payload.get("card", {})
	if card.is_empty():
		return false

	var last_message := parsed_messages[parsed_messages.size() - 1]
	if last_message.has("card") and last_message["card"] is Dictionary and not (last_message["card"] as Dictionary).is_empty():
		return false

	var content := str(card_payload.get("content", "")).strip_edges()
	var last_content := str(last_message.get("content", "")).strip_edges()
	if not content.is_empty():
		last_message["content"] = content if last_content.is_empty() else "%s\n%s" % [last_content, content]
	last_message["card"] = card
	parsed_messages[parsed_messages.size() - 1] = last_message
	return true


func _extract_inline_card_from_text(text: String) -> Dictionary:
	var regex := RegEx.new()
	regex.compile("\\[card:([a-zA-Z0-9_]+)([^\\]]*)\\]")
	var match := regex.search(text)
	if match == null:
		return {"content": text.strip_edges(), "card": {}}

	var card_type := match.get_string(1).strip_edges().to_lower()
	var params_text := match.get_string(2).strip_edges()
	var card: Dictionary = {"type": card_type}
	var parsed_params := _parse_protocol_key_values(params_text)
	for key in parsed_params.keys():
		card[key] = parsed_params[key]

	var remaining := "%s%s" % [
		text.substr(0, match.get_start()),
		text.substr(match.get_end()),
	]
	var sanitized_card := _sanitize_card(card)
	return {
		"content": remaining.strip_edges(),
		"card": sanitized_card,
	}


func _parse_protocol_key_values(text: String) -> Dictionary:
	var values: Dictionary = {}
	if text.is_empty():
		return values

	var regex := RegEx.new()
	regex.compile("([a-zA-Z0-9_]+)=(\"(?:\\\\.|[^\"])*\"|'(?:\\\\.|[^'])*'|\\S+)")
	for match in regex.search_all(text):
		var key := match.get_string(1).strip_edges()
		var raw_value := match.get_string(2)
		values[key] = _coerce_protocol_value(raw_value)
	return values


func _coerce_protocol_value(raw_value: String) -> Variant:
	var value := raw_value.strip_edges()
	if value.length() >= 2:
		var first_char := value.substr(0, 1)
		var last_char := value.substr(value.length() - 1, 1)
		if (first_char == '"' and last_char == '"') or (first_char == "'" and last_char == "'"):
			value = value.substr(1, value.length() - 2)
			value = value.replace("\\n", "\n")
			value = value.replace('\\"', '"')
			value = value.replace("\\'", "'")

	var lower_value := value.to_lower()
	if lower_value == "true":
		return true
	if lower_value == "false":
		return false
	if value.is_valid_int():
		return int(value)
	if value.is_valid_float():
		return float(value)
	return value


func _strip_response_code_fence(text: String) -> String:
	var clean_text := text.strip_edges()
	var regex := RegEx.new()
	regex.compile("```(?:[a-zA-Z0-9_+-]+)?\\n?([\\s\\S]*?)\\n?```")
	var match := regex.search(clean_text)
	if match:
		return match.get_string(1).strip_edges()
	return clean_text


func _build_fallback_ai_message(text: String) -> String:
	var cleaned_text := _strip_response_code_fence(text.strip_edges())
	cleaned_text = _strip_protocol_control_lines(cleaned_text)
	cleaned_text = cleaned_text.replace("[TOPIC_COMPLETE]", "").replace("[TOPIC_FAILED]", "").strip_edges()
	return cleaned_text


func _strip_protocol_control_lines(text: String) -> String:
	var kept_lines: Array[String] = []
	for raw_line in text.split("\n"):
		var line := str(raw_line)
		var stripped := line.strip_edges()
		if stripped == "[TOPIC_COMPLETE]":
			continue
		if stripped == "[TOPIC_FAILED]":
			continue
		if not _parse_bracket_command(stripped).is_empty():
			continue
		var bang_command := _parse_line_protocol_command(stripped)
		if not bang_command.is_empty() and not _normalize_protocol_action_command(str(bang_command.get("name", "")), bang_command.get("params", {})).is_empty():
			continue
		if not bang_command.is_empty() and str(bang_command.get("name", "")) in ["event", "complete"]:
			continue
		kept_lines.append(line)
	return "\n".join(kept_lines).strip_edges()


func _attach_complete_marker_to_messages(messages: Array[Dictionary]) -> void:
	if messages.is_empty():
		return
	for i in range(messages.size() - 1, -1, -1):
		var message := messages[i]
		var content := str(message.get("content", ""))
		if "[TOPIC_COMPLETE]" in content:
			return
		message["content"] = "%s[TOPIC_COMPLETE]" % content
		messages[i] = message
		return


func _sanitize_card(card: Dictionary) -> Dictionary:
	if _sanitize_message_card.is_null():
		return {}
	var result: Variant = _sanitize_message_card.call(card)
	if result is Dictionary:
		return (result as Dictionary).duplicate(true)
	return {}


func _normalize_protocol_timing(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	match normalized:
		"immediate":
			return "immediate"
		_:
			return "after_messages"
