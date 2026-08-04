class_name ChatDslParser extends RefCounted
## Chat DSL 解析、结构校验与只读条件求值工具。

const PLAYER_SPEAKER: String = "player"


static func parse(
	source: String,
	allowed_speakers: Array[String] = [],
	allowed_variable_paths: Array[String] = []
) -> Dictionary:
	var instructions: Array[Dictionary] = []
	var labels: Dictionary = {}
	var errors: Array[String] = []
	var label_references: Array[Dictionary] = []
	var if_stack: Array[Dictionary] = []
	var choice_index: int = -1
	var choice_line: int = -1
	var block_id: int = 0
	var end_count: int = 0
	var lines: PackedStringArray = source.replace("\r\n", "\n").replace("\r", "\n").split("\n")

	for line_index: int in range(lines.size()):
		var line_number: int = line_index + 1
		var line: String = lines[line_index].strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue

		if choice_index >= 0:
			if line == "ENDCHOICE":
				var choice: Dictionary = instructions[choice_index]
				var options: Array = choice.get("options", [])
				if options.is_empty():
					errors.append(_line_error(choice_line, "CHOICE requires at least one OPTION"))
				var has_fallback: bool = false
				for option_value: Variant in options:
					var option: Dictionary = option_value
					if str(option.get("condition", "")).is_empty():
						has_fallback = true
				if not has_fallback:
					errors.append(_line_error(choice_line, "CHOICE requires an unconditional OPTION"))
				choice_index = -1
				choice_line = -1
				continue
			if line.begins_with("OPTION "):
				var option_result: Dictionary = _parse_option(line, line_number, allowed_variable_paths)
				if not bool(option_result.get("ok", false)):
					errors.append_array(_string_array(option_result.get("errors", [])))
					continue
				var option: Dictionary = option_result["option"]
				var choice: Dictionary = instructions[choice_index]
				var options: Array = choice.get("options", [])
				var duplicate_id: bool = false
				for existing_value: Variant in options:
					var existing: Dictionary = existing_value
					if str(existing.get("id", "")) == str(option.get("id", "")):
						duplicate_id = true
						break
				if duplicate_id:
					errors.append(_line_error(line_number, "duplicate OPTION id '%s'" % option.get("id", "")))
				else:
					options.append(option)
					choice["options"] = options
					instructions[choice_index] = choice
					label_references.append({"target": option["target"], "line": line_number})
				continue
			errors.append(_line_error(line_number, "only OPTION or ENDCHOICE is valid inside CHOICE"))
			continue

		if line.begins_with("LABEL "):
			var label_id: String = line.trim_prefix("LABEL ").strip_edges()
			if not if_stack.is_empty():
				errors.append(_line_error(line_number, "LABEL must be at top level"))
			if not _is_valid_id(label_id):
				errors.append(_line_error(line_number, "invalid LABEL id '%s'" % label_id))
			elif labels.has(label_id):
				errors.append(_line_error(line_number, "duplicate LABEL '%s'" % label_id))
			else:
				labels[label_id] = instructions.size()
			instructions.append({"op": "label", "id": label_id, "line": line_number})
			continue

		if line.begins_with("JUMP "):
			var target: String = line.trim_prefix("JUMP ").strip_edges()
			if not _is_valid_id(target):
				errors.append(_line_error(line_number, "invalid JUMP target '%s'" % target))
			instructions.append({"op": "jump", "target": target, "line": line_number})
			label_references.append({"target": target, "line": line_number})
			continue

		if line.begins_with("IF "):
			var expression: String = line.trim_prefix("IF ").strip_edges()
			errors.append_array(_validate_condition(expression, line_number, allowed_variable_paths))
			block_id += 1
			var instruction_index: int = instructions.size()
			instructions.append({
				"op": "if",
				"block_id": block_id,
				"condition": expression,
				"false_target": -1,
				"end_target": -1,
				"line": line_number,
			})
			if_stack.append({
				"block_id": block_id,
				"branches": [instruction_index],
				"else_index": -1,
				"line": line_number,
			})
			continue

		if line.begins_with("ELIF "):
			if if_stack.is_empty():
				errors.append(_line_error(line_number, "ELIF has no matching IF"))
				continue
			var block: Dictionary = if_stack.back()
			if int(block.get("else_index", -1)) >= 0:
				errors.append(_line_error(line_number, "ELIF cannot appear after ELSE"))
				continue
			var expression: String = line.trim_prefix("ELIF ").strip_edges()
			errors.append_array(_validate_condition(expression, line_number, allowed_variable_paths))
			var instruction_index: int = instructions.size()
			var branches: Array = block["branches"]
			var previous_index: int = int(branches.back())
			instructions[previous_index]["false_target"] = instruction_index
			instructions.append({
				"op": "elif",
				"block_id": int(block["block_id"]),
				"condition": expression,
				"false_target": -1,
				"end_target": -1,
				"line": line_number,
			})
			branches.append(instruction_index)
			block["branches"] = branches
			if_stack[if_stack.size() - 1] = block
			continue

		if line == "ELSE":
			if if_stack.is_empty():
				errors.append(_line_error(line_number, "ELSE has no matching IF"))
				continue
			var block: Dictionary = if_stack.back()
			if int(block.get("else_index", -1)) >= 0:
				errors.append(_line_error(line_number, "IF block has more than one ELSE"))
				continue
			var instruction_index: int = instructions.size()
			var branches: Array = block["branches"]
			instructions[int(branches.back())]["false_target"] = instruction_index
			instructions.append({
				"op": "else",
				"block_id": int(block["block_id"]),
				"end_target": -1,
				"line": line_number,
			})
			block["else_index"] = instruction_index
			if_stack[if_stack.size() - 1] = block
			continue

		if line == "ENDIF":
			if if_stack.is_empty():
				errors.append(_line_error(line_number, "ENDIF has no matching IF"))
				continue
			var block: Dictionary = if_stack.pop_back()
			instructions.append({"op": "endif", "block_id": int(block["block_id"]), "line": line_number})
			var end_target: int = instructions.size()
			var branches: Array = block["branches"]
			for branch_value: Variant in branches:
				var branch_index: int = int(branch_value)
				instructions[branch_index]["end_target"] = end_target
			if int(block.get("else_index", -1)) >= 0:
				instructions[int(block["else_index"])]["end_target"] = end_target
			else:
				instructions[int(branches.back())]["false_target"] = end_target
			continue

		if line == "CHOICE":
			choice_index = instructions.size()
			choice_line = line_number
			instructions.append({"op": "choice", "options": [], "line": line_number})
			continue

		if line.begins_with("END "):
			var result_id: String = line.trim_prefix("END ").strip_edges()
			if not _is_valid_id(result_id):
				errors.append(_line_error(line_number, "invalid END result id '%s'" % result_id))
			instructions.append({"op": "end", "result_id": result_id, "line": line_number})
			end_count += 1
			continue

		var colon_index: int = line.find(":")
		if colon_index > 0:
			var speaker_id: String = line.substr(0, colon_index).strip_edges()
			var message_text: String = line.substr(colon_index + 1).strip_edges()
			if not _is_valid_id(speaker_id):
				errors.append(_line_error(line_number, "invalid speaker id '%s'" % speaker_id))
			elif speaker_id != PLAYER_SPEAKER and not allowed_speakers.is_empty() and speaker_id not in allowed_speakers:
				errors.append(_line_error(line_number, "speaker '%s' is not available in this channel" % speaker_id))
			if message_text.is_empty():
				errors.append(_line_error(line_number, "message text cannot be empty"))
			instructions.append({
				"op": "message",
				"speaker": speaker_id,
				"text": message_text,
				"line": line_number,
			})
			continue

		errors.append(_line_error(line_number, "unknown Chat DSL statement"))

	if choice_index >= 0:
		errors.append(_line_error(choice_line, "CHOICE is missing ENDCHOICE"))
	for block_value: Variant in if_stack:
		var block: Dictionary = block_value
		errors.append(_line_error(int(block["line"]), "IF is missing ENDIF"))
	if end_count == 0:
		errors.append("Chat DSL requires at least one END")
	for reference_value: Variant in label_references:
		var reference: Dictionary = reference_value
		if not labels.has(str(reference["target"])):
			errors.append(_line_error(int(reference["line"]), "unknown label '%s'" % reference["target"]))

	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"instructions": instructions,
		"labels": labels,
	}


