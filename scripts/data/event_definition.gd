class_name EventDefinition
extends Resource


enum EventType {
	COMBAT,
	RESCUE,
	PERFORMANCE,
	DAILY_HELP,
	PATROL,
}

enum FailureSeverity {
	SEVERE,
	MODERATE,
	MILD,
}

enum MediaExposure {
	HIGH,
	MEDIUM,
	LOW,
}


@export var event_id: String = ""
@export var event_name: String = ""
@export var event_type: EventType = EventType.COMBAT
@export var difficulty: String = "D"
@export var zone_id: String = ""
@export var required_slots: int = 1
@export var time_limit_minutes: float = 30.0
@export_multiline var description: String = ""
@export_multiline var prompt: String = ""
@export var failure_severity: FailureSeverity = FailureSeverity.MODERATE
@export var media_exposure: MediaExposure = MediaExposure.MEDIUM
@export var rewards: Dictionary = {"money": 0, "popularity": 0}
