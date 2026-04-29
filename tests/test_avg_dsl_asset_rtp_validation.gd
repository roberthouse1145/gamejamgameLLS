extends Control

const AVGCommandClass = preload("res://scripts/avg/resources/avg_command.gd")
const AVGDSLValidatorClass = preload("res://scripts/avg/dsl/avg_dsl_validator.gd")


class MockProject extends Resource:
	var characters: Array = []
	var project_root_path: String = ""


func _ready() -> void:
	print("=== AVG DSL Asset RTP Validation Test ===")

	var project := MockProject.new()
	project.project_root_path = "user://run/trunk/"
	_prepare_mock_trunk_manifest(project.project_root_path)

	var commands: Array = [
		AVGCommandClass.new("CHANGE_BACKGROUND", {"texture_path": "bg_classroom"}),
		AVGCommandClass.new("PLAY_BGM", {"audio_path": "BGM_日常_晴朗轻松"}),
	]

	var validator := AVGDSLValidatorClass.new()
	var result: Dictionary = validator.validate_commands(commands, project, project.project_root_path)
	var errors: Array = result.get("errors", [])

	if not errors.is_empty():
		push_error("RTP fallback validation failed for runtime project asset aliases")
		print("[FAIL] validator still reports runtime asset aliases as missing")
		print("  errors: %s" % str(errors))
		return

	print("[OK] validator accepts runtime project aliases via RTP fallback")
	print("  summary: %s" % str(result.get("summary", "")))


func _prepare_mock_trunk_manifest(project_root: String) -> void:
	var manifest_dir: String = project_root + "manifests"
	DirAccess.make_dir_recursive_absolute(manifest_dir)

	var source_manifest_path: String = "res://templates/tutorial_project/manifests/asset_aliases.json"
	var source_file: FileAccess = FileAccess.open(source_manifest_path, FileAccess.READ)
	if source_file == null:
		push_error("Failed to open template asset manifest for RTP validation test")
		return
	var content: String = source_file.get_as_text()
	source_file.close()

	var target_manifest_path: String = manifest_dir + "/asset_aliases.json"
	var target_file: FileAccess = FileAccess.open(target_manifest_path, FileAccess.WRITE)
	if target_file == null:
		push_error("Failed to create trunk asset manifest for RTP validation test")
		return
	target_file.store_string(content)
	target_file.close()
