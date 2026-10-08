class_name Relationship
extends RefCounted
## 무장 쌍의 친밀도 (GDD §5). 실제 친밀도 = 종족 간 기본 보정 + 쌓인 변화량.
## 변화량이 0이고 만난 적도 없는 쌍은 저장하지 않는다(희소 저장).


static func key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


static func race_base(a: String, b: String) -> int:
	var ra: String = Officers.get_state(a).get("race", "")
	var rb: String = Officers.get_state(b).get("race", "")
	for row: Dictionary in DataDB.get_rows("race_affinity"):
		if (row["a"] == ra and row["b"] == rb) or (row["a"] == rb and row["b"] == ra):
			return int(row["value"])
	return 0


static func affinity(a: String, b: String) -> int:
	var stored: int = int(GameState.relations.get(key(a, b), {}).get("v", 0))
	return clampi(race_base(a, b) + stored, DataDB.balance("affinity.min", -100), DataDB.balance("affinity.max", 100))


## 변화량을 더하고 새 친밀도를 돌려준다. 상한·하한을 넘는 만큼은 버린다.
static func add(a: String, b: String, delta: int) -> int:
	var k: String = key(a, b)
	var entry: Dictionary = GameState.relations.get(k, {"v": 0, "met": false})
	var base: int = race_base(a, b)
	var lo: int = DataDB.balance("affinity.min", -100)
	var hi: int = DataDB.balance("affinity.max", 100)
	entry["v"] = clampi(int(entry["v"]) + delta, lo - base, hi - base)
	_store(k, entry)
	return affinity(a, b)


static func has_met(a: String, b: String) -> bool:
	return bool(GameState.relations.get(key(a, b), {}).get("met", false))


static func mark_met(a: String, b: String) -> void:
	var k: String = key(a, b)
	var entry: Dictionary = GameState.relations.get(k, {"v": 0, "met": false})
	entry["met"] = true
	_store(k, entry)


static func _store(k: String, entry: Dictionary) -> void:
	if int(entry["v"]) == 0 and not entry["met"]:
		GameState.relations.erase(k)
	else:
		GameState.relations[k] = entry


# ── 관계 태그 (GDD §5): 전우·맹우·배우자·연인·원수·사제 ──

static func tags(a: String, b: String) -> Array:
	return GameState.relations.get(key(a, b), {}).get("tags", [])


static func has_tag(a: String, b: String, tag: String) -> bool:
	return tags(a, b).has(tag)


static func add_tag(a: String, b: String, tag: String) -> void:
	var k: String = key(a, b)
	var entry: Dictionary = GameState.relations.get(k, {"v": 0, "met": true})
	entry["met"] = true
	var list: Array = entry.get("tags", [])
	if not list.has(tag):
		list.append(tag)
	entry["tags"] = list
	GameState.relations[k] = entry


static func remove_tag(a: String, b: String, tag: String) -> void:
	var entry: Dictionary = GameState.relations.get(key(a, b), {})
	if entry.has("tags"):
		entry["tags"].erase(tag)


## 이 사람과 그 태그로 이어진 사람들
static func with_tag(a: String, tag: String) -> Array:
	var list: Array = []
	for k: String in GameState.relations:
		var entry: Dictionary = GameState.relations[k]
		if entry.get("tags", []).has(tag):
			var pair: PackedStringArray = k.split("|")
			if pair[0] == a:
				list.append(pair[1])
			elif pair[1] == a:
				list.append(pair[0])
	return list
