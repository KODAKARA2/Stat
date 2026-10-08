class_name ConquestAction
extends GameAction
## 용병단 점령전 (행동력 2): 용병대장이 용병단(동료·고용 부대)만으로 이웃 도시를 공성한다.
## 이기면 그 도시로 나라를 세운다(이름은 화면이 묻는다). 지면 그 나라 평판·명성 하락. params = {"target": city_id}


func _init() -> void:
	id = "conquest"


func ap_cost(_actor: String, _params: Dictionary) -> int:
	return int(Founding.cfg("conquest_ap", 2))


func check(actor: String, params: Dictionary) -> String:
	return Founding.conquest_check(actor, params.get("target", ""))


func run(actor: String, params: Dictionary) -> Dictionary:
	var target: String = params["target"]
	var quest: Dictionary = {
		"id": "conquest_%d" % TimeManager.month_index(), "type": "conquest", "side": "", "enemy": GameState.city_owner(target),
		"attack": true, "city": Officers.get_state(actor)["city"], "target": target, "tier": 3,
		"gold": 0, "fame": 20, "exp": 60, "deadline": TimeManager.month_index(),
	}
	return {"quest": quest, "battle": true, "lines": [msg("CONQUEST_START", [WorldMap.city_name(target)])]}