static func evaluate_condition(expression: String, context: Dictionary) -> Dictionary:
	var parser := ConditionParser.new(expression)
	var parsed: Dictionary = parser.parse_expression()
	if not bool(parsed.get("ok", false)):
		return parsed
	return {
		"ok": true,
		"value": parser.evaluate(parsed["ast"], context),
	}


static func _parse_option(line: String, line_number: int, allowed_paths: Array[String]) -> Dictionary:
	var regex := RegEx.new()
	regex.compile("^OPTION\\s+([A-Za-z_][A-Za-z0-9_-]*)\\s+\"((?:[^\"\\\\]|\\\\.)*)\"\\s*->\\s*([A-Za-z_][A-Za-z0-9_-]*)(?:\\s+IF\\s+(.+))?$")
	var matched: RegExMatch = regex.search(line)
	if matched == null:
		return {"ok": false, "errors": [_line_error(line_number, "invalid OPTION syntax")]}
	var expression: String = matched.get_string(4).strip_edges()
	var errors: Array[String] = []
	if not expression.is_empty():
		errors = _validate_condition(expression, line_number, allowed_paths)
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"option": {
			"id": matched.get_string(1),
			"text": _unescape_string(matched.get_string(2)),
			"target": matched.get_string(3),
			"condition": expression,
			"line": line_number,
		},
	}


