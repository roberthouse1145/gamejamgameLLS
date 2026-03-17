class_name AVGDevToolRegistry extends RefCounted
## AVG Dev AI — 工具注册入口
## 将所有 12 个工具注册到 AIService 实例
##
## 使用方法:
##   AVGDevToolRegistry.register_all(ai_service_node)

const DBTools = preload("res://scripts/avg/dev_tools/db_tools.gd")
const ScriptTools = preload("res://scripts/avg/dev_tools/script_tools.gd")
const ProjectTools = preload("res://scripts/avg/dev_tools/project_tools.gd")
const KBTools = preload("res://scripts/avg/dev_tools/kb_tools.gd")


## 注册所有 AVG Dev 工具到指定 AIService
static func register_all(ai_service: Node) -> void:
	DBTools.register_all(ai_service) # db_list/get/create/update/delete + get_story_outline (6)
	ScriptTools.register_all(ai_service) # get_scene_script / set_scene_script (2)
	ProjectTools.register_all(ai_service) # project_info / project_save / preview_scene / finish (4)
	KBTools.register_all(ai_service) # kb_read / kb_write (2)
	print("[AVGDevToolRegistry] 已注册 14 个工具")
