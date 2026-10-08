class_name Negotiation
extends RefCounted
## 설전 (기획 확정 2026-10-08): 논리/감정/위세 3택으로 상대를 설득하는 짧은 말싸움.
##  논리 = 지력, 감정 = 매력, 위세 = 명성·신분. 상대 성격(탐욕→논리, 의리→감정, 야망→위세)에 따라
##  매 라운드 한 가지에 귀가 열리고(×1.5) 한 가지는 질색한다(×0.3). 지력이 높을수록 눈치(힌트)가 정확하다.
## 쓰임: 재야 설득(영입), 용병단 계약 보수 교섭, 군주의 휴전 교섭.
## 상태 = {"kind", "actor", "target", "nation", "quest", "gauge", "goal", "round", "rounds", "posture": {접근: 배율}, "hint", "log"}

const APPROACHES: Array = ["logic", "emotion", "prestige"]
const TRAIT_OF: Dictionary = {"logic": "greed", "emotion": "loyalty", "prestige": "ambition"}


static func cfg(key: String, default_value: Variant = null) -> Variant:
	return DataDB.get_table("career").get("negotiation", {}).get(key, default_value)


## 설전 상대: 재야 설득은 그 사람, 계약·휴전은 그 나라 군주
static func opponent(kind: String, params: Dictionary) -> String:
	match kind:
		"recruit":
			return params.get("target", "")
		"contract":
			return Personnel.ruler_of(params.get("nation", ""))
		"truce":
			return Personnel.ruler_of(params.get("nation", ""))
	return ""


## 접근별 능력치 (0~100)
static func power_stat(id: String, approach: String) -> int:
	match approach:
		"logic":
			return Officers.stat(id, "int")
		"emotion":
			return Officers.stat(id, "cha")
	# 위세: 명성 + 신분
	var grade_bonus: int = MercGrade.steps(id) * int(MercGrade.cfg("prestige_per_step", 3))   # "1급 용병이시라고?"
	return clampi(int(int(Officers.get_state(id).get("fame", 0)) * float(cfg("prestige_per_fame", 0.3))) + Officers.rank_order(id) * int(cfg("prestige_per_rank", 3)) + grade_bonus, 0, 100)


static func start(kind: String, actor: String, params: Dictionary) -> Dictionary:
	var target: String = opponent(kind, params)
	var pol: int = Officers.stat(actor, "pol")
	var rounds: int = int(cfg("rounds", 3)) + (1 if pol >= int(cfg("extra_round_pol", 60)) else 0) + (1 if pol >= int(cfg("extra_round_pol2", 80)) else 0)
	var gauge: int = clampi(int(cfg("start_gauge", 20)) + int(Relationship.affinity(actor, target) * float(cfg("start_per_affinity", 0.2))), 0, int(cfg("start_max", 60)))
	var n: Dictionary = {
		"kind": kind, "actor": actor, "target": target, "nation": params.get("nation", ""), "quest": params.get("quest", ""),
		"gauge": gauge, "goal": int(cfg("goal", {}).get(kind, 100)), "round": 1, "rounds": rounds, "log": [],
	}
	_new_round(n)
	return n


## 이번 라운드 상대의 마음가짐과 눈치(힌트)
static func _new_round(n: Dictionary) -> void:
	var p: Dictionary = Officers.get_state(n["target"]).get("personality", {})
	var weights: Array = []
	for a: String in APPROACHES:
		weights.append(float(int(p.get(TRAIT_OF[a], 50)) + int(cfg("weight_floor", 10))))
	var open: String = APPROACHES[_weighted_index(weights)]
	var rest: Array = APPROACHES.filter(func(a: String) -> bool: return a != open)
	# 남은 둘 중 성격 수치가 낮은 쪽을 질색한다 (같으면 아무거나)
	var t0: int = int(p.get(TRAIT_OF[rest[0]], 50))
	var t1: int = int(p.get(TRAIT_OF[rest[1]], 50))
	var closed: String = rest[0] if t0 < t1 or (t0 == t1 and RNG.chance(0.5)) else rest[1]
	n["posture"] = {}
	for a: String in APPROACHES:
		n["posture"][a] = float(cfg("open_mult", 1.5)) if a == open else (float(cfg("closed_mult", 0.3)) if a == closed else 1.0)
	# 눈치: 지력이 높을수록 진짜 열린 쪽을 짚는다
	var accuracy: float = clampf(float(cfg("hint_base", 0.35)) + Officers.stat(n["actor"], "int") * float(cfg("hint_per_int", 0.006)), 0.0, float(cfg("hint_max", 0.95)))
	n["hint"] = open if RNG.chance(accuracy) else RNG.pick(rest)


