class_name Personnel
extends RefCounted
## 나라의 인사 (월말): 군주 승계, 재야 인재 등용, 범용 장수 기용, 떠돌이 재야 등장.


static func rcfg(key: String, default_value: Variant = null) -> Variant:
	return DataDB.get_table("officer_gen").get("recruit", {}).get(key, default_value)


static func officers_of(n: String) -> Array:
	var list: Array = []
	for id: String in GameState.officers:
		if id != GameState.player_id and Officers.is_active(id) and Officers.get_state(id).get("nation", "") == n:
			list.append(id)
	return list


static func ruler_of(n: String) -> String:
	if n != "" and GameState.player().get("nation", "") == n and GameState.player().get("rank", "") == "ruler" and Officers.is_active(GameState.player_id):
		return GameState.player_id   # 주인공이 세운 나라의 군주는 주인공
	for id: String in officers_of(n):
		if Officers.get_state(id).get("rank", "") == "ruler":
			return id
	return ""


static func capital_of(n: String) -> String:
	var best: String = ""
	for city: String in Economy.cities_of(n):
		if DataDB.get_row("cities", city).get("capital", false) and DataDB.get_row("cities", city).get("nation", "") == n:
			return city
		if best == "" or int(GameState.cities[city]["population"]) > int(GameState.cities[best]["population"]):
			best = city
	return best


## 매월 말 한 나라의 인사. 바뀐 내용을 문장으로 돌려준다.
static func run_month(n: String) -> Array:
	var lines: Array = []
	var cities: Array = Economy.cities_of(n)
	if cities.is_empty():
		return lines
	# 군주가 없으면 가장 신분 높은(같으면 강한) 무장이 즉위
	if ruler_of(n) == "":
		var heir: String = ""
		for id: String in officers_of(n):
			if heir == "" or Officers.rank_order(id) > Officers.rank_order(heir) or \
					(Officers.rank_order(id) == Officers.rank_order(heir) and NationAI.commander_score(id) > NationAI.commander_score(heir)):
				heir = id
		if heir != "":
			Officers.get_state(heir)["rank"] = "ruler"
			lines.append(GameAction.msg("PEOPLE_NEW_RULER", [Officers.display_name(heir), Diplomacy.nation_name(n)]))
	var target: int = maxi(int(rcfg("min", 4)), cities.size() * int(rcfg("per_city", 2)))
	if officers_of(n).size() >= target:
		return lines
	# 재야 등용: 그 나라 도시에 있는 재야 한 명
	var ruler: String = ruler_of(n)
	var chance: float = float(rcfg("base_chance", 0.35)) + (Officers.stat(ruler, "cha") - 50) * float(rcfg("cha_factor", 0.005)) if ruler != "" else float(rcfg("base_chance", 0.35))
	for id: String in GameState.officers:
		var s: Dictionary = GameState.officers[id]
		if not Career.is_free_agent(id) or not cities.has(s.get("city", "")):
			continue
		if RNG.chance(chance):
			s["nation"] = n
			s["rank"] = "vassal_knight"
			lines.append(GameAction.msg("PEOPLE_RECRUITED", [Officers.display_name(id), Diplomacy.nation_name(n)]))
			return lines
		break   # 한 달에 한 명만 시도
	# 범용 장수 기용
	if RNG.chance(float(rcfg("generic_chance", 0.3))):
		var id: String = OfficerGen.generate(n, capital_of(n), "vassal_knight")
		lines.append(GameAction.msg("PEOPLE_GENERIC", [Diplomacy.nation_name(n), Officers.display_name(id)]))
	return lines


## 떠돌이 재야가 가끔 나타난다 (등용·동료 영입 후보)
static func spawn_wanderer() -> Array:
	var count: int = 0
	for id: String in GameState.officers:
		if id != GameState.player_id and Officers.is_active(id) and Officers.get_state(id).get("nation", "") == "":
			count += 1
	if count >= int(rcfg("wanderer_cap", 15)) or not RNG.chance(float(rcfg("wanderer_chance", 0.25))):
		return []
	var city: String = RNG.pick(GameState.cities.keys())
	var id: String = OfficerGen.generate("", city, "none")
	return [GameAction.msg("PEOPLE_WANDERER", [Officers.display_name(id), Officers.race_label(id), WorldMap.city_name(city)])]
