class_name NegotiateAction
extends GameAction
## 설전 시작 (행동력 1). 결과는 설전 창에서 3택을 고른 뒤 Negotiation.apply로 반영한다.
## params = {"kind": "recruit"/"contract"/"truce", "target": 재야 id, "quest": 계약 id, "nation": 상대 나라}


func _init() -> void:
	id = "negotiate"


func check(actor: String, params: Dictionary) -> String:
	var s: Dictionary = Officers.get_state(actor)
	var month: int = TimeManager.month_index()
	match params.get("kind", ""):
		"recruit":
			var target: String = params.get("target", "")
			var reason: String = Actions.get_action("recruit").check(actor, {"target": target})
			if reason != "":
				return reason
			if int(Officers.get_state(target).get("persuaded_month", -1)) == month:
				return "NEGO_FAIL_TRIED"
		"contract":
			var reason: String = Actions.get_action("accept_quest").check(actor, {"quest": params.get("quest", "")})
			if reason != "":
				return reason
			var q: Dictionary = Guild.find(Guild.city_quests(s.get("city", "")), params.get("quest", ""))
			if q.get("type", "") != "contract":
				return "ACT_FAIL_NO_QUEST"
			if q.get("negotiated", false):
				return "NEGO_FAIL_TRIED"
			if Personnel.ruler_of(q["employer"]) == "":
				return "NEGO_FAIL_NOBODY"
		"truce":
			var n: String = params.get("nation", "")
			if Officers.track(actor) != "ruler":
				return "NEGO_FAIL_NOT_RULER"
			if not Diplomacy.at_war(s.get("nation", ""), n):
				return "NEGO_FAIL_NOT_AT_WAR"
			if Personnel.ruler_of(n) == "":
				return "NEGO_FAIL_NOBODY"
			if int(s.get("truce_tried", {}).get(n, -1)) == month:
				return "NEGO_FAIL_TRIED"
		_:
			return "ACT_FAIL_NO_QUEST"
	return ""


func run(actor: String, params: Dictionary) -> Dictionary:
	var kind: String = params["kind"]
	var p: Dictionary = params.duplicate()
	var month: int = TimeManager.month_index()
	match kind:
		"recruit":
			Officers.get_state(params["target"])["persuaded_month"] = month
		"contract":
			var q: Dictionary = Guild.find(Guild.city_quests(Officers.get_state(actor)["city"]), params["quest"])
			p["nation"] = q["employer"]
			q["negotiated"] = true   # 한 번뿐 (끝나기 전에 창을 닫아도)
		"truce":
			Officers.get_state(actor).get_or_add("truce_tried", {})[params["nation"]] = month
	var n: Dictionary = Negotiation.start(kind, actor, p)
	return {"negotiation": n, "lines": []}
