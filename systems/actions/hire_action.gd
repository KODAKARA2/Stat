class_name HireAction
extends GameAction
## 용병 고용 (행동력 0): 길드에서 금을 내고 부대를 계약한다. params = {"type": helper_types의 id}
## 고용한 부대는 계약 기간 동안 모든 전투에 같이 나간다.


func _init() -> void:
	id = "hire"


func check(actor: String, params: Dictionary) -> String:
	var type_id: String = params.get("type", "")
	if Guild.helper_type(type_id).is_empty():
		return "ACT_FAIL_UNKNOWN"
	if Guild.hired(actor).size() >= Guild.max_hired(actor):
		return "ACT_FAIL_HIRE_FULL"
	if int(Officers.get_state(actor).get("gold", 0)) < Guild.hire_cost(actor, type_id):
		return "ACT_FAIL_NO_GOLD"
	return ""


func run(actor: String, params: Dictionary) -> Dictionary:
	var s: Dictionary = Officers.get_state(actor)
	var type_id: String = params["type"]
	var cost: int = Guild.hire_cost(actor, type_id)
	s["gold"] = int(s["gold"]) - cost
	var entry: Dictionary = Guild.add_hired(actor, type_id)
	var name: String = Guild.hired_name(type_id, Guild.hired(actor).size())
	return {"hired": entry, "lines": [msg("ACT_HIRED", [name, cost, int(entry["months"])])]}
