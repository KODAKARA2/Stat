class_name WarSystem
extends RefCounted
## 전쟁 레이어의 한 달 (GDD §3.1 월말 처리 / §7):
##  월초: 나라별 공격 계획 → 양쪽 도시 길드에 참전 의뢰
##  월말: 전투 판정 → 경제 → 내정·징병 → 세력균형 개입 → 휴전 기간 → 멸망 처리 → 월말 보고
## 월말 보고는 GameState.flags["report"]에 남고, 지도 화면이 다음 달 시작 때 보여 준다.


static func setup() -> void:
	for row: Dictionary in DataDB.get_rows("nations"):
		var gold: int = 0
		var food: int = 0
		for city: Dictionary in DataDB.get_rows("cities"):
			if city["nation"] == row["id"]:
				gold += int(city.get("gold", 0))
				food += int(city.get("food", 0))
		GameState.nations[row["id"]] = {"alive": true, "gold": gold, "food": food}
	Diplomacy.setup()
	GameState.flags["planned_attacks"] = []


static func plans() -> Array:
	return GameState.flags.get("planned_attacks", [])


static func find_plan(plan_id: String) -> Dictionary:
	for p: Dictionary in plans():
		if p["id"] == plan_id:
			return p
	return {}


static func start_month(month: int) -> void:
	var new_plans: Array = NationAI.plan_attacks(month)
	GameState.flags["planned_attacks"] = new_plans
	for p: Dictionary in new_plans:
		Guild.post_war_quests(p)


static func end_month(year: int, month: int) -> void:
	var report: Dictionary = {"year": year, "month": month, "battles": [], "diplomacy": [], "deaths": [], "economy": [], "people": [], "log": []}
	for p: Dictionary in plans():
		var r: Dictionary = WarResolver.resolve(p, month)
		report["battles"].append_array(r["lines"])
		report["deaths"].append_array(r["deaths"])
	GameState.flags["planned_attacks"] = []
	for n: String in Diplomacy.alive_nations():
		report["economy"].append_array(Economy.run_month(n, month))
		Economy.develop(n)
		Economy.recover_security(n)
		Economy.conscript(n)
		report["people"].append_array(Personnel.run_month(n))
	report["diplomacy"].append_array(NationAI.intervene())
	report["diplomacy"].append_array(Diplomacy.tick())
	report["diplomacy"].append_array(_eliminate())
	report["people"].append_array(Personnel.spawn_wanderer())
	report["log"] = GameState.flags.get("month_log", [])
	GameState.flags["month_log"] = []
	GameState.flags["report"] = report


## 도시가 하나도 없는 나라는 멸망. 무장은 재야가 된다.
static func _eliminate() -> Array:
	var lines: Array = []
	for n: String in Diplomacy.alive_nations():
		if not Economy.cities_of(n).is_empty():
			continue
		GameState.nations[n]["alive"] = false
		for id: String in GameState.officers:
			var s: Dictionary = GameState.officers[id]
			if s.get("nation", "") == n:
				s["nation"] = ""
				s["rank"] = "none"
		for k: String in GameState.diplomacy.keys():
			if n in k.split("|"):
				GameState.diplomacy.erase(k)
		lines.append(GameAction.msg("REPORT_FALLEN", [Diplomacy.nation_name(n)]))
	return lines


static func report_is_empty(report: Dictionary) -> bool:
	for key: String in ["battles", "diplomacy", "deaths", "economy", "people", "log"]:
		if not report.get(key, []).is_empty():
			return false
	return true
