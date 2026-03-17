class_name ArtAIService extends Node
## ArtAIService — 图像生成 API 服务
## 支持火山引擎豆包 Seedream（OpenAI Images API 兼容格式）。
## 功能：text-to-image、image-to-image、连续多图生成。
## 纯工具类节点，不需要配套 .tscn。

#region 信号
signal generation_completed(request_id: String, result: Dictionary)
signal generation_failed(request_id: String, error: String)
#endregion

#region 导出配置
@export_group("API Configuration")
@export var api_base_url: String = "https://ark.cn-beijing.volces.com/api/v3"
@export var api_key: String = ""
@export var model: String = "doubao-seedream-4-5-251128"

@export_group("Default Settings")
@export var default_size: String = "2K"
@export var default_response_format: String = "url"
@export var default_watermark: bool = false
@export var timeout: float = 120.0
#endregion

#region 内部变量
var _active_requests: Dictionary = {}  # request_id -> HTTPRequest
var _request_counter: int = 0
#endregion


#region 公共 API

## 生成图片 — 文生图 / 图生图统一入口
## [param prompt] 图片描述
## [param options] 可选参数，支持 size, response_format, watermark, reference_images 等
##   reference_images: 参考图，可以是单个 URL/路径字符串、URL 数组、或包含 url/b64 的字典数组
## 返回 request_id
func generate_image(prompt: String, options: Dictionary = {}) -> String:
	var body: Dictionary = _build_request_body(prompt, options)
	# 参考图 → 图生图
	if options.has("reference_images"):
		body["image"] = options["reference_images"]
	return _send_request(body)


## 连续多图生成（可选参考图）
func generate_sequential(prompt: String, max_images: int = 4, options: Dictionary = {}) -> String:
	var body: Dictionary = _build_request_body(prompt, options)
	if options.has("reference_images"):
		body["image"] = options["reference_images"]
	body["sequential_image_generation"] = "auto"
	body["sequential_image_generation_options"] = {"max_images": max_images}
	return _send_request(body)


## 取消请求
func cancel_request(request_id: String) -> bool:
	if _active_requests.has(request_id):
		var http: HTTPRequest = _active_requests[request_id]
		if is_instance_valid(http):
			http.cancel_request()
			http.queue_free()
		_active_requests.erase(request_id)
		return true
	return false


## 取消所有请求
func cancel_all() -> void:
	for request_id in _active_requests.keys():
		cancel_request(request_id)


## 是否有活跃请求
func is_busy() -> bool:
	return _active_requests.size() > 0
#endregion


#region 内部方法

func _generate_request_id() -> String:
	_request_counter += 1
	return "art_%d_%d" % [Time.get_ticks_msec(), _request_counter]


func _build_request_body(prompt: String, options: Dictionary) -> Dictionary:
	var body: Dictionary = {
		"model": options.get("model", model),
		"prompt": prompt,
		"size": options.get("size", default_size),
		"response_format": options.get("response_format", default_response_format),
		"stream": false,
		"watermark": options.get("watermark", default_watermark),
	}

	# sequential_image_generation 默认 disabled
	if not options.has("sequential"):
		body["sequential_image_generation"] = options.get("sequential_image_generation", "disabled")

	return body


func _build_headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key,
	])


func _send_request(body: Dictionary) -> String:
	var request_id: String = _generate_request_id()

	var http: HTTPRequest = HTTPRequest.new()
	http.timeout = timeout
	add_child(http)
	http.request_completed.connect(_on_request_completed.bind(request_id))

	_active_requests[request_id] = http

	var url: String = api_base_url + "/images/generations"
	var body_json: String = JSON.stringify(body)

	print("[ArtAIService] Sending request %s to %s" % [request_id, url])

	var error: int = http.request(url, _build_headers(), HTTPClient.METHOD_POST, body_json)
	if error != OK:
		_cleanup_request(request_id)
		generation_failed.emit(request_id, "Failed to create HTTP request: %d" % error)
		return request_id

	return request_id


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request_id: String) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		var error_msg: String = _get_http_error_message(result)
		print("[ArtAIService] HTTP error for %s: %s" % [request_id, error_msg])
		_cleanup_request(request_id)
		generation_failed.emit(request_id, error_msg)
		return

	var response_text: String = body.get_string_from_utf8()

	if response_code != 200:
		print("[ArtAIService] API error %d for %s: %s" % [response_code, request_id, response_text.left(500)])
		var error_msg: String = "API error (HTTP %d)" % response_code
		# 尝试解析错误详情
		var err_json: JSON = JSON.new()
		if err_json.parse(response_text) == OK and err_json.data is Dictionary:
			var err_data: Variant = err_json.data.get("error", err_json.data.get("message", ""))
			if err_data is Dictionary:
				error_msg += ": " + str(err_data.get("message", ""))
			elif err_data is String and not err_data.is_empty():
				error_msg += ": " + err_data
		_cleanup_request(request_id)
		generation_failed.emit(request_id, error_msg)
		return

	# 解析成功响应
	var json: JSON = JSON.new()
	if json.parse(response_text) != OK:
		_cleanup_request(request_id)
		generation_failed.emit(request_id, "Failed to parse JSON response")
		return

	var response: Dictionary = json.data
	print("[ArtAIService] Request %s completed successfully" % request_id)

	# 提取图片数据
	var images: Array = _extract_images(response)
	var result_data: Dictionary = {
		"images": images,
		"raw_response": response,
	}

	_cleanup_request(request_id)
	generation_completed.emit(request_id, result_data)


