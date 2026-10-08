class_name Officers
extends RefCounted
## 무장(플레이어 포함) 상태 조회 도우미. 상태 자체는 GameState.officers에 있다.


static func get_state(id: String) -> Dictionary:
	return GameState.officers.get(id, {})


static func is_player(id: String) -> bool:
	return id == GameState.player_id


static func display_name(id: String) -> String:
	var s: Dictionary = get_state(id)
	if String(s.get("name", "")) != "":
		return s["name"]
	return TranslationServer.translate(s.get("name_key", id))


## 실제로 쓰는 능력치 = 기본 능력치 + 장비 보너스 (1~100)
static func stat(id: String, key: String) -> int:
	return clamp_stat(base_stat(id, key) + equipment_bonus(id, key)) if GameState.officers.has(id) else 0


## 성장·잠재치 비교에 쓰는 기본 능력치 (장비 제외)
static func base_stat(id: String, key: String) -> int:
	return int(get_state(id).get("stats", {}).get(key, 0))


static func equipment_bonus(id: String, key: String) -> int:
	var total: int = 0
	for item_id: Variant in get_state(id).get("equipment", {}).values():
		total += int(DataDB.get_row("items", str(item_id)).get("bonus", {}).get(key, 0))
	return total


static func potential(id: String, key: String) -> int:
	return int(get_state(id).get("potential", {}).get(key, 0))


static func stat_keys() -> Array:
	return DataDB.balance("stats.keys", ["lead", "str", "int", "mag", "pol", "cha"])


static func stat_label(key: String) -> String:
	return TranslationServer.translate("STAT_" + key.to_upper())


static func clamp_stat(value: int) -> int:
	return clampi(value, DataDB.balance("stats.min", 1), DataDB.balance("stats.max", 100))


static func race_label(id: String) -> String:
	var s: Dictionary = get_state(id)
	return race_label_of(s.get("race", ""), s.get("variant", ""))


static func race_label_of(race_id: String, variant: String) -> String:
	var race: Dictionary = DataDB.get_row("races", race_id)
	for v: Dictionary in race.get("variants", []):
		if v["id"] == variant:
			return TranslationServer.translate(v["name_key"])
	return TranslationServer.translate(race.get("name_key", "?"))


static func has_trait(id: String, trait_id: String) -> bool:
	var race: Dictionary = DataDB.get_row("races", get_state(id).get("race", ""))
	return race.get("traits", []).has(trait_id)


static func rank_row(id: String) -> Dictionary:
	return DataDB.get_row("ranks", get_state(id).get("rank", "none"))


static func rank_label(id: String) -> String:
	return TranslationServer.translate(rank_row(id).get("name_key", "RANK_NONE"))


static func rank_order(id: String) -> int:
	return int(rank_row(id).get("order", 0))


## free(재야) / merc(용병) / vassal(사관) / ruler(군주) — ranks.json의 track
static func track(id: String) -> String:
	return rank_row(id).get("track", "free")


static func nation_label(id: String) -> String:
	var nation: String = get_state(id).get("nation", "")
	if nation == "":
		return TranslationServer.translate("NATION_NONE")
	return Nations.display_name(nation)


static func max_ap(id: String) -> int:
	return int(DataDB.balance("ap.base", 3)) + int(rank_row(id).get("ap_bonus", 0))


static func is_active(id: String) -> bool:
	var s: Dictionary = get_state(id)
	return bool(s.get("alive", false)) and not bool(s.get("minor", false))   # 미성년 자녀는 활동하지 않는다


## 그 도시에 있는 활동 중인 무장 목록. 신분 높은 순.
static func in_city(city_id: String, exclude: String = "") -> PackedStringArray:
	var ids: Array = []
	for id: String in GameState.officers:
		if id != exclude and is_active(id) and get_state(id).get("city", "") == city_id:
			ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool: return rank_order(a) > rank_order(b))
	return PackedStringArray(ids)


## data/officers.json 한 줄 → 판 상태
static func state_from_data(row: Dictionary) -> Dictionary:
	var headroom: int = DataDB.balance("officer.default_potential_headroom", 12)
	var stats: Dictionary = {}
	var pot: Dictionary = {}
	for key: String in stat_keys():
		stats[key] = clamp_stat(int(row.get("stats", {}).get(key, 1)))
		pot[key] = clamp_stat(int(row.get("potential", {}).get(key, stats[key] + headroom)))
	return {
		"name_key": row.get("name_key", ""),
		"race": row.get("race", "human"),
		"variant": row.get("variant", ""),
		"gender": row.get("gender", ""),
		"age": int(row.get("age", 20)),
		"nation": row.get("nation", ""),
		"origin": row.get("nation", ""),
		"city": row.get("city", ""),
		"rank": row.get("rank", "none"),
		"stats": stats,
		"potential": pot,
		"exp": {},
		"skills": row.get("skills", []).duplicate(),
		"personality": row.get("personality", {}).duplicate(),
		"ap": 0,
		"energy": int(DataDB.balance("energy.start", 100)),
		"injury": 0,
		"gold": int(row.get("gold", 0)),
		"fame": int(row.get("fame", 0)),
		"alive": true,
		"sprite_id": "portrait_" + String(row.get("id", "")),
		"unit_type": row.get("unit_type", "infantry"),
		"troops": troops_for_lead(int(row.get("stats", {}).get("lead", 1))),
	}


## 장수 부대 최대 병력 = troops_base + 통솔 × troops_per_lead (GDD §4.3 통솔 → 최대 병력)
static func max_troops(id: String) -> int:
	return troops_for_lead(stat(id, "lead"))


static func troops_for_lead(lead: int) -> int:
	return int(DataDB.balance("battle.troops_base", 200)) + lead * int(DataDB.balance("battle.troops_per_lead", 4))