static func _validate_condition(expression: String, line_number: int, allowed_paths: Array[String]) -> Array[String]:
	var parser := ConditionParser.new(expression)
	var parsed: Dictionary = parser.parse_expression()
	var errors: Array[String] = []
	if not bool(parsed.get("ok", false)):
		errors.append(_line_error(line_number, str(parsed.get("error", "invalid condition"))))
		return errors
	if allowed_paths.is_empty():
		return errors
	for path_value: Variant in parsed.get("paths", []):
		var path: String = str(path_value)
		if path not in allowed_paths:
			errors.append(_line_error(line_number, "unknown variable path '%s'" % path))
	return errors


static func _is_valid_id(value: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[A-Za-z_][A-Za-z0-9_-]*$")
	return regex.search(value) != null


static func _line_error(line_number: int, message: String) -> String:
	return "line %d: %s" % [line_number, message]


static func _string_array(values: Variant) -> Array[String]:
	var result: Array[String] = []
	if values is Array:
		for value: Variant in values:
			result.append(str(value))
	return result


static func _unescape_string(value: String) -> String:
	return value.replace("\\n", "\n").replace("\\\"", "\"").replace("\\\\", "\\")


class ConditionParser extends RefCounted:
	var _source: String
	var _tokens: Array[Dictionary] = []
	var _position: int = 0
	var _error: String = ""
	var _paths: Dictionary = {}


	func _init(source: String) -> void:
		_source = source


	func parse_expression() -> Dictionary:
		_tokenize()
		if not _error.is_empty():
			return {"ok": false, "error": _error}
		if _tokens.is_empty():
			return {"ok": false, "error": "condition cannot be empty"}
		var ast: Dictionary = _parse_or()
		if not _error.is_empty():
			return {"ok": false, "error": _error}
		if _position < _tokens.size():
			return {"ok": false, "error": "unexpected token '%s'" % _tokens[_position].get("text", "")}
		var paths: Array[String] = []
		for path_value: Variant in _paths:
			paths.append(str(path_value))
		return {"ok": true, "ast": ast, "paths": paths}


	func evaluate(ast: Dictionary, context: Dictionary) -> Variant:
		match str(ast.get("type", "")):
			"literal":
				return ast.get("value")
			"path":
				return _read_path(context, str(ast.get("value", "")))
			"not":
				return not _truthy(evaluate(ast["value"], context))
			"and":
				return _truthy(evaluate(ast["left"], context)) and _truthy(evaluate(ast["right"], context))
			"or":
				return _truthy(evaluate(ast["left"], context)) or _truthy(evaluate(ast["right"], context))
			"compare":
				return _compare(evaluate(ast["left"], context), evaluate(ast["right"], context), str(ast["operator"]))
		return false


	func _parse_or() -> Dictionary:
		var left: Dictionary = _parse_and()
		while _match("operator", "OR"):
			left = {"type": "or", "left": left, "right": _parse_and()}
		return left


	func _parse_and() -> Dictionary:
		var left: Dictionary = _parse_not()
		while _match("operator", "AND"):
			left = {"type": "and", "left": left, "right": _parse_not()}
		return left


	func _parse_not() -> Dictionary:
		if _match("operator", "NOT"):
			return {"type": "not", "value": _parse_not()}
		return _parse_comparison()


	func _parse_comparison() -> Dictionary:
		var left: Dictionary = _parse_primary()
		if not _error.is_empty() or _position >= _tokens.size():
			return left
		var token: Dictionary = _tokens[_position]
		if str(token.get("type", "")) == "operator" and str(token.get("text", "")) in ["==", "!=", ">", ">=", "<", "<="]:
			_position += 1
			return {
				"type": "compare",
				"operator": token["text"],
				"left": left,
				"right": _parse_primary(),
			}
		return left


	func _parse_primary() -> Dictionary:
		if _position >= _tokens.size():
			_error = "condition ended unexpectedly"
			return {}
		var token: Dictionary = _tokens[_position]
		_position += 1
		match str(token.get("type", "")):
			"literal":
				return {"type": "literal", "value": token.get("value")}
			"identifier":
				var path: String = str(token["text"])
				_paths[path] = true
				return {"type": "path", "value": path}
			"left_paren":
				var nested: Dictionary = _parse_or()
				if not _match("right_paren", ")"):
					_error = "missing ')'"
				return nested
		_error = "unexpected token '%s'" % token.get("text", "")
		return {}


	func _match(type_name: String, text: String) -> bool:
		if _position >= _tokens.size():
			return false
		var token: Dictionary = _tokens[_position]
		if str(token.get("type", "")) != type_name or str(token.get("text", "")) != text:
			return false
		_position += 1
		return true


	func _tokenize() -> void:
		var index: int = 0
		while index < _source.length():
			var character: String = _source.substr(index, 1)
			if character in [" ", "\t"]:
				index += 1
				continue
			if character == "(":
				_tokens.append({"type": "left_paren", "text": character})
				index += 1
				continue
			if character == ")":
				_tokens.append({"type": "right_paren", "text": character})
				index += 1
				continue
			if character == "\"":
				index = _tokenize_string(index)
				if not _error.is_empty():
					return
				continue
			if character in ["=", "!", ">", "<"]:
				var operator: String = character
				if index + 1 < _source.length() and _source.substr(index + 1, 1) == "=":
					operator += "="
					index += 1
				if operator in ["=", "!"]:
					_error = "invalid operator '%s'" % operator
					return
				_tokens.append({"type": "operator", "text": operator})
				index += 1
				continue
			if character.is_valid_int() or (character == "-" and index + 1 < _source.length() and _source.substr(index + 1, 1).is_valid_int()):
				index = _tokenize_number(index)
				continue
			if _is_identifier_start(character):
				index = _tokenize_identifier(index)
				continue
			_error = "invalid character '%s'" % character
			return


	func _tokenize_string(start: int) -> int:
		var index: int = start + 1
		var value: String = ""
		while index < _source.length():
			var character: String = _source.substr(index, 1)
			if character == "\"":
				_tokens.append({"type": "literal", "text": value, "value": value})
				return index + 1
			if character == "\\" and index + 1 < _source.length():
				var escaped: String = _source.substr(index + 1, 1)
				value += "\n" if escaped == "n" else escaped
				index += 2
				continue
			value += character
			index += 1
		_error = "unterminated string literal"
		return index


	func _tokenize_number(start: int) -> int:
		var index: int = start
		var has_dot: bool = false
		if _source.substr(index, 1) == "-":
			index += 1
		while index < _source.length():
			var character: String = _source.substr(index, 1)
			if character == "." and not has_dot:
				has_dot = true
				index += 1
				continue
			if not character.is_valid_int():
				break
			index += 1
		var raw: String = _source.substr(start, index - start)
		_tokens.append({
			"type": "literal",
			"text": raw,
			"value": raw.to_float() if has_dot else raw.to_int(),
		})
		return index


	func _tokenize_identifier(start: int) -> int:
		var index: int = start + 1
		while index < _source.length() and _is_identifier_part(_source.substr(index, 1)):
			index += 1
		var raw: String = _source.substr(start, index - start)
		if raw in ["AND", "OR", "NOT"]:
			_tokens.append({"type": "operator", "text": raw})
		elif raw == "true":
			_tokens.append({"type": "literal", "text": raw, "value": true})
		elif raw == "false":
			_tokens.append({"type": "literal", "text": raw, "value": false})
		else:
			_tokens.append({"type": "identifier", "text": raw})
		return index


	func _is_identifier_start(character: String) -> bool:
		return character == "_" or (character.to_lower() != character.to_upper() and character.length() == 1)


	func _is_identifier_part(character: String) -> bool:
		return _is_identifier_start(character) or character.is_valid_int() or character == "."


	func _read_path(context: Dictionary, path: String) -> Variant:
		var current: Variant = context
		for segment: String in path.split(".", false):
			if current is Dictionary and current.has(segment):
				current = current[segment]
			else:
				return null
		return current


	func _truthy(value: Variant) -> bool:
		if value == null:
			return false
		if value is bool:
			return value
		if value is int or value is float:
			return not is_zero_approx(float(value))
		if value is String:
			return not value.is_empty()
		return true


	func _compare(left: Variant, right: Variant, operator: String) -> bool:
		if operator == "==":
			return _equal(left, right)
		if operator == "!=":
			return not _equal(left, right)
		if not _numeric(left) or not _numeric(right):
			return false
		match operator:
			">": return float(left) > float(right)
			">=": return float(left) >= float(right)
			"<": return float(left) < float(right)
			"<=": return float(left) <= float(right)
		return false


	func _equal(left: Variant, right: Variant) -> bool:
		if _numeric(left) and _numeric(right):
			return is_equal_approx(float(left), float(right))
		return left == right


	func _numeric(value: Variant) -> bool:
		return value is int or value is float
