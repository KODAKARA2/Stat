class_name LaunchWarAction
extends GameAction
## 출진 (성주, 행동력 2): 다스리는 도시에서 전쟁 중인 이웃 도시를 직접 친다(기획 확정).
## 이번 달 공격 계획을 만들고, 주인공이 지휘하는 공성전을 바로 시작한다. 결과는 월말 판정에 반영.
## params = {"target": city_id}


func _init() -> void:
	id = "launch_war"


func ap_cost(_actor: String, _params: Dictionary) -> int:
	return int(Career.cfg("govern", "launch_ap", 2))


func check(actor: String, params: Dictionary) -> String:
	var from: String = Career.governs(actor)
	if from == "":
		return "GOVERN_FAIL_NO_CITY"
	if Officers.get_state(actor).get("city", "") != from:
		return "GOVERN_FAIL_NOT_HERE"
	var to: String = params.get("target", "")
	var n: String = Officers.get_state(actor)["nation"]
	if not WorldMap.shared().is_adjacent(from, to) or not Diplomacy.at_war(n, GameState.city_owner(to)):
		return "LAUNCH_FAIL_TARGET"
	for p: Dictionary in WarSystem.plans():
		if p["to"] == to or p["from"] == from:
			return "LAUNCH_FAIL_BUSY"
	if int(GameState.cities[from]["troops"]) < 500:
		return "LAUNCH_FAIL_TROOPS"
	return ""


func run(actor: String, params: Dictionary) -> Dictionary:
	var from: String = Career.governs(actor)
	var to: String = params["target"]
	var n: String = Officers.get_state(actor)["nation"]
	var enemy: String = GameState.city_owner(to)
	var def_cmd: String = NationAI.pick_commander(enemy, to)
	if def_cmd != "" and Officers.get_state(def_cmd).get("city", "") != to:
		def_cmd = ""
	var plan: Dictionary = {
		"id": "p%d_%s" % [TimeManager.month_index(), from], "attacker": n, "defender": enemy, "from": from, "to": to,
		"sent": int(int(GameState.cities[from]["troops"]) * float(Career.cfg("govern", "launch_send_ratio", 0.7))),
		"mercs": 0, "merc_cost": 0, "commander": actor, "def_commander": def_cmd,
		"player_side": n, "player_result": "", "player_led": true,
	}
	WarSystem.plans().append(plan)
	var quest: Dictionary = {
		"id": plan["id"] + "_a", "type": "war", "plan": plan["id"], "side": n, "enemy": enemy, "attack": true,
		"city": from, "target": to, "tier": 2, "gold": 0, "fame": 5, "exp": 40, "deadline": TimeManager.month_index(), "order": true,
	}
	Officers.get_state(actor).get_or_add("quests", []).append(quest)
	return {"quest": quest, "battle": true, "lines": [msg("LAUNCH_DONE", [WorldMap.city_name(to)])]}
