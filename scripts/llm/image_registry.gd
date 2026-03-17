class_name ImageRegistry extends RefCounted
## 图片注册表 — 管理 AI 生成的图片 ID 映射
## 纯数据类，不需要 .tscn。
##
## LLM 只看到短 ID（如 "img_001"），实际文件路径和元数据存在这里。
## 避免 URL/b64 等大量无意义文本占据 token。

#region 内部数据
## image_id -> {local_path: String, prompt: String, size: String, created_at: float, metadata: Dictionary}
var _images: Dictionary = {}
var _counter: int = 0
#endregion


#region 公共 API

## 注册一张图片，返回分配的 image_id
func register(local_path: String, prompt: String = "", size: String = "", metadata: Dictionary = {}) -> String:
	_counter += 1
	var image_id: String = "img_%03d" % _counter
	_images[image_id] = {
		"local_path": local_path,
		"prompt": prompt,
		"size": size,
		"created_at": Time.get_unix_time_from_system(),
		"metadata": metadata,
	}
	print("[ImageRegistry] Registered %s -> %s" % [image_id, local_path])
	return image_id


## 通过 ID 获取图片信息
func get_image(image_id: String) -> Dictionary:
	return _images.get(image_id, {})


## 获取图片本地路径
func get_path(image_id: String) -> String:
	var info: Dictionary = _images.get(image_id, {})
	return info.get("local_path", "")


## 检查 ID 是否存在
func has_image(image_id: String) -> bool:
	return _images.has(image_id)


## 列出所有图片（返回 LLM 友好的摘要数组）
func list_all() -> Array:
	var result: Array = []
	for image_id in _images:
		var info: Dictionary = _images[image_id]
		result.append({
			"image_id": image_id,
			"local_path": info.get("local_path", ""),
			"prompt": info.get("prompt", "").left(80),
			"size": info.get("size", ""),
		})
	return result


## 移除一张图片记录（不删除文件）
func unregister(image_id: String) -> bool:
	return _images.erase(image_id)


## 清空所有记录
func clear() -> void:
	_images.clear()
	_counter = 0


## 当前图片数量
func count() -> int:
	return _images.size()
#endregion
