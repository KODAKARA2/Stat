class_name MercGrade
extends RefCounted
## 용병 등급 9급 → 1급 (기획 2026-10-08). 신분(신입 용병 … 용병대장)과는 따로 가는 길드의 평가.
## 길드 공적(merc_points)이 쌓이면 오른다. 등급이 높을수록 의뢰 보수·계약 월급이 많고, 사람들이 대단하게 본다
## (재야 영입이 잘 되고, 설전에서 위세가 높다). 용병대장이 아니어도 1급 용병일 수 있다.
## 수치는 guild.json grades.


static func cfg(key: String, default_value: Variant = null) -> Variant:
	return DataDB.get_table("guild").get("grades", {}).get(key, default_value)


static func points(id: String) -> int:
	return int(Officers.get_state(id).get("merc_points", 0))


## 지금 등급 (9 = 가장 낮음, 1 = 가장 높음)
static func grade(id: String) -> int:
	var p: int = points(id)
	var g: int = 9
	for need: Variant in cfg("thresholds", [6, 15, 28, 45, 70, 100, 140, 190]):   # 8급, 7급, … 1급에 필요한 공적
		if p >= int(need):
			g -= 1
	return g


## 9급에서 몇 단계 올랐나 (0 ~ 8)
static func steps(id: String) -> int:
	return 9 - grade(id)


## 다음 등급까지 필요한 공적 (1급이면 0)
static func next_need(id: String) -> int:
	var th: Array = cfg("thresholds", [6, 15, 28, 45, 70, 100, 140, 190])
	var s: int = steps(id)
	return int(th[s]) if s < th.size() else 0


static func label(id: String) -> String:
	return TranslationServer.translate("GRADE_LABEL") % grade(id)


## 보수 배율: 한 단계마다 pay_per_step
static func pay_mult(id: String) -> float:
	return 1.0 + steps(id) * float(cfg("pay_per_step", 0.05))


static func pay(id: String, base: int) -> int:
	return int(round(base * pay_mult(id)))


## 공적을 쌓는다. 등급이 올랐으면 알림 문장, 아니면 ""
static func add_points(id: String, amount: int) -> String:
	if id == "" or amount <= 0 or not GameState.officers.has(id):
		return ""
	var before: int = grade(id)
	var s: Dictionary = Officers.get_state(id)
	s["merc_points"] = points(id) + amount
	var after: int = grade(id)
	if after < before:
		return GameAction.msg("GRADE_UP", [after, int(round(steps(id) * float(cfg("pay_per_step", 0.05)) * 100))])
	return ""


## 의뢰 종류·단계에 따른 공적
static func quest_points(quest: Dictionary, won: bool) -> int:
	var kind: String = quest.get("type", "monster")
	var table: Dictionary = cfg("points", {})
	match kind:
		"war":
			return int(table.get("war_win", 6)) if won else int(table.get("war_lose", 2))
		"conquest":
			return int(table.get("conquest_win", 10)) if won else 0
	return int(table.get("monster", {}).get(str(int(quest.get("tier", 1))), 2)) if won else 0


## 장부 한 줄: "3급 용병 (공적 104/140)"
static func status_line(id: String) -> String:
	var need: int = next_need(id)
	if need == 0:
		return TranslationServer.translate("GRADE_STATUS_MAX") % [grade(id), points(id)]
	return TranslationServer.translate("GRADE_STATUS") % [grade(id), points(id), need]
