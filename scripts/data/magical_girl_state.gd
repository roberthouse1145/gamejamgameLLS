class_name MagicalGirlState
extends RefCounted

const MagicalGirlDataScript := preload("res://scripts/data/magical_girl_data.gd")

enum Status {
	IDLE,
	DISPATCHED,
	TRAVELING,
	LIVESTREAMING,
	RESTING,
	INJURED,
}

var girl_data: MagicalGirlDataScript
var status: Status = Status.IDLE
var fatigue: float = 0.0
var mood: float = 100.0
var popularity: int = 0
var money: int = 0
var current_mission_id: String = ""
