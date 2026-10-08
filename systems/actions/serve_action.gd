class_name ServeAction
extends GameAction
## 투신 (행동력 1): 지금 있는 도시의 나라에 봉신으로 들어간다. 거절당할 수도 있다.
## 봉신이 되어도 길드 의뢰는 계속 받을 수 있다(기획 확정). 용병단 계약은 끝난다.


func _init() -> void:
	id = "serve"


func check(actor: String, _params: Dictionary) -> String:
	return Career.serve_check(actor)


func run(actor: String, _params: Dictionary) -> Dictionary:
	var n: String = GameState.city_owner(Officers.get_state(actor)["city"])
	var chance: float = Career.serve_chance(actor, n)
	var ruler: String = Personnel.ruler_of(n)
	if RNG.chance(chance):
		Career.become_vassal(actor, n)
		EventRunner.clear_pending()   # 투신 행동 자체의 이벤트보다 서임식이 먼저
		EventRunner.trigger("rank_change", {"rank": "vassal_knight"})
		return {"accepted": true, "nation": n, "speaker": ruler, "speech": VisitAction.speech_variant("TALK_SERVE_YES"),
			"lines": [msg("SERVE_ACCEPTED", [Diplomacy.nation_name(n)])]}
	return {"accepted": false, "nation": n, "speaker": ruler, "speech": VisitAction.speech_variant("TALK_SERVE_NO"),
		"lines": [msg("SERVE_REFUSED", [Diplomacy.nation_name(n), int(round(chance * 100))])]}
