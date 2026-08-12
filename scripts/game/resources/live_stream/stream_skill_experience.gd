class_name StreamSkillExperience extends Resource
## 一场素材完成后授予中之人的五领域熟练度 EXP。

@export_range(0, 1000, 1) var game: int = 0
@export_range(0, 1000, 1) var talk: int = 0
@export_range(0, 1000, 1) var song: int = 0
@export_range(0, 1000, 1) var act: int = 0
@export_range(0, 1000, 1) var tech: int = 0


func get_value(family: StringName) -> int:
	match family:
		&"game":
			return game
		&"talk":
			return talk
		&"song":
			return song
		&"act":
			return act
		&"tech":
			return tech
	return 0


func get_total() -> int:
	return game + talk + song + act + tech


func to_dict() -> Dictionary:
	return {
		"game": game,
		"talk": talk,
		"song": song,
		"act": act,
		"tech": tech,
	}
