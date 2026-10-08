class_name OfficerGen
extends RefCounted
## 범용 장수 생성 (이름표: data/names/<종족>.json, 수치: data/officer_gen.json).
## 능력치는 평균적으로 낮지만 무작위라 가끔 쓸 만한 인재가 나온다.


static func cfg(key: String, default_value: Variant = null) -> Variant:
	return DataDB.get_table("officer_gen").get(key, default_value)


## 새 장수를 만들어 GameState에 넣고 id를 돌려준다. race/gender가 ""이면 무작위.
static func generate(nation_id: String, city_id: String, rank: String, race_id: String = "", gender: String = "") -> String:
	if race_id == "":
		race_id = _pick_race(nation_id)
	if gender == "":
		gender = "m" if RNG.chance(0.5) else "f"
	var race: Dictionary = DataDB.get_row("races", race_id)
	var stats: Dictionary = {}
	for key: String in Officers.stat_keys():
		stats[key] = RNG.randi_range(int(cfg("stat_min", 15)), int(cfg("stat_max", 55)))
	if RNG.chance(float(cfg("spike_chance", 0.3))):
		var lucky: String = RNG.pick(Officers.stat_keys())
		stats[lucky] = int(stats[lucky]) + RNG.randi_range(int(cfg("spike_min", 10)), int(cfg("spike_max", 30)))
	var pot: Dictionary = {}
	for key: String in stats:
		stats[key] = Officers.clamp_stat(int(stats[key]) + int(race.get("stat_mod", {}).get(key, 0)))
		pot[key] = Officers.clamp_stat(int(stats[key]) + RNG.randi_range(int(cfg("potential_min", 5)), int(cfg("potential_max", 20))))
	var skills: Array = []
	if RNG.chance(float(cfg("skill_chance", 0.3))):
		skills.append(RNG.pick(cfg("battle_skills", ["charge"])))
	var adult: int = int(race.get("adult_age", 16))
	var id: String = _new_id()
	var row: Dictionary = {
		"id": id, "race": race_id, "gender": gender,
		"variant": "dark_elf" if race_id == "elf" and RNG.chance(0.3) else "",
		"age": adult + RNG.randi_range(0, maxi(10, adult)),
		"nation": nation_id, "city": city_id, "rank": rank,
		"stats": stats, "potential": pot, "skills": skills,
		"unit_type": _unit_type_for(stats),
		"personality": {"ambition": RNG.randi_range(10, 80), "loyalty": RNG.randi_range(20, 80), "greed": RNG.randi_range(10, 80)},
	}
	var state: Dictionary = Officers.state_from_data(row)
	state["name"] = _make_name(race_id, gender)
	state["variant"] = row["variant"]
	state["generic"] = true
	state["sprite_id"] = Portraits.pick(race_id, state["variant"], gender)
	GameState.officers[id] = state
	return id


static func _new_id() -> String:
	var n: int = int(GameState.flags.get("generic_count", 0)) + 1
	GameState.flags["generic_count"] = n
	return "gen_%d" % n


## 나라 주요 종족 중에서 (재야면 아무 종족)
static func _pick_race(nation_id: String) -> String:
	var races: Array = Nations.row(nation_id).get("races", [])
	if races.is_empty():
		races = []
		for r: Dictionary in DataDB.get_rows("races"):
			races.append(r["id"])
	return RNG.pick(races)


## 이름: 이름표에서 고르고, 이미 쓰는 이름이면 다시 (몇 번 해도 겹치면 그대로)
static func _make_name(race_id: String, gender: String) -> String:
	var table: Dictionary = DataDB.get_table("names/" + race_id) if DataDB.has_table("names/" + race_id) else {}
	var used: Dictionary = {}
	for id: String in GameState.officers:
		used[Officers.display_name(id)] = true
	var name: String = "?"
	for attempt: int in 8:
		name = RNG.pick(table.get(gender, ["무명"]))
		var family: Array = table.get("family", [])
		if not family.is_empty():
			name += " " + RNG.pick(family)
		if not used.has(name):
			break
	return name


## 가장 높은 능력에 맞춰 병종
static func _unit_type_for(stats: Dictionary) -> String:
	if int(stats["mag"]) >= maxi(int(stats["str"]), int(stats["lead"])):
		return "mage"
	if int(stats["lead"]) > int(stats["str"]) + 10:
		return "infantry"
	return RNG.pick(["cavalry", "archer", "infantry"])
