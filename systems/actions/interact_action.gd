class_name InteractAction
extends VisitAction
## 교류: 술 한잔·선물 등으로 친밀도를 크게 올린다. 금을 쓴다. params = {"target": officer_id}


func _init() -> void:
	id = "interact"


func check(actor: String, params: Dictionary) -> String:
	if int(Officers.get_state(actor).get("gold", 0)) < int(cfg("gold", 30)):
		return "ACT_FAIL_NO_GOLD"
	return super.check(actor, params)


func run(actor: String, params: Dictionary) -> Dictionary:
	var s: Dictionary = Officers.get_state(actor)
	var cost: int = int(cfg("gold", 30))
	s["gold"] = int(s["gold"]) - cost
	var result: Dictionary = super.run(actor, params)
	result["speech"] = speech_variant("TALK_INTERACT")
	result["lines"].push_front(msg("ACT_GOLD_SPENT", [cost]))
	return result
