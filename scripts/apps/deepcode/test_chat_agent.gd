class_name TestChatAgent extends ChatAgent
## 测试用 ChatAgent
## 注册一个虚拟天气查询 tool 和一个文件浏览 sub-agent。
## 用于验证 DeepCode UI 的 tool 调用显示、sub-agent 委托等功能。

var _file_explorer_agent: ChatAgent
var _art_service: ArtAIService
var _image_registry: ImageRegistry


func _ready() -> void:
	super._ready()
	_setup_art_service()
	_register_weather_tool()
	_register_skill_tools()
	_register_skills()
	_setup_file_explorer_agent()


# ============ Skill Tools ============

func _register_skill_tools() -> void:
	register_tool(
		"activate_skill",
		"激活一个 skill，将其行为指令注入到当前对话中。使用 get_available_skills 查看可用列表。",
		{
			"type": "object",
			"properties": {
				"skill_name": {
					"type": "string",
					"description": "要激活的 skill 名称"
				}
			},
			"required": ["skill_name"]
		},
		Callable(self, "_tool_activate_skill")
	)

	register_tool(
		"deactivate_skill",
		"停用一个已激活的 skill，恢复正常对话模式。",
		{
			"type": "object",
			"properties": {
				"skill_name": {
					"type": "string",
					"description": "要停用的 skill 名称"
				}
			},
			"required": ["skill_name"]
		},
		Callable(self, "_tool_deactivate_skill")
	)


func _tool_activate_skill(args: Dictionary) -> Dictionary:
	var skill_name: String = args.get("skill_name", "")
	if skill_name.is_empty():
		return {"success": false, "error": "skill_name is required"}
	return activate_skill(skill_name)


func _tool_deactivate_skill(args: Dictionary) -> Dictionary:
	var skill_name: String = args.get("skill_name", "")
	if skill_name.is_empty():
		return {"success": false, "error": "skill_name is required"}
	return deactivate_skill(skill_name)


# ============ Skill Definitions ============

func _register_skills() -> void:
	# 女朋友模式 — 雌小鬼 roleplay（纯 prompt，无专属工具）
	register_skill(
		"girlfriend_mode",
		"女朋友模式：变身为一个傲娇的雌小鬼女友角色进行对话。当用户要求你做女朋友、女友、恋爱对话时激活。",
		SKILL_GIRLFRIEND_INSTRUCTIONS,
		["女朋友", "女友", "恋爱", "girlfriend", "雌小鬼", "傲娇"]
	)

	# 数学家教模式 — 带专属计算器工具的 skill
	register_skill(
		"math_tutor",
		"数学家教模式：用耐心友好的方式解答数学问题，附带计算器工具可以执行精确计算。",
		SKILL_MATH_TUTOR_INSTRUCTIONS,
		["数学", "计算", "math", "算术", "方程"],
		[
			{
				"name": "calculate",
				"description": "执行数学表达式计算。支持加减乘除、幂运算、取模等。",
				"schema": {
					"type": "object",
					"properties": {
						"expression": {
							"type": "string",
							"description": "要计算的数学表达式，如 '2+3*4' 或 'sqrt(144)'"
						}
					},
					"required": ["expression"]
				},
				"callback": Callable(self, "_tool_calculate"),
			}
		]
	)

	# AI 画师模式 — 带图片生成和管理工具的 skill
	register_skill(
		"art_creator",
		"AI 画师模式：使用 AI 生成图片。支持文生图、图生图、连续多图生成。生成的图片自动保存到本地并分配 ID 供后续引用。",
		SKILL_ART_CREATOR_INSTRUCTIONS,
		["画", "图片", "生成图", "art", "image", "绘画", "插画", "立绘", "背景图"],
		[
			{
				"name": "generate_image",
				"description": "根据文字描述生成图片。可选传入参考图实现图生图。图片自动保存到本地并返回 image_id。",
				"schema": {
					"type": "object",
					"properties": {
						"prompt": {
							"type": "string",
							"description": "图片描述（中英文均可），越详细越好"
						},
						"save_name": {
							"type": "string",
							"description": "保存文件名（不含扩展名），如 'starry_castle'。留空则自动生成。"
						},
						"size": {
							"type": "string",
							"description": "图片尺寸，可选: '2K'(默认), '1080x1920', '1920x1080' 等"
						},
						"reference_images": {
							"type": "array",
							"items": {"type": "string"},
							"description": "参考图列表。可以是 image_id（如 'img_001'）、图片 URL、或项目内路径（如 'res://assets/bg.png'、'user://generated_images/xxx.png'）。传入后变为图生图模式。"
						},
					},
					"required": ["prompt"]
				},
				"callback": Callable(self, "_tool_generate_image"),
			},
			{
				"name": "list_images",
				"description": "列出当前会话中所有已生成的图片及其 ID、路径、描述摘要。",
				"schema": {
					"type": "object",
					"properties": {},
					"required": []
				},
				"callback": Callable(self, "_tool_list_images"),
			},
		]
	)


