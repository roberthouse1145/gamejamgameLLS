extends Control
## DSL Tester — 交互式测试 DSL 解析和序列化
## Requirements: 10.1, 10.2, 10.3, 10.4

const ParserClass = preload("res://scripts/avg/dsl/avg_dsl_parser.gd")
const SerializerClass = preload("res://scripts/avg/dsl/avg_dsl_serializer.gd")

@onready var _input_edit: TextEdit = %InputEdit
@onready var _output_edit: TextEdit = %OutputEdit
@onready var _parse_button: Button = %ParseButton
@onready var _serialize_button: Button = %SerializeButton
@onready var _roundtrip_button: Button = %RoundTripButton
@onready var _status_label: Label = %StatusLabel

var _parser: RefCounted = ParserClass.new()
var _serializer: RefCounted = SerializerClass.new()
var _last_parsed_commands: Array = []


func _ready() -> void:
	_parse_button.pressed.connect(_on_parse_pressed)
	_serialize_button.pressed.connect(_on_serialize_pressed)
	_roundtrip_button.pressed.connect(_on_roundtrip_pressed)
	_serialize_button.disabled = true
	_status_label.text = "就绪"


func _on_parse_pressed() -> void:
	var dsl_text: String = _input_edit.text
	if dsl_text.strip_edges().is_empty():
		_status_label.text = "输入为空"
		return

	var result: Dictionary = _parser.parse(dsl_text)
	if result.success:
		_last_parsed_commands = result.commands
		_serialize_button.disabled = false
		_output_edit.text = _format_commands(result.commands)
		_status_label.text = "解析成功: %d 条命令" % result.commands.size()
	else:
		_last_parsed_commands = []
		_serialize_button.disabled = true
		_output_edit.text = _format_errors(result.errors)
		_status_label.text = "解析失败: %d 个错误" % result.errors.size()


func _on_serialize_pressed() -> void:
	if _last_parsed_commands.is_empty():
		_status_label.text = "无可序列化的命令（请先解析）"
		return

	var dsl_text: String = _serializer.serialize(_last_parsed_commands)
	_output_edit.text = dsl_text
	_status_label.text = "序列化完成: %d 条命令 → DSL 文本" % _last_parsed_commands.size()


func _on_roundtrip_pressed() -> void:
	var dsl_text: String = _input_edit.text
	if dsl_text.strip_edges().is_empty():
		_status_label.text = "输入为空"
		return

	# Step 1: 解析
	var result1: Dictionary = _parser.parse(dsl_text)
	if not result1.success:
		_output_edit.text = "Round-Trip 第1步失败（解析）:\n" + _format_errors(result1.errors)
		_status_label.text = "Round-Trip 失败: 初始解析出错"
		return

	# Step 2: 序列化
	var serialized: String = _serializer.serialize(result1.commands)

	# Step 3: 再解析
	var result2: Dictionary = _parser.parse(serialized)
	if not result2.success:
		_output_edit.text = "Round-Trip 第3步失败（再解析）:\n" + _format_errors(result2.errors)
		_output_edit.text += "\n\n--- 序列化结果 ---\n" + serialized
		_status_label.text = "Round-Trip 失败: 再解析出错"
		return

	# Step 4: 比较
	var match_result: bool = _commands_equal(result1.commands, result2.commands)
	var output: String = "--- 原始解析: %d 条命令 ---\n" % result1.commands.size()
	output += _format_commands(result1.commands)
	output += "\n\n--- 序列化 DSL ---\n" + serialized
	output += "\n\n--- 再解析: %d 条命令 ---\n" % result2.commands.size()
	output += _format_commands(result2.commands)
	output += "\n\n--- 结果: %s ---" % ("✅ 一致" if match_result else "❌ 不一致")
	_output_edit.text = output

	if match_result:
		_status_label.text = "Round-Trip 成功: %d 条命令一致" % result1.commands.size()
	else:
		_status_label.text = "Round-Trip 失败: 前后结果不一致"


func _format_commands(commands: Array, indent: int = 0) -> String:
	var lines: PackedStringArray = []
	var prefix: String = "  ".repeat(indent)
	for cmd in commands:
		if cmd is AVGCommand:
			lines.append("%s[%s] %s" % [prefix, cmd.command_type, _format_params(cmd.params, indent)])
		elif cmd is Dictionary:
			var ct: String = cmd.get("command_type", "?")
			var p: Dictionary = cmd.get("params", {})
			lines.append("%s[%s] %s" % [prefix, ct, _format_params(p, indent)])
	return "\n".join(lines)


func _format_params(params: Dictionary, indent: int = 0) -> String:
	var parts: PackedStringArray = []
	for key in params:
		var value = params[key]
		if value is Array:
			if key in ["if_commands", "else_commands", "condition_commands"]:
				parts.append("%s=[\n%s\n%s]" % [key, _format_commands(value, indent + 1), "  ".repeat(indent + 1)])
			elif key == "choices":
				parts.append("%s=[\n%s\n%s]" % [key, _format_choices(value, indent + 1), "  ".repeat(indent + 1)])
			else:
				parts.append("%s=%s" % [key, str(value)])
		else:
			parts.append("%s=%s" % [key, str(value)])
	return " ".join(parts)


func _format_choices(choices: Array, indent: int) -> String:
	var lines: PackedStringArray = []
	var prefix: String = "  ".repeat(indent)
	for i in choices.size():
		var choice: Dictionary = choices[i] if choices[i] is Dictionary else {}
		lines.append("%s- \"%s\"" % [prefix, choice.get("text", "")])
		var cmds: Array = choice.get("commands", [])
		if not cmds.is_empty():
			lines.append(_format_commands(cmds, indent + 1))
	return "\n".join(lines)


func _format_errors(errors: Array) -> String:
	var lines: PackedStringArray = []
	for err in errors:
		if err is Dictionary:
			lines.append("第 %d 行: %s" % [err.get("line", 0), err.get("message", "未知错误")])
		else:
			lines.append(str(err))
	return "\n".join(lines)


func _commands_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not _command_equal(a[i], b[i]):
			return false
	return true


func _command_equal(a, b) -> bool:
	var type_a: String = a.command_type if a is AVGCommand else a.get("command_type", "")
	var type_b: String = b.command_type if b is AVGCommand else b.get("command_type", "")
	if type_a != type_b:
		return false
	var params_a: Dictionary = a.params if a is AVGCommand else a.get("params", {})
	var params_b: Dictionary = b.params if b is AVGCommand else b.get("params", {})
	return _params_equal(params_a, params_b)


func _params_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a:
		if not b.has(key):
			return false
		if not _value_equal(a[key], b[key]):
			return false
	return true


func _value_equal(a, b) -> bool:
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _value_equal(a[i], b[i]):
				return false
		return true
	if a is Dictionary and b is Dictionary:
		return _params_equal(a, b)
	if a is AVGCommand and b is AVGCommand:
		return _command_equal(a, b)
	return str(a) == str(b)
