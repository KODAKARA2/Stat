class_name RecruitAction
extends GameAction
## 동료 영입: 같은 도시의 재야를 동료로 들인다. 친밀도·매력·명성이 높을수록 잘 된다. params = {"target": id}


func _init() -> void:
	id = "recruit"


func check(actor: String, params: Dictionary) -> String:
	var target: String = params.get("target", "")
	if not Career.is_free_agent(target):
		return "RECRUIT_FAIL_NOT_FREE"
	if Officers.get_state(target).get("city", "") != Officers.get_state(actor).get("city", ""):
		return "ACT_FAIL_NOT_HERE"
	if not Career.has_free_slot(actor):
		return "RECRUIT_FAIL_SLOTS"
	return ""


func run(actor: String, params: Dictionary) -> Dictionary:
	var target: String = params["target"]
	var chance: float = Career.recruit_chance(actor, target)
	Relationship.mark_met(actor, target)
	if RNG.chance(chance):
		Career.add_companion(actor, target)
		return {"target": target, "joined": true, "speech": VisitAction.speech_variant("TALK_RECRUIT_YES"),
			"lines": [msg("RECRUIT_JOINED", [Officers.display_name(target)])]}
	return {"target": target, "joined": false, "speech": VisitAction.speech_variant("TALK_RECRUIT_NO"),
		"lines": [msg("RECRUIT_REFUSED", [Officers.display_name(target), int(round(chance * 100))])]}
