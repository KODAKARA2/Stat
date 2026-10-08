class_name MoveAction
extends GameAction
## 이동: 인접 도시로 간다. params = {"to": city_id}


func _init() -> void:
	id = "move"


func check(actor: String, params: Dictionary) -> String:
	var here: String = Officers.get_state(actor).get("city", "")
	var to: String = params.get("to", "")
	if to == "" or to == here:
		return "ACT_FAIL_SAME_CITY"
	if not WorldMap.shared().is_adjacent(here, to):
		return "ACT_FAIL_NOT_ADJACENT"
	return ""


func run(actor: String, params: Dictionary) -> Dictionary:
	var s: Dictionary = Officers.get_state(actor)
	var to: String = params["to"]
	s["city"] = to
	Career.follow(actor)   # 동료도 같이 간다
	s["energy"] = maxi(0, int(s["energy"]) - int(cfg("energy", 5)))
	var city_name: String = TranslationServer.translate(DataDB.get_row("cities", to)["name_key"])
	return {"to": to, "lines": [msg("ACT_MOVE_DONE", [city_name])]}
