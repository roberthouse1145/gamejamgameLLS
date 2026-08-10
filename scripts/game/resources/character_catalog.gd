class_name CharacterCatalog extends Resource
## 本体唯一角色目录。应用和管理器通过稳定角色 ID 获取资料。

@export var player_character_id: String = ""
@export var characters: Array[CharacterProfile] = []


func get_character(character_id: String) -> CharacterProfile:
	var normalized_id: String = character_id.strip_edges()
	for character: CharacterProfile in characters:
		if character != null and character.character_id == normalized_id:
			return character
	return null


func get_player_character() -> CharacterProfile:
	return get_character(player_character_id)


func get_linkchat_characters() -> Array[CharacterProfile]:
	var result: Array[CharacterProfile] = []
	for character: CharacterProfile in characters:
		if character != null and character.linkchat_profile != null:
			result.append(character)
	return result


func get_social_account(account_id: String) -> SocialAccountProfile:
	for character: CharacterProfile in characters:
		if character == null:
			continue
		var account: SocialAccountProfile = character.get_social_account(account_id)
		if account != null:
			return account
	return null


func get_character_for_social_account(account_id: String) -> CharacterProfile:
	for character: CharacterProfile in characters:
		if character != null and character.get_social_account(account_id) != null:
			return character
	return null
