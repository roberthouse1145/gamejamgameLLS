class_name NPCManager extends RefCounted
## NPC管理器
## 管理所有NPC角色资源的加载和访问

## NPC注册表：character_id -> NPCCharacter
var _npcs: Dictionary = {}


## 注册一个NPC
func register_npc(npc: NPCCharacter) -> void:
	if npc == null or npc.character_id.is_empty():
		push_warning("NPCManager: Cannot register invalid NPC")
		return
	_npcs[npc.character_id] = npc


## 获取NPC
func get_npc(character_id: String) -> NPCCharacter:
	return _npcs.get(character_id)


## 通过 display_name 查找NPC（用于将AI输出的显示名映射回 character_id）
func find_npc_by_display_name(display_name: String) -> NPCCharacter:
	for npc: NPCCharacter in _npcs.values():
		if npc.display_name == display_name:
			return npc
	return null


## 获取所有NPC
func get_all_npcs() -> Array[NPCCharacter]:
	var result: Array[NPCCharacter] = []
	for npc in _npcs.values():
		if npc is NPCCharacter:
			result.append(npc)
	return result


## 获取所有NPC ID
func get_all_npc_ids() -> Array[String]:
	var result: Array[String] = []
	for key in _npcs.keys():
		result.append(str(key))
	return result
