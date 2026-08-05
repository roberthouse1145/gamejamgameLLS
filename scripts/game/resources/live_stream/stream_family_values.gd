class_name StreamFamilyValues extends Resource
## 素材对五个技能系别的适配倍率。

@export_range(0.0, 3.0, 0.05) var game: float = 1.0
@export_range(0.0, 3.0, 0.05) var talk: float = 1.0
@export_range(0.0, 3.0, 0.05) var song: float = 1.0
@export_range(0.0, 3.0, 0.05) var act: float = 1.0
@export_range(0.0, 3.0, 0.05) var tech: float = 1.0


func get_value(family: StringName) -> float:
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
	return 1.0
