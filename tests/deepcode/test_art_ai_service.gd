extends Node
## 测试 ArtAIService + ImageRegistry
## 不依赖真实 API — 测试请求构建、ImageRegistry 逻辑、b64 保存、配置加载等。
## 注意：不添加自动退出逻辑，由 stop_project 手动停止。

var _all_passed: bool = true
var _results: Array[Dictionary] = []


func _ready() -> void:
	print("========== ArtAIService + ImageRegistry Tests ==========")
	print("")

	# ImageRegistry 测试
	_test_registry_register_and_get()
	_test_registry_list_all()
	_test_registry_unregister()
	_test_registry_clear()
	_test_registry_has_image()
	_test_registry_get_path()
	_test_registry_auto_increment_id()

	# ArtAIService 请求构建测试
	_test_build_request_body_defaults()
	_test_build_request_body_custom_options()
	_test_generate_request_id_unique()
	_test_build_headers()

	# ArtAIService 图片提取测试
	_test_extract_images_url()
	_test_extract_images_b64()
	_test_extract_images_empty()

	# b64 保存测试
	_test_save_b64_to_file()

	# AIConfigManager art profile 测试
	_test_config_manager_art_profile()

	# 真实 API 调用测试（异步）
	await _test_real_api_generate_image()

	print("")
	print("========== Summary ==========")
	for r in _results:
		var status: String = "PASS" if r["passed"] else "FAIL"
		print("[%s] %s" % [status, r["name"]])

	print("")
	if _all_passed:
		print("ALL ART AI SERVICE TESTS PASSED")
	else:
		print("SOME ART AI SERVICE TESTS FAILED")


func _record(test_name: String, passed: bool, detail: String = "") -> void:
	_results.append({"name": test_name, "passed": passed})
	var status: String = "PASS" if passed else "FAIL"
	if detail != "":
		print("[%s] %s — %s" % [status, test_name, detail])
	else:
		print("[%s] %s" % [status, test_name])
	if not passed:
		_all_passed = false


# ============================================================
# ImageRegistry Tests
# ============================================================

func _test_registry_register_and_get() -> void:
	var reg: ImageRegistry = ImageRegistry.new()
	var id: String = reg.register("user://test/img.png", "a cat", "2K")

	var passed: bool = (
		id == "img_001"
		and reg.count() == 1
	)
	var info: Dictionary = reg.get_image(id)
	passed = passed and (
		info.get("local_path") == "user://test/img.png"
		and info.get("prompt") == "a cat"
		and info.get("size") == "2K"
		and info.has("created_at")
	)
	_record("registry_register_and_get", passed)


func _test_registry_list_all() -> void:
	var reg: ImageRegistry = ImageRegistry.new()
	reg.register("user://a.png", "prompt a", "2K")
	reg.register("user://b.png", "prompt b", "1080x1920")

	var list: Array = reg.list_all()
	var passed: bool = (
		list.size() == 2
		and list[0].get("image_id") == "img_001"
		and list[1].get("image_id") == "img_002"
		and list[0].get("local_path") == "user://a.png"
		and list[1].get("local_path") == "user://b.png"
	)
	_record("registry_list_all", passed)


func _test_registry_unregister() -> void:
	var reg: ImageRegistry = ImageRegistry.new()
	var id: String = reg.register("user://x.png")
	var removed: bool = reg.unregister(id)
	var passed: bool = removed and reg.count() == 0 and not reg.has_image(id)
	_record("registry_unregister", passed)


func _test_registry_clear() -> void:
	var reg: ImageRegistry = ImageRegistry.new()
	reg.register("user://1.png")
	reg.register("user://2.png")
	reg.clear()
	var passed: bool = reg.count() == 0
	_record("registry_clear", passed)


func _test_registry_has_image() -> void:
	var reg: ImageRegistry = ImageRegistry.new()
	var id: String = reg.register("user://exists.png")
	var passed: bool = reg.has_image(id) and not reg.has_image("img_999")
	_record("registry_has_image", passed)


