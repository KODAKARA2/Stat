class_name SwearAction
extends GameAction
## 맹세 (행동력 1): 친밀도 90 이상인 사람과 의형제(맹우)를 맺는다. 맹우는 승계 후보가 된다 (GDD §5). params = {"target": id}


func _init() -> void:
	id = "swear"


func check(actor: String, params: Dictionary) -> String:
	var target: String = params.get("target", "")
	if Officers.get_state(target).get("city", "") != Officers.get_state(actor).get("city", ""):
		return "ACT_FAIL_NOT_HERE"
	return Family.can_swear(actor, target)


func run(actor: String, params: Dictionary) -> Dictionary:
	var target: String = params["target"]
	Relationship.add_tag(actor, target, "sworn")
	return {"sworn": true, "speech": VisitAction.speech_variant("TALK_SWEAR"), "lines": [msg("SWORN_DONE", [Officers.display_name(target)])]}
