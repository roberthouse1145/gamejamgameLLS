class_name ChatRunner extends Node
## 执行已校验的 Chat DSL。每发出一条消息便暂停，由 UI 播放完成后调用 advance()。

const ChatDslParserClass = preload("res://scripts/chat/chat_dsl_parser.gd")
const MAX_STEPS_WITHOUT_OUTPUT: int = 1000

signal message_emitted(speaker_id: String, text: String, is_player: bool)
signal choices_presented(choices: Array)
signal completed(result: Dictionary)
signal failed(errors: Array)

var _instructions: Array[Dictionary] = []
var _labels: Dictionary = {}
var _context: Dictionary = {}
var _instruction_index: int = 0
var _taken_if_blocks: Dictionary = {}
var _pending_options: Array[Dictionary] = []
var _last_choice_id: String = ""
var _running: bool = false
var _waiting_for_choice: bool = false
var _paused_on_message: bool = false
var _has_failed: bool = false


func start(
	source: String,
	context: Dictionary = {},
	allowed_speakers: Array[String] = [],
	allowed_variable_paths: Array[String] = []
) -> bool:
	reset()
	var parsed: Dictionary = ChatDslParserClass.parse(source, allowed_speakers, allowed_variable_paths)
	if not bool(parsed.get("ok", false)):
		_fail(parsed.get("errors", []))
		return false
	_instructions = parsed["instructions"]
	_labels = parsed["labels"]
	_context = context.duplicate(true)
	_running = true
	_run_until_pause()
	return not _has_failed


func advance() -> bool:
	if not _running or _waiting_for_choice or not _paused_on_message:
		return false
	_paused_on_message = false
	_run_until_pause()
	return true


func choose(option_id: String) -> bool:
	if not _running or not _waiting_for_choice:
		return false
	for option: Dictionary in _pending_options:
		if str(option.get("id", "")) != option_id:
			continue
		_last_choice_id = option_id
		_waiting_for_choice = false
		_pending_options.clear()
		_taken_if_blocks.clear()
		_instruction_index = int(_labels.get(str(option.get("target", "")), -1))
		if _instruction_index < 0:
			_fail(["unknown option target '%s'" % option.get("target", "")])
			return false
		_run_until_pause()
		return true
	return false


func reset() -> void:
	_instructions.clear()
	_labels.clear()
	_context.clear()
	_instruction_index = 0
	_taken_if_blocks.clear()
	_pending_options.clear()
	_last_choice_id = ""
	_running = false
	_waiting_for_choice = false
	_paused_on_message = false
	_has_failed = false


func is_waiting_for_choice() -> bool:
	return _waiting_for_choice


func get_pending_choices() -> Array[Dictionary]:
	return _pending_options.duplicate(true)


func _run_until_pause() -> void:
	var step_count: int = 0
	while _running and not _waiting_for_choice and not _paused_on_message:
		step_count += 1
		if step_count > MAX_STEPS_WITHOUT_OUTPUT:
			_fail(["Chat DSL exceeded the execution loop limit"])
			return
		if _instruction_index < 0 or _instruction_index >= _instructions.size():
			_fail(["Chat DSL reached the end without END"])
			return

		var instruction: Dictionary = _instructions[_instruction_index]
		match str(instruction.get("op", "")):
			"label":
				_instruction_index += 1
			"jump":
				_taken_if_blocks.clear()
				_instruction_index = int(_labels.get(str(instruction.get("target", "")), -1))
				if _instruction_index < 0:
					_fail(["unknown JUMP target '%s'" % instruction.get("target", "")])
			"if", "elif":
				_execute_condition_branch(instruction)
			"else":
				_execute_else(instruction)
			"endif":
				_taken_if_blocks.erase(int(instruction.get("block_id", -1)))
				_instruction_index += 1
			"message":
				_instruction_index += 1
				_paused_on_message = true
				var speaker_id: String = str(instruction.get("speaker", ""))
				message_emitted.emit(speaker_id, str(instruction.get("text", "")), speaker_id == ChatDslParserClass.PLAYER_SPEAKER)
			"choice":
				_present_choice(instruction)
			"end":
				_running = false
				completed.emit({
					"result_id": str(instruction.get("result_id", "")),
					"choice_id": _last_choice_id,
				})
			_:
				_fail(["unknown runtime instruction '%s'" % instruction.get("op", "")])


func _execute_condition_branch(instruction: Dictionary) -> void:
	var current_block_id: int = int(instruction.get("block_id", -1))
	if str(instruction.get("op", "")) == "elif" and bool(_taken_if_blocks.get(current_block_id, false)):
		_taken_if_blocks.erase(current_block_id)
		_instruction_index = int(instruction.get("end_target", _instruction_index + 1))
		return
	var evaluated: Dictionary = ChatDslParserClass.evaluate_condition(str(instruction.get("condition", "")), _context)
	if not bool(evaluated.get("ok", false)):
		_fail([str(evaluated.get("error", "condition evaluation failed"))])
		return
	if bool(evaluated.get("value", false)):
		_taken_if_blocks[current_block_id] = true
		_instruction_index += 1
	else:
		_taken_if_blocks[current_block_id] = false
		_instruction_index = int(instruction.get("false_target", _instruction_index + 1))


func _execute_else(instruction: Dictionary) -> void:
	var current_block_id: int = int(instruction.get("block_id", -1))
	if bool(_taken_if_blocks.get(current_block_id, false)):
		_taken_if_blocks.erase(current_block_id)
		_instruction_index = int(instruction.get("end_target", _instruction_index + 1))
		return
	_taken_if_blocks[current_block_id] = true
	_instruction_index += 1


func _present_choice(instruction: Dictionary) -> void:
	var visible_options: Array[Dictionary] = []
	for option_value: Variant in instruction.get("options", []):
		var option: Dictionary = option_value
		var expression: String = str(option.get("condition", ""))
		if not expression.is_empty():
			var evaluated: Dictionary = ChatDslParserClass.evaluate_condition(expression, _context)
			if not bool(evaluated.get("ok", false)):
				_fail([str(evaluated.get("error", "option condition evaluation failed"))])
				return
			if not bool(evaluated.get("value", false)):
				continue
		visible_options.append(option.duplicate(true))
	if visible_options.is_empty():
		_fail(["CHOICE has no visible OPTION"])
		return
	_pending_options = visible_options
	_waiting_for_choice = true
	var public_choices: Array[Dictionary] = []
	for option: Dictionary in visible_options:
		public_choices.append({"id": option.get("id", ""), "text": option.get("text", "")})
	choices_presented.emit(public_choices)


func _fail(error_values: Variant) -> void:
	_running = false
	_waiting_for_choice = false
	_paused_on_message = false
	_has_failed = true
	var errors: Array[String] = []
	if error_values is Array:
		for value: Variant in error_values:
			errors.append(str(value))
	else:
		errors.append(str(error_values))
	failed.emit(errors)