func _test_registry_get_path() -> void:
	var reg: ImageRegistry = ImageRegistry.new()
	var id: String = reg.register("user://path/test.png")
	var passed: bool = (
		reg.get_path(id) == "user://path/test.png"
		and reg.get_path("img_999") == ""
	)
	_record("registry_get_path", passed)


func _test_registry_auto_increment_id() -> void:
	var reg: ImageRegistry = ImageRegistry.new()
	var id1: String = reg.register("user://1.png")
	var id2: String = reg.register("user://2.png")
	var id3: String = reg.register("user://3.png")
	var passed: bool = id1 == "img_001" and id2 == "img_002" and id3 == "img_003"
	_record("registry_auto_increment_id", passed,
		"Got: %s, %s, %s" % [id1, id2, id3] if not passed else "")


# ============================================================
# ArtAIService 请求构建测试（通过子类暴露私有方法）
# ============================================================

## 测试用子类，暴露私有方法
class TestableArtService extends ArtAIService:
	func test_build_request_body(prompt: String, options: Dictionary = {}) -> Dictionary:
		return _build_request_body(prompt, options)

	func test_build_headers() -> PackedStringArray:
		return _build_headers()

	func test_generate_request_id() -> String:
		return _generate_request_id()

	func test_extract_images(response: Dictionary) -> Array:
		return _extract_images(response)


func _test_build_request_body_defaults() -> void:
	var svc: TestableArtService = TestableArtService.new()
	svc.model = "test-model"
	svc.default_size = "2K"
	svc.default_response_format = "url"
	svc.default_watermark = true
	add_child(svc)

	var body: Dictionary = svc.test_build_request_body("a beautiful sunset")

	var passed: bool = (
		body.get("model") == "test-model"
		and body.get("prompt") == "a beautiful sunset"
		and body.get("size") == "2K"
		and body.get("response_format") == "url"
		and body.get("stream") == false
		and body.get("watermark") == true
		and body.get("sequential_image_generation") == "disabled"
	)
	_record("build_request_body_defaults", passed,
		"Body: %s" % str(body) if not passed else "")
	svc.queue_free()


func _test_build_request_body_custom_options() -> void:
	var svc: TestableArtService = TestableArtService.new()
	add_child(svc)

	var body: Dictionary = svc.test_build_request_body("test prompt", {
		"model": "custom-model",
		"size": "1080x1920",
		"response_format": "b64_json",
		"watermark": false,
	})

	var passed: bool = (
		body.get("model") == "custom-model"
		and body.get("size") == "1080x1920"
		and body.get("response_format") == "b64_json"
		and body.get("watermark") == false
	)
	_record("build_request_body_custom_options", passed,
		"Body: %s" % str(body) if not passed else "")
	svc.queue_free()


func _test_generate_request_id_unique() -> void:
	var svc: TestableArtService = TestableArtService.new()
	add_child(svc)

	var id1: String = svc.test_generate_request_id()
	var id2: String = svc.test_generate_request_id()
	var id3: String = svc.test_generate_request_id()

	var passed: bool = (
		id1 != id2 and id2 != id3 and id1 != id3
		and id1.begins_with("art_")
		and id2.begins_with("art_")
	)
	_record("generate_request_id_unique", passed,
		"IDs: %s, %s, %s" % [id1, id2, id3] if not passed else "")
	svc.queue_free()


func _test_build_headers() -> void:
	var svc: TestableArtService = TestableArtService.new()
	svc.api_key = "test-key-123"
	add_child(svc)

	var headers: PackedStringArray = svc.test_build_headers()

	var has_content_type: bool = false
	var has_auth: bool = false
	for h in headers:
		if h == "Content-Type: application/json":
			has_content_type = true
		if h == "Authorization: Bearer test-key-123":
			has_auth = true

	var passed: bool = has_content_type and has_auth
	_record("build_headers", passed,
		"Headers: %s" % str(headers) if not passed else "")
	svc.queue_free()


