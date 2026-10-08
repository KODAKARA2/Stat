class_name SkillLevels
extends RefCounted
## 전법 레벨 1~3 (기획 2026-10-08). 레벨이 오르면 피해·사거리·범위가 커진다 (skills.json levels).
## 장수 상태: skill_levels = {전법: 레벨}, skill_uses = {전법: 누적 사용 횟수}.
## 해금 ① 많이 쓰기 (uses) ② 그 전법을 더 잘 쓰는 사람과 친해지기 (매월 초, 스승 레벨까지 한 단계씩)


static func cfg(key: String, default_value: Variant = null) -> Variant:
	return DataDB.get_table("balance").get("skill_leveling", {}).get(key, default_value)


static func max_level() -> int:
	return int(cfg("max_level", 3))


## 레벨이 있는 전법인가 (전투에서 쓰는 특기)
static func is_battle(skill_id: String) -> bool:
	return DataDB.get_row("skills", skill_id).has("battle")


## 지금 레벨. 따로 적힌 적이 없으면: 주인공은 1, 다른 장수는 그 전법의 주 능력치로 정한다.
static func level(id: String, skill_id: String) -> int:
	var s: Dictionary = Officers.get_state(id)
	var levels: Dictionary = s.get("skill_levels", {})
	if levels.has(skill_id):
		return clampi(int(levels[skill_id]), 1, max_level())
	if id == GameState.player_id:
		return 1
	return default_level(id, skill_id)


static func default_level(id: String, skill_id: String) -> int:
	var stat: int = Officers.base_stat(id, DataDB.get_row("skills", skill_id).get("key_stat", "str"))
	var lv: int = 1
	for line: Variant in cfg("npc_stat", [70, 85]):
		if stat >= int(line):
			lv += 1
	return clampi(lv, 1, max_level())


## 화면에 쓰는 전법 이름: "돌격 Lv2" (전투 전법이 아니면 이름만)
static func title(skill: Dictionary) -> String:
	var name: String = TranslationServer.translate(skill.get("name_key", ""))
	return name + " Lv%d" % int(skill["level"]) if skill.has("level") else name


## 장수 카드용: "돌격 Lv2 (사용 4/18)"
static func card_line(id: String, skill_id: String) -> String:
	var name: String = TranslationServer.translate(DataDB.get_row("skills", skill_id).get("name_key", skill_id))
	if not is_battle(skill_id):
		return name
	var need: int = uses_needed(id, skill_id)
	if need == 0:
		return TranslationServer.translate("SKILL_CARD_MAX") % [name, level(id, skill_id)]
	return TranslationServer.translate("SKILL_CARD_LINE") % [name, level(id, skill_id), uses(id, skill_id), need]


## 처음부터 1레벨로 시작하는 전법 표 (주인공·자녀)
static func starting_levels(skill_ids: Array) -> Dictionary:
	var out: Dictionary = {}
	for skill_id: String in skill_ids:
		out[skill_id] = 1
	return out


static func set_level(id: String, skill_id: String, lv: int) -> void:
	Officers.get_state(id).get_or_add("skill_levels", {})[skill_id] = clampi(lv, 1, max_level())


static func uses(id: String, skill_id: String) -> int:
	return int(Officers.get_state(id).get("skill_uses", {}).get(skill_id, 0))


## 다음 레벨까지 필요한 누적 사용 횟수 (최고 레벨이면 0)
static func uses_needed(id: String, skill_id: String) -> int:
	var lv: int = level(id, skill_id)
	if lv >= max_level():
		return 0
	return int(cfg("uses", {}).get(str(lv + 1), 999))


## 전법을 한 번 썼다. 레벨이 올랐으면 새 레벨, 아니면 0
static func add_use(id: String, skill_id: String) -> int:
	if id == "" or not GameState.officers.has(id):
		return 0
	var before: int = level(id, skill_id)
	var s: Dictionary = Officers.get_state(id)
	var counts: Dictionary = s.get_or_add("skill_uses", {})
	counts[skill_id] = int(counts.get(skill_id, 0)) + 1
	var lv: int = before
	while lv < max_level() and int(counts[skill_id]) >= int(cfg("uses", {}).get(str(lv + 1), 999)):
		lv += 1
	set_level(id, skill_id, lv)   # 처음 쓴 순간 지금 레벨을 적어 둔다 (이후 능력치가 바뀌어도 그대로)
	return lv if lv > before else 0


## 레벨을 반영한 전법 정보: 데이터 행을 복사하고 battle 값을 그 레벨 것으로 덮어쓴 것 + "level"
static func row_for(id: String, skill_id: String) -> Dictionary:
	var row: Dictionary = DataDB.get_row("skills", skill_id).duplicate(true)
	if not row.has("battle"):
		return row
	var lv: int = level(id, skill_id) if id != "" else 1
	var levels: Array = row.get("levels", [])
	if lv - 1 < levels.size():
		row["battle"].merge(levels[lv - 1], true)
	row["level"] = lv
	return row


## 매월 초: 그 전법을 더 잘 쓰는 친한 사람에게서 배운다. 바뀐 내용을 문장으로 돌려준다.
static func learn_from_mentors(id: String) -> Array:
	var lines: Array = []
	var need: int = int(cfg("mentor_affinity", 70))
	for skill_id: String in Officers.get_state(id).get("skills", []):
		if not is_battle(skill_id):
			continue
		var lv: int = level(id, skill_id)
		if lv >= max_level():
			continue
		var mentor: String = ""
		for other: String in GameState.officers:
			if other == id or not Officers.is_active(other) or not Officers.get_state(other).get("skills", []).has(skill_id):
				continue
			if level(other, skill_id) > lv and Relationship.has_met(id, other) and Relationship.affinity(id, other) >= need:
				mentor = other
				break
		if mentor == "":
			continue
		set_level(id, skill_id, lv + 1)
		lines.append(GameAction.msg("SKILL_LEARNED", [Officers.display_name(id), Officers.display_name(mentor),
			TranslationServer.translate(DataDB.get_row("skills", skill_id)["name_key"]), lv + 1]))
	return lines


## 주인공과 동료들의 월초 배움
static func start_month() -> void:
	if GameState.player_id == "":
		return
	for id: String in [GameState.player_id] + Career.companions(GameState.player_id):
		if Officers.is_active(id):
			for line: String in learn_from_mentors(id):
				GameState.flags.get_or_add("month_log", []).append(line)
