class_name Guild
extends RefCounted
## 용병 길드 (GDD §9): 매월 초 도시마다 토벌 의뢰를 새로 걸고, 받은 의뢰를 관리한다.
## 의뢰 = {"id", "city", "monster", "tier", "gold", "fame", "exp", "deadline"(달 번호)}


static func cfg(key: String, default_value: Variant = null) -> Variant:
	return DataDB.get_table("guild").get(key, default_value) if DataDB.has_table("guild") else default_value


static func refresh_all() -> void:
	for city_id: String in GameState.cities:
		var list: Array = []
		for i: int in int(cfg("quests_per_city", 3)):
			list.append(make_quest(city_id))
		GameState.cities[city_id]["quests"] = list


static func city_quests(city_id: String) -> Array:
	return GameState.cities.get(city_id, {}).get("quests", [])


static func active_quests(officer_id: String) -> Array:
	return Officers.get_state(officer_id).get("quests", [])


## 그 도시 지형에 사는 몬스터 중에서 단계 비중대로 하나 고른다. 4단계(이벤트 전용)는 안 나온다.
static func make_quest(city_id: String) -> Dictionary:
	var terrain: String = DataDB.get_row("cities", city_id).get("terrain", "plains")
	var tier: int = _roll_tier()
	var pool: Array = monsters_for(terrain, tier)
	var monster: Dictionary = RNG.pick(pool)
	var party: Dictionary = cfg("parties", {}).get(str(tier), {})
	var spread: float = float(cfg("reward_random", 0.2))
	return {
		"id": "q%d_%d" % [TimeManager.month_index(), RNG.randi_range(1000, 9999)],
		"type": "monster",
		"city": city_id,
		"monster": monster["id"],
		"tier": tier,
		"gold": int(party.get("gold", 80) * RNG.randf_range(1.0 - spread, 1.0 + spread)),
		"fame": int(party.get("fame", 2)),
		"exp": int(party.get("exp", 25)),
		"deadline": TimeManager.month_index() + int(cfg("deadline_months", 2)),
	}


## 그 지형에 사는 그 단계 몬스터. 없으면 단계만 맞는 아무 몬스터.
static func monsters_for(terrain: String, tier: int) -> Array:
	var exact: Array = []
	var any_tier: Array = []
	for m: Dictionary in DataDB.get_rows("monsters"):
		if int(m["tier"]) != tier or m.get("event_only", false):
			continue
		any_tier.append(m)
		if m.get("habitat", []).has(terrain):
			exact.append(m)
	return exact if not exact.is_empty() else any_tier


static func _roll_tier() -> int:
	var weights: Dictionary = cfg("tier_weights", {"1": 1.0})
	var total: float = 0.0
	for k: String in weights:
		total += float(weights[k])
	var roll: float = RNG.randf() * total
	for k: String in weights:
		roll -= float(weights[k])
		if roll <= 0.0:
			return int(k)
	return int(weights.keys()[0])


static func find(list: Array, quest_id: String) -> Dictionary:
	for q: Dictionary in list:
		if q["id"] == quest_id:
			return q
	return {}


## 마감이 지난 의뢰는 사라진다 (위약금은 M4 전쟁 계약에서)
static func expire(officer_id: String) -> Array:
	var expired: Array = []
	var list: Array = active_quests(officer_id)
	for q: Dictionary in list.duplicate():
		if TimeManager.month_index() > int(q["deadline"]):
			list.erase(q)
			expired.append(q)
			Record.add(officer_id, "quest_fail")   # 기한을 넘긴 의뢰는 실패
	return expired


static func complete(officer_id: String, quest_id: String) -> void:
	var list: Array = active_quests(officer_id)
	list.erase(find(list, quest_id))


static func monster_name(quest: Dictionary) -> String:
	return TranslationServer.translate(DataDB.get_row("monsters", quest["monster"]).get("name_key", "?"))


# ── 용병 고용 ───────────────────────────────────
## 고용 부대 = {"type": helper_types의 id, "troops": 남은 병력, "months": 남은 계약 개월}