func _extract_images(response: Dictionary) -> Array:
	var images: Array = []
	var data: Array = response.get("data", [])
	for item in data:
		if item is Dictionary:
			var img: Dictionary = {}
			if item.has("url"):
				img["url"] = item["url"]
			if item.has("b64_json"):
				img["b64_json"] = item["b64_json"]
			if not img.is_empty():
				images.append(img)
	return images


func _get_http_error_message(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT: return "Cannot connect to server"
		HTTPRequest.RESULT_CANT_RESOLVE: return "Cannot resolve hostname"
		HTTPRequest.RESULT_CONNECTION_ERROR: return "Connection error"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: return "TLS handshake failed"
		HTTPRequest.RESULT_NO_RESPONSE: return "No response from server"
		HTTPRequest.RESULT_TIMEOUT: return "Request timeout"
		_: return "HTTP error: %d" % result


func _cleanup_request(request_id: String) -> void:
	if _active_requests.has(request_id):
		var http: HTTPRequest = _active_requests[request_id]
		if is_instance_valid(http):
			http.queue_free()
		_active_requests.erase(request_id)
#endregion


#region 保存辅助方法

## 将 b64 字符串解码并保存为 PNG 文件
## 返回 true 表示成功
static func save_b64_to_file(b64_data: String, save_path: String) -> bool:
	var bytes: PackedByteArray = Marshalls.base64_to_raw(b64_data)
	if bytes.is_empty():
		push_error("[ArtAIService] Failed to decode base64 data")
		return false
	return _save_bytes_to_file(bytes, save_path)


## 下载 URL 图片并保存到本地（异步，需要挂在场景树上）
## 返回保存路径，失败返回空字符串
func download_and_save(url: String, save_path: String) -> String:
	var http: HTTPRequest = HTTPRequest.new()
	http.timeout = timeout
	add_child(http)

	var state: Dictionary = {"done": false, "success": false, "data": PackedByteArray()}

	var on_done: Callable = func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			state["success"] = true
			state["data"] = body
		else:
			print("[ArtAIService] Download failed: result=%d code=%d" % [result, response_code])
		state["done"] = true

	http.request_completed.connect(on_done)

	var error: int = http.request(url)
	if error != OK:
		http.queue_free()
		return ""

	# 等待下载完成
	while not state["done"]:
		await get_tree().process_frame

	http.queue_free()

	if not state["success"]:
		return ""

	if _save_bytes_to_file(state["data"], save_path):
		return save_path
	return ""


## 将图片数据（来自 generation_completed 的 result）保存到本地
## 自动处理 url 和 b64_json 两种格式
## 返回保存的文件路径数组
func save_images(images: Array, save_dir: String, filename_prefix: String = "gen") -> Array:
	var saved_paths: Array = []
	_ensure_dir_exists(save_dir)

	var timestamp: String = str(Time.get_ticks_msec())
	for i in range(images.size()):
		var img: Dictionary = images[i]
		var filename: String = "%s_%s_%d.png" % [filename_prefix, timestamp, i]
		var save_path: String = save_dir.path_join(filename)

		if img.has("b64_json"):
			if save_b64_to_file(img["b64_json"], save_path):
				saved_paths.append(save_path)
				print("[ArtAIService] Saved b64 image to: %s" % save_path)
		elif img.has("url"):
			var result_path: String = await download_and_save(img["url"], save_path)
			if not result_path.is_empty():
				saved_paths.append(result_path)
				print("[ArtAIService] Downloaded and saved to: %s" % result_path)

	return saved_paths


## 确保目录存在
static func _ensure_dir_exists(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)


## 将字节数据写入文件
static func _save_bytes_to_file(bytes: PackedByteArray, save_path: String) -> bool:
	var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("[ArtAIService] Cannot open file for writing: %s" % save_path)
		return false
	file.store_buffer(bytes)
	file.close()
	return true
#endregion
