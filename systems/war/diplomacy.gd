class_name Diplomacy
extends RefCounted
## 나라 사이 관계 (GDD §2.3): 전쟁(war) / 휴전(truce). 상태는 GameState.diplomacy에 있다.


static func cfg(key: String, default_value: Variant = null) -> Variant:
	return DataDB.get_table("war").get("diplomacy", {}).get(key, default_value)


static func key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


static func setup() -> void:
	GameState.diplomacy.clear()
	var alive: Array = alive_nations()
	for i: int in alive.size():
		for j: int in range(i + 1, alive.size()):
			GameState.diplomacy[key(alive[i], alive[j])] = {"status": "truce", "months": 6}
	for row: Dictionary in DataDB.get_rows("diplomacy"):
		GameState.diplomacy[key(row["a"], row["b"])] = {"status": row["status"], "months": int(row.get("months", 0))}


static func alive_nations() -> Array:
	var list: Array = []
	for n: String in GameState.nations:
		if GameState.nations[n].get("alive", false):
			list.append(n)
	return list


static func status(a: String, b: String) -> String:
	return GameState.diplomacy.get(key(a, b), {}).get("status", "truce")


static func at_war(a: String, b: String) -> bool:
	return a != b and a != "" and b != "" and status(a, b) == "war"


static func set_war(a: String, b: String) -> void:
	GameState.diplomacy[key(a, b)] = {"status": "war", "months": 0}


static func set_truce(a: String, b: String, months: int = -1) -> void:
	if months < 0:
		months = RNG.randi_range(int(cfg("truce_min", 6)), int(cfg("truce_max", 12)))
	GameState.diplomacy[key(a, b)] = {"status": "truce", "months": months}


## 도시 하나라도 맞닿아 있으면 이웃 나라
static func neighbor_nations(n: String) -> Array:
	var result: Array = []
	var world: WorldMap = WorldMap.shared()
	for city: String in GameState.cities:
		if GameState.city_owner(city) != n:
			continue
		for other: String in world.neighbors(city):
			var owner: String = GameState.city_owner(other)
			if owner != n and owner != "" and not result.has(owner):
				result.append(owner)
	return result


## 매월 말: 휴전 기간 -1. 끝나면 연장하거나 다시 전쟁. 바뀐 내용을 문장으로 돌려준다.
static func tick() -> Array:
	var lines: Array = []
	for k: String in GameState.diplomacy:
		var d: Dictionary = GameState.diplomacy[k]
		if d["status"] != "truce":
			continue
		d["months"] = int(d["months"]) - 1
		if int(d["months"]) > 0:
			continue
		var pair: PackedStringArray = k.split("|")
		if RNG.chance(float(cfg("renew_chance", 0.3))):
			set_truce(pair[0], pair[1])
			lines.append(GameAction.msg("DIPLO_TRUCE_RENEWED", [nation_name(pair[0]), nation_name(pair[1])]))
		else:
			set_war(pair[0], pair[1])
			lines.append(GameAction.msg("DIPLO_WAR_RESUMED", [nation_name(pair[0]), nation_name(pair[1])]))
	return lines


static func nation_name(n: String) -> String:
	return Nations.display_name(n)