static func helper_type(type_id: String) -> Dictionary:
	for row: Dictionary in cfg("helper_types", []):
		if row["id"] == type_id:
			return row
	return {}


static func hire_cfg(key: String, default_value: Variant) -> Variant:
	return cfg("hire", {}).get(key, default_value)


static func hired(officer_id: String) -> Array:
	return Officers.get_state(officer_id).get("hired", [])


static func max_hired(officer_id: String) -> int:
	var count: int = int(hire_cfg("max_units", 2))
	if Officers.get_state(officer_id).get("perks", []).has("extra_hire"):
		count += 1
	return count


## 특기 상재가 있으면 할인
static func hire_cost(officer_id: String, type_id: String) -> int:
	var cost: float = float(helper_type(type_id).get("cost", 60))
	if Officers.get_state(officer_id).get("skills", []).has("commerce"):
		cost *= 1.0 - float(hire_cfg("commerce_discount", 0.25))
	return int(round(cost))


static func add_hired(officer_id: String, type_id: String) -> Dictionary:
	var s: Dictionary = Officers.get_state(officer_id)
	if not s.has("hired"):
		s["hired"] = []
	var entry: Dictionary = {"type": type_id, "troops": int(helper_type(type_id).get("troops", 200)), "months": int(hire_cfg("months", 2))}
	s["hired"].append(entry)
	return entry


## 매월 초: 계약 기간 -1, 끝난 계약은 떠난다. 떠난 부대 목록을 돌려준다.
static func tick_contracts(officer_id: String) -> Array:
	var left: Array = []
	var list: Array = hired(officer_id)
	for entry: Dictionary in list.duplicate():
		entry["months"] = int(entry["months"]) - 1
		if int(entry["months"]) <= 0:
			list.erase(entry)
			left.append(entry)
	return left


static func hired_name(type_id: String, number: int) -> String:
	return TranslationServer.translate(helper_type(type_id).get("hired_name_key", "")) % number


# ── 참전 의뢰 (M4) ──────────────────────────────
## 공격 계획 하나에 양쪽 도시 길드가 각각 용병을 구한다.
## {"id", "type": "war", "plan", "side": 편드는 나라, "enemy", "attack": 공격측인가, "city": 출발 도시, "target": 싸울 도시, "gold", "fame", "exp", "deadline": 이번 달}

static func war_cfg(key: String, default_value: Variant = null) -> Variant:
	return DataDB.get_table("war").get("war_quest", {}).get(key, default_value)


static func post_war_quests(plan: Dictionary) -> void:
	for attack: bool in [true, false]:
		var city: String = plan["from"] if attack else plan["to"]
		var q: Dictionary = {
			"id": "%s_%s" % [plan["id"], "a" if attack else "d"],
			"type": "war",
			"plan": plan["id"],
			"side": plan["attacker"] if attack else plan["defender"],
			"enemy": plan["defender"] if attack else plan["attacker"],
			"attack": attack,
			"city": city,
			"target": plan["to"],
			"tier": 2,
			"gold": int(war_cfg("gold", 220) * RNG.randf_range(0.9, 1.2)),
			"fame": int(war_cfg("fame", 5)),
			"exp": int(war_cfg("exp", 40)),
			"deadline": TimeManager.month_index(),
		}
		if GameState.cities.has(city):
			GameState.cities[city].get_or_add("quests", []).append(q)


## 게시판에 보일 의뢰 제목
static func quest_title(q: Dictionary) -> String:
	if q.get("type", "") == "contract":
		return GameAction.msg("CONTRACT_TITLE", [Diplomacy.nation_name(q["employer"]), int(q["months"]), Fmt.num(int(q["pay"]))])
	if q.get("type", "monster") == "war":
		return GameAction.msg("WAR_QUEST_ATTACK" if q["attack"] else "WAR_QUEST_DEFEND", [Diplomacy.nation_name(q["side"]), WorldMap.city_name(q["target"])])
	return GameAction.msg("GUILD_QUEST_LINE", [monster_name(q), int(q["tier"])])
