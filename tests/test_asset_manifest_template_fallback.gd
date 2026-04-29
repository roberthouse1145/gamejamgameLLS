extends Node

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("\n=== asset manifest template fallback test ===")

	var fake_root: String = "user://run/manifest_fallback_test/"
	var setup_err: Error = _prepare_fake_runtime_root(fake_root)
	_assert("prepare fake runtime root", setup_err == OK, "error=%s" % setup_err)
	if setup_err != OK:
		_print_summary()
		return

	StorageManager.clear_asset_manifest_cache()

	var resolved_manifest: Dictionary = StorageManager.get_asset_manifest(null, fake_root)
	_assert("merged manifest exposes template bgm alias", bool(resolved_manifest.get("bgm", {}).has("BGM_日常_晴朗轻松")), str(resolved_manifest))
	_assert("merged manifest exposes template background alias", bool(resolved_manifest.get("backgrounds", {}).has("bg_academy_gate")), str(resolved_manifest))

	var bgm_stream: AudioStream = StorageManager.load_audio_from_path("BGM_日常_晴朗轻松", null, fake_root)
	_assert("audio alias resolves through template fallback", bgm_stream != null, "alias=BGM_日常_晴朗轻松")

	var bg_texture: Texture2D = StorageManager.load_texture_from_path("bg_academy_gate", null, fake_root)
	_assert("background alias resolves through template fallback", bg_texture != null, "alias=bg_academy_gate")

	_cleanup_fake_runtime_root(fake_root)
	_print_summary()


func _prepare_fake_runtime_root(fake_root: String) -> Error:
	_cleanup_fake_runtime_root(fake_root)
	var manifest_dir: String = fake_root + "manifests/"
	var mkdir_err: Error = DirAccess.make_dir_recursive_absolute(manifest_dir)
	if mkdir_err != OK:
		return mkdir_err
	var manifest_file: FileAccess = FileAccess.open(manifest_dir + "asset_aliases.json", FileAccess.WRITE)
	if manifest_file == null:
		return ERR_CANT_CREATE
	manifest_file.store_string("{\"backgrounds\":{},\"images\":{},\"bgm\":{},\"sfx\":{}}")
	manifest_file.close()
	return OK


func _cleanup_fake_runtime_root(fake_root: String) -> void:
	if DirAccess.dir_exists_absolute(fake_root):
		_remove_dir_recursive(fake_root)


func _remove_dir_recursive(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry_name: String = dir.get_next()
	while entry_name != "":
		if not entry_name.begins_with("."):
			var child_path: String = path + entry_name
			if dir.current_is_dir():
				_remove_dir_recursive(child_path + "/")
			else:
				DirAccess.remove_absolute(child_path)
		entry_name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path.trim_suffix("/"))


func _assert(assert_name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass_count += 1
		print("PASS  %s" % assert_name)
	else:
		_fail_count += 1
		print("FAIL  %s  %s" % [assert_name, detail])


func _print_summary() -> void:
	print("SUMMARY  pass=%d fail=%d" % [_pass_count, _fail_count])
