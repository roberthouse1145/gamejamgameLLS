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
	for activity: OutingActivity in get_daily_activities(day):
		if activity.is_available(day, time_slot):
			result.append(activity)
	return result


func get_daily_activities(day: int) -> Array[OutingActivity]:
	var result: Array[OutingActivity] = []
	for place: MapPlace in places:
		if place == null or not place.is_valid():
			continue
		var candidates: Array[OutingActivity] = []
		for activity: OutingActivity in activities:
			if activity == null or not activity.is_valid():
				continue
			if activity.place_id == place.place_id and day >= activity.available_from_day and day <= activity.available_until_day:
				candidates.append(activity)
		if candidates.is_empty():
			continue
		var place_offset: int = absi(place.place_id.hash()) % candidates.size()
		var selected_index: int = (maxi(day, 1) - 1 + place_offset) % candidates.size()
		result.append(candidates[selected_index])
	return result
