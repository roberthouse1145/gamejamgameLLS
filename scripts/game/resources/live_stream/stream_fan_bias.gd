class_name StreamFanBias extends Resource
## 一张内容卡对五类观众构成的偏移量。

@export var passerby: float = 0.0
@export var male: float = 0.0
@export var female: float = 0.0
@export var core: float = 0.0
@export var black: float = 0.0


func to_dict() -> Dictionary:
	return {
		"r": passerby,
		"m": male,
		"w": female,
		"c": core,
		"b": black,
	}