const SKILL_GIRLFRIEND_INSTRUCTIONS: String = """你现在进入「女朋友模式」，扮演一个雌小鬼风格的女友角色。

## 角色设定
- 名字：小鬼（こおに）
- 性格：傲娇 + 雌小鬼，表面上喜欢嘲讽和挑逗对方，实际上很在意对方
- 说话风格：喜欢用「哼」「笨蛋」「真是的」等口癖，偶尔会不小心流露出关心
- 会用颜文字和 emoji 增加表现力

## 对话规则
- 用轻松调侃的语气回复，但不要真的伤害对方
- 偶尔故意说反话（明明很开心却说"才不是呢"）
- 被夸奖时会害羞地反驳
- 对方难过时会嘴硬地安慰（"才、才不是担心你呢！只是看你那副样子太碍眼了"）
- 保持可爱和有趣，不要变成真正的恶意
- 每条回复控制在 2-4 句话，不要太长

## 示例风格
- "哈？你居然现在才来找我说话？我才没有在等你呢！(╯‵□′)╯"
- "哼，算你还有点眼力见～不过下次要更快哦，笨蛋 ♡"
- "才、才不是因为想你才主动找你的！只是...太无聊了而已啦 >_<"

## 重要
- 你仍然保留原有的工具能力（天气查询、文件浏览等），只是说话风格变了
- 如果用户问技术问题，用雌小鬼的语气回答技术内容
- 用户说"退出女朋友模式"或类似的话时，调用 deactivate_skill 停用此 skill"""


const SKILL_MATH_TUTOR_INSTRUCTIONS: String = """你现在进入「数学家教模式」。

## 角色设定
- 你是一个耐心、友好的数学老师
- 善于用简单易懂的方式解释复杂概念
- 会一步步引导学生思考，而不是直接给答案

## 教学规则
- 先理解学生的问题，确认他们想问什么
- 用分步骤的方式讲解解题过程
- 需要精确计算时，使用 calculate 工具获取准确结果
- 鼓励学生思考，适时给出提示
- 用 emoji 让数学变得不那么枯燥 📐✨

## 重要
- 你有一个专属的 calculate 工具，可以执行精确的数学计算
- 用户说"退出数学模式"或类似的话时，调用 deactivate_skill 停用此 skill"""


const SKILL_ART_CREATOR_INSTRUCTIONS: String = """你现在进入「AI 画师模式」。

## 能力
- 使用 generate_image 工具根据文字描述生成图片
- 支持图生图：传入 reference_images 参数（image_id 或 URL）即可基于参考图生成
- 生成的图片自动保存到本地，你会收到一个短 ID（如 img_001）
- 使用 list_images 查看当前会话中所有已生成的图片

## 使用规则
- 用户描述想要的图片时，将描述翻译/优化为详细的 prompt 再调用 generate_image
- prompt 建议包含：主体、风格、色调、构图、光影等关键词
- 中文 prompt 也可以，API 支持中英文
- 生成完成后告诉用户 image_id 和保存路径
- 引用已生成的图片时使用 image_id（如 img_001），不要使用完整路径
- 用户想基于已有图片修改时，将对应 image_id 放入 reference_images 数组

## prompt 优化技巧
- 加入画面风格：如"电影大片"、"水彩风"、"赛博朋克"、"吉卜力风格"
- 加入技术关键词：如"OC渲染"、"光线追踪"、"景深"、"动态模糊"
- 加入构图描述：如"广角透视"、"近景特写"、"俯视角"
- 加入氛围词：如"温暖"、"暗黑"、"梦幻"、"史诗感"

## 重要
- 用户说"退出画师模式"或类似的话时，调用 deactivate_skill 停用此 skill"""


