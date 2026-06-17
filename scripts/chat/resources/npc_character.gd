class_name NPCCharacter extends Resource
## NPC角色资源
## 存储NPC的基础信息和人设Prompt

## 角色唯一标识
@export var character_id: String = ""

## 显示名称
@export var display_name: String = ""

## 头像
@export var avatar: Texture2D

## 完整的人设 Prompt 文本（无需再单独建文件，系统角色或群演直接写在这里）
@export_multiline var prompt: String = ""

## 初始好感度
@export_range(0, 100) var initial_affection: int = 50

## 项目上下文访问范围
## none: 普通聊天对象，不知道项目知识库/工单/开发进度
## personal: 仅可见 tags 含自己 character_id 的文档（待实现的过滤行为，hook 留位）
## world: 仅可见 world / story 类目下文档（待实现的过滤行为，hook 留位）
## collaborator: 协作搭档，可引用全部项目共享上下文
@export_enum("none", "personal", "world", "collaborator") var project_context_scope: String = "none"


func can_access_project_context() -> bool:
	# 当前阶段只有 collaborator 实际启用注入；personal/world 的过滤逻辑后续再实现
	return project_context_scope == "collaborator"
