class_name OutingCatalog extends Resource

@export var places: Array[MapPlace] = []
@export var activities: Array[OutingActivity] = []


func get_place(place_id: String) -> MapPlace:
	var normalized_id: String = place_id.strip_edges()
	for place: MapPlace in places:
		if place != null and place.place_id == normalized_id:
			return place
	return null


func get_activity(activity_id: String) -> OutingActivity:
	var normalized_id: String = activity_id.strip_edges()
	for activity: OutingActivity in activities:
		if activity != null and activity.activity_id == normalized_id:
			return activity
	return null


func get_available_activities(day: int, time_slot: int) -> Array[OutingActivity]:
	var result: Array[OutingActivity] = []
	for activity: OutingActivity in activities:
		if activity != null and activity.is_valid() and activity.is_available(day, time_slot):
			result.append(activity)
	return result