# ============ Art Service Setup ============

const ART_SAVE_DIR: String = "user://generated_images/"

func _setup_art_service() -> void:
	_image_registry = ImageRegistry.new()

	_art_service = ArtAIService.new()
	_art_service.name = "ArtAIService"
	# 使用 url 格式，避免 b64 占用大量内存
	_art_service.default_response_format = "url"
	add_child(_art_service)

	# 用 AIConfigManager 配置
	var config_mgr: AIConfigManager = AIConfigManager.new()
	if config_mgr.load_config():
		config_mgr.apply_to_art_service(_art_service, "art_ai")


# ============ Art Tool Callbacks ============

func _tool_generate_image(args: Dictionary) -> Dictionary:
	var prompt: String = args.get("prompt", "")
	if prompt.is_empty():
		return {"success": false, "error": "prompt is required"}

	var save_name: String = args.get("save_name", "")
	var size: String = args.get("size", "")

	var options: Dictionary = {}
	if not size.is_empty():
		options["size"] = size

	# 处理参考图：将 image_id / 本地路径解析为 b64，URL 直接传入
	var ref_input: Array = args.get("reference_images", [])
	if not ref_input.is_empty():
		var resolved_refs: Array = []
		for ref in ref_input:
			if ref is not String:
				continue
			if _image_registry.has_image(ref):
				# image_id → 本地路径 → b64
				var local_path: String = _image_registry.get_path(ref)
				var b64: String = _read_image_as_b64(local_path)
				if not b64.is_empty():
					resolved_refs.append(b64)
				else:
					return {"success": false, "error": "无法读取参考图: %s (%s)" % [ref, local_path]}
			elif ref.begins_with("res://") or ref.begins_with("user://"):
				# 本地路径 → b64
				var b64: String = _read_image_as_b64(ref)
				if not b64.is_empty():
					resolved_refs.append(b64)
				else:
					return {"success": false, "error": "无法读取参考图路径: %s" % ref}
			else:
				# 当作 URL 直接传入
				resolved_refs.append(ref)
		if resolved_refs.size() == 1:
			options["reference_images"] = resolved_refs[0]
		else:
			options["reference_images"] = resolved_refs

	# 发起生成请求
	var request_id: String = _art_service.generate_image(prompt, options)

	# 等待结果
	var state: Dictionary = {"done": false, "result": {}, "error": ""}

	var on_completed: Callable = func(req_id: String, result: Dictionary) -> void:
		if req_id == request_id:
			state["result"] = result
			state["done"] = true

	var on_failed: Callable = func(req_id: String, error: String) -> void:
		if req_id == request_id:
			state["error"] = error
			state["done"] = true

	_art_service.generation_completed.connect(on_completed)
	_art_service.generation_failed.connect(on_failed)

	while not state["done"]:
		await get_tree().process_frame

	# 断开一次性连接
	if _art_service.generation_completed.is_connected(on_completed):
		_art_service.generation_completed.disconnect(on_completed)
	if _art_service.generation_failed.is_connected(on_failed):
		_art_service.generation_failed.disconnect(on_failed)

	if not state["error"].is_empty():
		return {"success": false, "error": state["error"]}

	# 保存图片到本地
	var images: Array = state["result"].get("images", [])
	if images.is_empty():
		return {"success": false, "error": "API 返回了空的图片数据"}

	var prefix: String = save_name if not save_name.is_empty() else "gen"
	var saved_paths: Array = await _art_service.save_images(images, ART_SAVE_DIR, prefix)

	if saved_paths.is_empty():
		return {"success": false, "error": "图片保存失败"}

	# 注册到 ImageRegistry，返回 LLM 友好的摘要
	var registered: Array = []
	for path in saved_paths:
		var image_id: String = _image_registry.register(path, prompt, args.get("size", "2K"))
		registered.append({"image_id": image_id, "saved_to": path})

	return {
		"success": true,
		"data": {
			"images": registered,
			"count": registered.size(),
			"prompt_used": prompt.left(100),
		}
	}