static func _weighted_index(weights: Array) -> int:
	var total: float = 0.0
	for w: float in weights:
		total += w
	var roll: float = RNG.randf() * total
	for i: int in weights.size():
		roll -= float(weights[i])
		if roll < 0.0:
			return i
	return weights.size() - 1


static func finished(n: Dictionary) -> bool:
	return int(n["gauge"]) >= int(n["goal"]) or int(n["round"]) > int(n["rounds"])


static func succeeded(n: Dictionary) -> bool:
	return int(n["gauge"]) >= int(n["goal"])


## 한 라운드. 돌려주는 값: {"gain", "reaction": "open"/"neutral"/"closed"}
static func play(n: Dictionary, approach: String) -> Dictionary:
	var mine: int = power_stat(n["actor"], approach)
	var theirs: int = power_stat(n["target"], approach)
	var mult: float = float(n["posture"][approach])
	var gain: int = int(round((float(cfg("base_power", 15)) + mine * float(cfg("power_per_stat", 0.2))) * (mine + 50.0) / (theirs + 50.0) * mult * RNG.randf_range(0.85, 1.15)))
	n["gauge"] = mini(int(n["gauge"]) + gain, int(n["goal"]) + 50)
	var reaction: String = "open" if mult > 1.0 else ("closed" if mult < 1.0 else "neutral")
	n["log"].append({"approach": approach, "gain": gain, "reaction": reaction})
	n["round"] = int(n["round"]) + 1
	if not finished(n):
		_new_round(n)
	return {"gain": gain, "reaction": reaction}


## 계약 보수 배율: 0.75 ~ 1.5 (게이지 비율로)
static func pay_mult(n: Dictionary) -> float:
	var ratio: float = clampf(float(n["gauge"]) / float(n["goal"]), 0.0, 1.0)
	return float(cfg("pay_mult_min", 0.75)) + (float(cfg("pay_mult_max", 1.5)) - float(cfg("pay_mult_min", 0.75))) * ratio


## 끝난 설전의 결과를 반영한다. 돌려주는 값: 결과 문장들
static func apply(n: Dictionary) -> Array:
	var lines: Array = []
	var actor: String = n["actor"]
	var target: String = n["target"]
	var ok: bool = succeeded(n)
	Relationship.mark_met(actor, target)
	match n["kind"]:
		"recruit":
			if ok and Career.is_free_agent(target) and Career.has_free_slot(actor):
				Career.add_companion(actor, target)
				lines.append(GameAction.msg("NEGO_RECRUIT_OK", [Officers.display_name(target)]))
			else:
				Relationship.add(actor, target, int(cfg("recruit_fail_affinity", -3)))
				lines.append(GameAction.msg("NEGO_RECRUIT_FAIL", [Officers.display_name(target)]))
		"contract":
			var city: String = Officers.get_state(actor).get("city", "")
			var q: Dictionary = Guild.find(Guild.city_quests(city), n["quest"])
			if not q.is_empty():
				var mult: float = pay_mult(n)
				q["pay"] = int(round(int(q["pay"]) * mult))
				q["gold"] = q["pay"]
				q["win_bonus"] = int(round(int(q.get("win_bonus", 0)) * mult))
				q["negotiated"] = true
				lines.append(GameAction.msg("NEGO_CONTRACT_DONE", [Diplomacy.nation_name(q["employer"]), int(round(mult * 100)), Fmt.num(int(q["pay"]))]))
		"truce":
			var mine: String = Officers.get_state(actor).get("nation", "")
			if ok and Diplomacy.at_war(mine, n["nation"]):
				Diplomacy.set_truce(mine, n["nation"])
				lines.append(GameAction.msg("NEGO_TRUCE_OK", [Diplomacy.nation_name(n["nation"]), int(GameState.diplomacy[Diplomacy.key(mine, n["nation"])]["months"])]))
			else:
				lines.append(GameAction.msg("NEGO_TRUCE_FAIL", [Diplomacy.nation_name(n["nation"])]))
	return lines
