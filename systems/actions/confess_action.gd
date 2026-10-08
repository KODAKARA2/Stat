class_name ConfessAction
extends GameAction
## 고백 (행동력 1): 친밀도가 높은 미혼 성인에게. 받아들이면 연인이 된다 (GDD §5.1 "연인 상태 이벤트 경유"). params = {"target": id}


func _init() -> void:
	id = "confess"


func check(actor: String, params: Dictionary) -> String:
	var target: String = params.get("target", "")
	if Officers.get_state(target).get("city", "") != Officers.get_state(actor).get("city", ""):
		return "ACT_FAIL_NOT_HERE"
	return Family.can_confess(actor, target)


func run(actor: String, params: Dictionary) -> Dictionary:
	var target: String = params["target"]
	var chance: float = Relationship.affinity(actor, target) * float(Family.cfg("romance", "confess_per_affinity", 0.01))
	if RNG.chance(chance):
		Relationship.add_tag(actor, target, "lover")
		return {"accepted": true, "speech": VisitAction.speech_variant("TALK_CONFESS_YES"), "lines": [msg("ROMANCE_LOVERS", [Officers.display_name(target)])]}
	Relationship.add(actor, target, int(Family.cfg("romance", "confess_fail_affinity", -5)))
	return {"accepted": false, "speech": VisitAction.speech_variant("TALK_CONFESS_NO"), "lines": [msg("ROMANCE_REJECTED", [Officers.display_name(target)])]}