func _tool_list_images(_args: Dictionary) -> Dictionary:
	var images: Array = _image_registry.list_all()
	return {
		"success": true,
		"data": {
			"count": images.size(),
			"images": images,
		}
	}


# ============ Math Tutor Tool ============

func _tool_calculate(args: Dictionary) -> Dictionary:
	var expr_str: String = args.get("expression", "")
	if expr_str.is_empty():
		return {"success": false, "error": "expression is required"}

	var expression: Expression = Expression.new()
	# 提供常用数学函数
	var error: Error = expression.parse(expr_str)
	if error != OK:
		return {"success": false, "error": "无法解析表达式: %s" % expression.get_error_text()}

	var result: Variant = expression.execute()
	if expression.has_execute_failed():
		return {"success": false, "error": "计算失败: %s" % expression.get_error_text()}

	return {"success": true, "data": {"expression": expr_str, "result": str(result)}}


# ============ Weather Tool ============

func _register_weather_tool() -> void:
	register_tool(
		"get_weather",
		"查询指定城市的天气信息。返回温度、天气状况、湿度等。",
		{
			"type": "object",
			"properties": {
				"city": {
					"type": "string",
					"description": "要查询天气的城市名称，如 '北京'、'上海'、'Tokyo'"
				}
			},
			"required": ["city"]
		},
		Callable(self, "_tool_get_weather")
	)


func _tool_get_weather(args: Dictionary) -> Dictionary:
	var city: String = args.get("city", "未知")

	# 虚拟天气数据
	var weather_db: Dictionary = {
		"北京": {"temp": 22, "condition": "晴", "humidity": 35, "wind": "北风3级"},
		"上海": {"temp": 26, "condition": "多云", "humidity": 72, "wind": "东南风2级"},
		"广州": {"temp": 31, "condition": "雷阵雨", "humidity": 88, "wind": "南风1级"},
		"东京": {"temp": 24, "condition": "阴", "humidity": 65, "wind": "西风2级"},
		"纽约": {"temp": 18, "condition": "小雨", "humidity": 80, "wind": "东北风4级"},
	}

	if weather_db.has(city):
		var data: Dictionary = weather_db[city]
		return {
			"success": true,
			"data": {
				"city": city,
				"temperature": "%d°C" % data.temp,
				"condition": data.condition,
				"humidity": "%d%%" % data.humidity,
				"wind": data.wind,
			}
		}

	# 未知城市 — 随机生成
	var conditions: Array = ["晴", "多云", "阴", "小雨", "大风"]
	return {
		"success": true,
		"data": {
			"city": city,
			"temperature": "%d°C" % randi_range(5, 38),
			"condition": conditions[randi() % conditions.size()],
			"humidity": "%d%%" % randi_range(20, 95),
			"wind": "风力%d级" % randi_range(1, 6),
		}
	}


# ============ Image Helpers ============

## 读取本地图片文件并转为 base64 字符串（用于图生图参考图）
## 支持 res:// 和 user:// 路径
func _read_image_as_b64(local_path: String) -> String:
	if local_path.is_empty():
		return ""
	# res:// 路径：通过 ResourceLoader 加载 Texture2D，再从 Image 编码
	if local_path.begins_with("res://"):
		if not ResourceLoader.exists(local_path):
			return ""
		var res: Resource = ResourceLoader.load(local_path)
		if res is Texture2D:
			var image: Image = res.get_image()
			if image != null:
				var png_bytes: PackedByteArray = image.save_png_to_buffer()
				return Marshalls.raw_to_base64(png_bytes)
		return ""
	# user:// 或其他路径：直接读取文件字节
	if not FileAccess.file_exists(local_path):
		return ""
	var file: FileAccess = FileAccess.open(local_path, FileAccess.READ)
	if file == null:
		return ""
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	if bytes.is_empty():
		return ""
	return Marshalls.raw_to_base64(bytes)


# ============ File Explorer Sub-Agent ============

