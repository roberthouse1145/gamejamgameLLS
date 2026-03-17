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
