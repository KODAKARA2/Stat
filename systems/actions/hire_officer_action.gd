class_name HireOfficerAction
extends GameAction
## 무명 무장 고용 (행동력 0): 금을 내면 누가 올지 모르는 범용 장수 한 명이 동료로 들어온다.


func _init() -> void:
	id = "hire_officer"


func check(actor: String, _params: Dictionary) -> String:
	if not Career.has_free_slot(actor):
		return "RECRUIT_FAIL_SLOTS"
	if int(Officers.get_state(actor).get("gold", 0)) < int(Career.cfg("hire_officer", "cost", 120)):
		return "ACT_FAIL_NO_GOLD"
	return ""


func run(actor: String, _params: Dictionary) -> Dictionary:
	var s: Dictionary = Officers.get_state(actor)
	var cost: int = int(Career.cfg("hire_officer", "cost", 120))
	s["gold"] = int(s["gold"]) - cost
	var new_id: String = OfficerGen.generate("", s["city"], "none")
	Career.add_companion(actor, new_id)
	return {"target": new_id, "speech": VisitAction.speech_variant("TALK_HIRED_OFFICER"),
		"lines": [msg("HIRE_OFFICER_DONE", [Officers.display_name(new_id), cost])]}