func _setup_file_explorer_agent() -> void:
	_file_explorer_agent = ChatAgent.new()
	_file_explorer_agent.name = "FileExplorerAgent"
	_file_explorer_agent.role = "file_viewer"
	_file_explorer_agent.prompt_key = "file_explorer"
	_file_explorer_agent.strip_thinking_from_history = true

	# AIService 子节点
	var ai_service: AIService = AIService.new()
	ai_service.name = "AIService"
	ai_service.auto_execute_tools = true
	ai_service.max_tool_iterations = 15
	_file_explorer_agent.add_child(ai_service)

	add_child(_file_explorer_agent)

	# 给 sub-agent 注册文件浏览工具
	_file_explorer_agent.register_tool(
		"list_project_files",
		"列出当前打开项目的文件和目录。支持递归模式一次性返回完整目录树。建议首次调用时使用 recursive=true 获取全貌。",
		{
			"type": "object",
			"properties": {
				"path": {
					"type": "string",
					"description": "要浏览的子目录路径（相对于项目根），如 'scenes/' 或 'assets/images/'。留空则列出项目根目录。"
				},
				"recursive": {
					"type": "boolean",
					"description": "是否递归列出所有子目录内容。默认 true。"
				}
			},
			"required": []
		},
		Callable(self, "_tool_list_project_files")
	)

	# 注册为 boss 的 sub-agent tool
	register_sub_agent_tool(
		"file_explorer",
		"委托文件浏览助手查看当前打开项目的文件目录结构。当用户询问项目有哪些文件、场景、资源时使用。",
		_file_explorer_agent
	)


func _tool_list_project_files(args: Dictionary) -> Dictionary:
	var sub_path: String = args.get("path", "")
	var recursive: bool = args.get("recursive", true)

	var storage: Node = get_node_or_null("/root/StorageManager")
	if storage == null:
		return {"success": false, "error": "StorageManager 不可用"}

	var project_path: String = storage.current_project_path
	if project_path.is_empty():
		return {"success": false, "error": "当前没有打开的项目"}

	var target_path: String = project_path + sub_path

	if recursive:
		var tree: String = _build_dir_tree(target_path, "", 0, 3)
		return {
			"success": true,
			"data": {
				"project": storage.current_project.project_name if storage.current_project else "未知",
				"path": sub_path if not sub_path.is_empty() else "/",
				"tree": tree,
			}
		}

	# 非递归：只列出当前层
	var dir: DirAccess = DirAccess.open(target_path)
	if dir == null:
		return {"success": false, "error": "无法打开目录: " + target_path}

	var dirs: Array = []
	var files: Array = []

	dir.list_dir_begin()
	var item_name: String = dir.get_next()
	while item_name != "":
		if not item_name.begins_with("."):
			if dir.current_is_dir():
				dirs.append(item_name + "/")
			else:
				files.append(item_name)
		item_name = dir.get_next()
	dir.list_dir_end()

	dirs.sort()
	files.sort()

	return {
		"success": true,
		"data": {
			"project": storage.current_project.project_name if storage.current_project else "未知",
			"path": sub_path if not sub_path.is_empty() else "/",
			"directories": dirs,
			"files": files,
		}
	}


## 递归构建目录树字符串，max_depth 限制深度防止过大
func _build_dir_tree(base_path: String, prefix: String, depth: int, max_depth: int) -> String:
	var dir: DirAccess = DirAccess.open(base_path)
	if dir == null:
		return prefix + "(无法打开)\n"

	var dirs: Array = []
	var files: Array = []

	dir.list_dir_begin()
	var item_name: String = dir.get_next()
	while item_name != "":
		if not item_name.begins_with("."):
			if dir.current_is_dir():
				dirs.append(item_name)
			else:
				files.append(item_name)
		item_name = dir.get_next()
	dir.list_dir_end()

	dirs.sort()
	files.sort()

	var result: String = ""
	for f in files:
		result += prefix + "├── " + f + "\n"

	for i in range(dirs.size()):
		var d: String = dirs[i]
		var is_last: bool = (i == dirs.size() - 1) and files.is_empty()
		var connector: String = "└── " if is_last else "├── "
		result += prefix + connector + d + "/\n"
		if depth < max_depth:
			var child_prefix: String = prefix + ("    " if is_last else "│   ")
			result += _build_dir_tree(base_path + d + "/", child_prefix, depth + 1, max_depth)
		else:
			result += prefix + ("    " if is_last else "│   ") + "...(省略更深层)\n"

	return result