# ============================================================
# 图片提取测试
# ============================================================

func _test_extract_images_url() -> void:
	var svc: TestableArtService = TestableArtService.new()
	add_child(svc)

	var response: Dictionary = {
		"data": [
			{"url": "https://example.com/img1.png"},
			{"url": "https://example.com/img2.png"},
		]
	}
	var images: Array = svc.test_extract_images(response)

	var passed: bool = (
		images.size() == 2
		and images[0].get("url") == "https://example.com/img1.png"
		and images[1].get("url") == "https://example.com/img2.png"
	)
	_record("extract_images_url", passed)
	svc.queue_free()


func _test_extract_images_b64() -> void:
	var svc: TestableArtService = TestableArtService.new()
	add_child(svc)

	var response: Dictionary = {
		"data": [
			{"b64_json": "aGVsbG8="},  # "hello" in base64
		]
	}
	var images: Array = svc.test_extract_images(response)

	var passed: bool = (
		images.size() == 1
		and images[0].has("b64_json")
		and images[0].get("b64_json") == "aGVsbG8="
	)
	_record("extract_images_b64", passed)
	svc.queue_free()


func _test_extract_images_empty() -> void:
	var svc: TestableArtService = TestableArtService.new()
	add_child(svc)

	var images: Array = svc.test_extract_images({"data": []})
	var images2: Array = svc.test_extract_images({})

	var passed: bool = images.size() == 0 and images2.size() == 0
	_record("extract_images_empty", passed)
	svc.queue_free()


# ============================================================
# b64 保存测试
# ============================================================

func _test_save_b64_to_file() -> void:
	# 创建一个简单的 1x1 白色 PNG 的 base64
	# 手动构造测试数据：直接用已知字节
	var test_data: String = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg=="
	var save_path: String = "user://test_art_b64_save.png"

	# 清理旧文件
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)

	var success: bool = ArtAIService.save_b64_to_file(test_data, save_path)
	var file_exists: bool = FileAccess.file_exists(save_path)

	var passed: bool = success and file_exists
	if passed:
		# 验证文件不为空
		var file: FileAccess = FileAccess.open(save_path, FileAccess.READ)
		if file:
			passed = file.get_length() > 0
			file.close()
		else:
			passed = false

	_record("save_b64_to_file", passed,
		"success=%s file_exists=%s" % [str(success), str(file_exists)] if not passed else "")

	# 清理
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)


# ============================================================
# AIConfigManager art profile 测试
# ============================================================

func _test_config_manager_art_profile() -> void:
	var mgr: AIConfigManager = AIConfigManager.new()
	var loaded: bool = mgr.load_config()

	if not loaded:
		_record("config_manager_art_profile", false, "Failed to load config")
		return

	# 检查 art_ai role 存在
	var roles: Array[String] = mgr.get_roles()
	var has_art_role: bool = "art_ai" in roles

	# 检查 volcengine_art profile 存在
	var profiles: Array[String] = mgr.get_profiles()
	var has_art_profile: bool = "volcengine_art" in profiles

	# 检查配置内容
	var config: Dictionary = mgr.get_config_for_role("art_ai")
	var config_valid: bool = (
		config.get("type") == "image"
		and config.get("base_url") == "https://ark.cn-beijing.volces.com/api/v3"
		and not config.get("api_key", "").is_empty()
		and config.get("model") == "doubao-seedream-4-5-251128"
	)

	# 测试 apply_to_art_service
	var svc: ArtAIService = ArtAIService.new()
	add_child(svc)
	var applied: bool = mgr.apply_to_art_service(svc, "art_ai")
	var svc_valid: bool = (
		svc.api_base_url == "https://ark.cn-beijing.volces.com/api/v3"
		and not svc.api_key.is_empty()
		and svc.model == "doubao-seedream-4-5-251128"
	)

	# 测试 apply_to_art_service 拒绝 chat 类型
	var rejected: bool = not mgr.apply_to_art_service(svc, "test_chat")

	var passed: bool = has_art_role and has_art_profile and config_valid and applied and svc_valid and rejected
	_record("config_manager_art_profile", passed,
		"role=%s profile=%s config=%s applied=%s svc=%s rejected=%s" % [
			str(has_art_role), str(has_art_profile), str(config_valid),
			str(applied), str(svc_valid), str(rejected)
		] if not passed else "")
	svc.queue_free()


