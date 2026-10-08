class_name Portraits
extends RefCounted
## 초상화 고르기: data/portraits.json의 종족·성별 묶음에서. 살아 있는 사람과 겹치지 않는 것을 우선한다.
## 결과는 sprite_id("pt_###")이고, 실제 파일은 assets/manifest.json이 정한다.


static func pool(race_id: String, variant: String, gender: String) -> Array:
	var pools: Dictionary = DataDB.get_table("portraits").get("pools", {}) if DataDB.has_table("portraits") else {}
	var key: String = ("dark_elf" if variant == "dark_elf" else race_id) + "_" + gender
	var list: Array = pools.get(key, [])
	if list.is_empty():
		list = pools.get("human_" + gender, pools.get("human_m", []))
	return list


## 묶음 항목: 숫자면 예전 임시 그림("pt_###"), 문자열이면 그대로 sprite id (새 그림 "ai_...")
static func sprite_id(entry: Variant) -> String:
	return "pt_%03d" % int(entry) if (entry is int or entry is float) else str(entry)


## 아직 아무도 안 쓰는 초상화 하나 (다 쓰였으면 아무거나)
static func pick(race_id: String, variant: String, gender: String) -> String:
	var list: Array = pool(race_id, variant, gender)
	if list.is_empty():
		return ""
	var used: Dictionary = {}
	for id: String in GameState.officers:
		var s: Dictionary = GameState.officers[id]
		if bool(s.get("alive", false)):
			used[s.get("sprite_id", "")] = true
	var free: Array = list.filter(func(n: Variant) -> bool: return not used.has(sprite_id(n)))
	return sprite_id(RNG.pick(free if not free.is_empty() else list))
