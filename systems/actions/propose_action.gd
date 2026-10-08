class_name ProposeAction
extends GameAction
## 청혼 (행동력 1, 혼례 비용): 연인 + 친밀도 80 이상이면 결혼 (GDD §5.1). 종족은 상관없다. params = {"target": id}


func _init() -> void:
	id = "propose"


func check(actor: String, params: Dictionary) -> String:
	var target: String = params.get("target", "")
	if Officers.get_state(target).get("city", "") != Officers.get_state(actor).get("city", ""):
		return "ACT_FAIL_NOT_HERE"
	if int(Officers.get_state(actor).get("gold", 0)) < int(Family.cfg("romance", "propose_cost", 100)):
		return "ACT_FAIL_NO_GOLD"
	return Family.can_propose(actor, target)


func run(actor: String, params: Dictionary) -> Dictionary:
	var target: String = params["target"]
	var s: Dictionary = Officers.get_state(actor)
	s["gold"] = int(s["gold"]) - int(Family.cfg("romance", "propose_cost", 100))
	Family.marry(actor, target)
	return {"married": true, "speech": VisitAction.speech_variant("TALK_PROPOSE_YES"), "lines": [msg("ROMANCE_MARRIED", [Officers.display_name(target)])]}