# ============================================================
# 真实 API 调用测试（需要网络）
# ============================================================

func _test_real_api_generate_image() -> void:
	var svc: ArtAIService = ArtAIService.new()
	svc.name = "RealArtService"
	add_child(svc)

	# 用 AIConfigManager 加载真实配置
	var mgr: AIConfigManager = AIConfigManager.new()
	if not mgr.load_config():
		_record("real_api_generate_image", false, "Failed to load config")
		svc.queue_free()
		return

	if not mgr.apply_to_art_service(svc, "art_ai"):
		_record("real_api_generate_image", false, "Failed to apply art config")
		svc.queue_free()
		return

	print("[RealAPI] api_base_url=%s model=%s api_key=%s..." % [
		svc.api_base_url, svc.model, svc.api_key.left(8)
	])

	# 发起真实请求（Seedream 要求最低 3686400 像素，用 2K）
	var request_id: String = svc.generate_image("一只可爱的白色小猫坐在窗台上，阳光照射，温暖氛围", {
		"size": "2K",
		"response_format": "url",
	})

	print("[RealAPI] Request sent: %s" % request_id)

	# 等待结果
	var state: Dictionary = {"done": false, "success": false, "result": {}, "error": ""}

	svc.generation_completed.connect(func(req_id: String, result: Dictionary) -> void:
		if req_id == request_id:
			state["success"] = true
			state["result"] = result
			state["done"] = true
	)

	svc.generation_failed.connect(func(req_id: String, error: String) -> void:
		if req_id == request_id:
			state["error"] = error
			state["done"] = true
	)

	# 等待（最多 120 秒）
	var waited: float = 0.0
	while not state["done"] and waited < 120.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5

	if not state["done"]:
		_record("real_api_generate_image", false, "Timeout after 120s")
		svc.queue_free()
		return

	if not state["success"]:
		_record("real_api_generate_image", false, "API error: %s" % state["error"])
		print("[RealAPI] FAILED: %s" % state["error"])
		svc.queue_free()
		return

	# 验证结果
	var images: Array = state["result"].get("images", [])
	print("[RealAPI] Got %d image(s)" % images.size())

	if images.size() == 0:
		_record("real_api_generate_image", false, "No images returned")
		svc.queue_free()
		return

	var first_img: Dictionary = images[0]
	var has_url: bool = first_img.has("url")
	var has_b64: bool = first_img.has("b64_json")
	print("[RealAPI] First image: has_url=%s has_b64=%s" % [str(has_url), str(has_b64)])

	if has_url:
		print("[RealAPI] URL: %s" % str(first_img["url"]).left(120))

	# 测试保存到本地
	var save_dir: String = "user://test_generated/"
	var saved_paths: Array = await svc.save_images(images, save_dir, "test_cat")
	print("[RealAPI] Saved %d file(s)" % saved_paths.size())

	for p in saved_paths:
		var exists: bool = FileAccess.file_exists(p)
		print("[RealAPI] %s exists=%s" % [p, str(exists)])

	# 注册到 ImageRegistry
	var reg: ImageRegistry = ImageRegistry.new()
	for p in saved_paths:
		var img_id: String = reg.register(p, "test cat", "2K")
		print("[RealAPI] Registered: %s -> %s" % [img_id, p])

	var passed: bool = (
		images.size() > 0
		and saved_paths.size() > 0
		and reg.count() > 0
	)
	_record("real_api_generate_image", passed,
		"images=%d saved=%d registered=%d" % [images.size(), saved_paths.size(), reg.count()])

	svc.queue_free()
