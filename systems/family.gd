class_name Family
extends RefCounted
## 가족과 세월 (GDD §4.4, §5, §5.1, §5.2): 노화·노환 사망, 연인·결혼, 맹우, 자녀(종족은 부모 한쪽 50:50), 성인식, 주인공 사망과 승계.


static func cfg(section: String, key: String, default_value: Variant = null) -> Variant:
	return DataDB.get_table("family").get(section, {}).get(key, default_value)


static func log_line(text: String) -> void:
	GameState.flags.get_or_add("month_log", []).append(text)


static func lifespan(id: String) -> int:
	return int(DataDB.get_row("races", Officers.get_state(id).get("race", "human")).get("lifespan", 70))


static func adult_age(id: String) -> int:
	return int(DataDB.get_row("races", Officers.get_state(id).get("race", "human")).get("adult_age", 16))


static func spouse(id: String) -> String:
	var list: Array = Relationship.with_tag(id, "spouse")
	for other: String in list:
		if bool(Officers.get_state(other).get("alive", false)):
			return other
	return ""


static func children(id: String) -> Array:
	var list: Array = []
	for other: String in GameState.officers:
		var s: Dictionary = GameState.officers[other]
		if bool(s.get("alive", false)) and id in s.get("parents", []):
			list.append(other)
	return list


static func is_single_adult(id: String) -> bool:
	var s: Dictionary = Officers.get_state(id)
	return Officers.is_active(id) and spouse(id) == "" and int(s.get("age", 0)) >= adult_age(id)


# ── 노화 ────────────────────────────────────────

## 이번 해 노환으로 세상을 떠날 확률
static func death_chance(id: String) -> float:
	var age: int = int(Officers.get_state(id).get("age", 0))
	var life: float = lifespan(id)
	var start: float = life * float(cfg("aging", "start_ratio", 0.85))
	if age < start:
		return 0.0
	var p: float
	if age < life:
		p = lerpf(float(cfg("aging", "start_chance", 0.03)), float(cfg("aging", "at_lifespan", 0.35)), (age - start) / maxf(life - start, 1.0))
	else:
		p = float(cfg("aging", "at_lifespan", 0.35)) + (age - life) * float(cfg("aging", "per_year_over", 0.1))
	return minf(p, float(cfg("aging", "max", 0.9)))


## 매년 1월 (나이 +1 다음): 노환 사망, 성인식, 출산
static func new_year() -> void:
	for id: String in GameState.officers.keys():
		var s: Dictionary = GameState.officers[id]
		if not bool(s.get("alive", false)):
			continue
		if bool(s.get("minor", false)):
			if int(s["age"]) >= adult_age(id):
				_come_of_age(id)
			continue
		if RNG.chance(death_chance(id)):
			die(id, "old_age")
	_npc_marriages()
	_births()


static func die(id: String, cause: String) -> void:
	var s: Dictionary = Officers.get_state(id)
	s["alive"] = false
	var line: String = GameAction.msg("FAMILY_DIED_" + cause.to_upper(), [Officers.display_name(id), int(s.get("age", 0))])
	log_line(line)
	if id == GameState.player_id:
		succeed(cause)
	else:
		# 동료였다면 명단에서 빠진다
		var leader: String = s.get("leader", "")
		if leader != "":
			Career.remove_companion(leader, id)


static func _come_of_age(id: String) -> void:
	var s: Dictionary = Officers.get_state(id)
	s["minor"] = false
	s["rank"] = "none"
	s["troops"] = Officers.max_troops(id)
	var parents: Array = s.get("parents", [])
	var player: String = GameState.player_id
	log_line(GameAction.msg("FAMILY_ADULT", [Officers.display_name(id), int(s["age"])]))
	# 주인공의 자녀는 자리가 있으면 동료로 합류
	if player in parents:
		s["city"] = Officers.get_state(player).get("city", s.get("city", ""))
		if Career.has_free_slot(player):
			Career.add_companion(player, id)


# ── 연애·결혼·맹우 ──────────────────────────────

static func can_confess(a: String, b: String) -> String:
	if not is_single_adult(a) or not is_single_adult(b) or a == b:
		return "ROMANCE_FAIL_NOT_SINGLE"
	if Relationship.has_tag(a, b, "lover"):
		return "ROMANCE_FAIL_ALREADY"
	if Relationship.affinity(a, b) < int(cfg("romance", "confess_affinity", 70)):
		return "ROMANCE_FAIL_AFFINITY"
	return ""


static func can_propose(a: String, b: String) -> String:
	if not is_single_adult(a) or not is_single_adult(b):
		return "ROMANCE_FAIL_NOT_SINGLE"
	if not Relationship.has_tag(a, b, "lover"):
		return "ROMANCE_FAIL_NOT_LOVER"
	if Relationship.affinity(a, b) < int(cfg("romance", "propose_affinity", 80)):
		return "ROMANCE_FAIL_AFFINITY"
	return ""


static func marry(a: String, b: String) -> void:
	Relationship.remove_tag(a, b, "lover")
	Relationship.add_tag(a, b, "spouse")


static func can_swear(a: String, b: String) -> String:
	if a == b or not Officers.is_active(b):
		return "ACT_FAIL_NO_TARGET"
	if Relationship.has_tag(a, b, "sworn"):
		return "SWORN_FAIL_ALREADY"
	if Relationship.affinity(a, b) < int(cfg("sworn", "sworn_affinity", 90)):
		return "ROMANCE_FAIL_AFFINITY"
	return ""


# ── 자녀 ────────────────────────────────────────

static func _births() -> void:
	var done: Dictionary = {}
	for id: String in GameState.officers.keys():
		var partner: String = spouse(id)
		if partner == "" or done.has(id) or not Officers.is_active(id):
			continue
		done[id] = true
		done[partner] = true
		var a: Dictionary = Officers.get_state(id)
		var b: Dictionary = Officers.get_state(partner)
		if a.get("city", "") != b.get("city", ""):
			continue
		if bool(cfg("children", "require_opposite_gender", true)) and a.get("gender", "") == b.get("gender", ""):
			continue
		var ratio: float = cfg("children", "max_parent_age_ratio", 0.6)
		if int(a["age"]) >= lifespan(id) * ratio or int(b["age"]) >= lifespan(partner) * ratio:
			continue
		var fert: float = minf(float(DataDB.get_row("races", a["race"]).get("fertility", 0.2)), float(DataDB.get_row("races", b["race"]).get("fertility", 0.2)))
		if RNG.chance(fert):
			var child: String = make_child(id, partner)
			log_line(GameAction.msg("FAMILY_BIRTH", [Officers.display_name(id), Officers.display_name(partner), Officers.race_label(child)]))
			if GameState.player_id in [id, partner]:
				GameState.flags["pending_naming"] = child   # 화면이 이름을 묻는다


## 아이 만들기: 종족은 부모 한쪽을 50:50 (혼혈 없음), 능력은 부모 평균과 무작위 반반 + 자기 종족 보정
static func make_child(p1: String, p2: String) -> String:
	var a: Dictionary = Officers.get_state(p1)
	var b: Dictionary = Officers.get_state(p2)
	var from_a: bool = RNG.chance(0.5)
	var race_id: String = a["race"] if from_a else b["race"]
	var variant: String = (a if from_a else b).get("variant", "")
	var race: Dictionary = DataDB.get_row("races", race_id)
	var w: float = cfg("children", "parent_weight", 0.5)
	var stats: Dictionary = {}
	var pot: Dictionary = {}
	for key: String in Officers.stat_keys():
		var avg: float = (Officers.base_stat(p1, key) + Officers.base_stat(p2, key)) / 2.0
		var rnd: float = RNG.randi_range(int(cfg("children", "base_min", 20)), int(cfg("children", "base_max", 60)))
		stats[key] = Officers.clamp_stat(int(avg * w + rnd * (1.0 - w)) + int(race.get("stat_mod", {}).get(key, 0)))
		pot[key] = Officers.clamp_stat(int(stats[key]) + RNG.randi_range(int(cfg("children", "potential_bonus_min", 10)), int(cfg("children", "potential_bonus_max", 30))))
	var skills: Array = []
	for skill: String in a.get("skills", []) + b.get("skills", []):
		if not skills.has(skill) and RNG.chance(float(cfg("children", "skill_chance", 0.2))):
			skills.append(skill)
	var id: String = "child_%d" % (int(GameState.flags.get("child_count", 0)) + 1)
	GameState.flags["child_count"] = int(GameState.flags.get("child_count", 0)) + 1
	var gender: String = "m" if RNG.chance(0.5) else "f"
	var state: Dictionary = Officers.state_from_data({
		"id": id, "race": race_id, "gender": gender, "age": 0, "nation": a.get("nation", ""), "city": a.get("city", ""),
		"rank": "none", "stats": stats, "potential": pot, "skills": skills, "skill_levels": SkillLevels.starting_levels(skills), "unit_type": a.get("unit_type", "infantry"),
	})
	state["name"] = OfficerGen._make_name(race_id, gender)
	state["variant"] = variant if race_id == "elf" else ""
	state["minor"] = true
	state["parents"] = [p1, p2]
	state["sprite_id"] = Portraits.pick(race_id, state["variant"], gender)
	GameState.officers[id] = state
	for parent: String in [p1, p2]:
		Relationship.add_tag(parent, id, "family")
		Relationship.add(parent, id, 50)
	return id


# ── 승계 (GDD §5) ───────────────────────────────

## 후계자: 성인 자녀(나이 많은 순) → 배우자 → 맹우
static func heir_of(id: String) -> String:
	var kids: Array = children(id).filter(func(c: String) -> bool: return Officers.is_active(c))
	kids.sort_custom(func(x: String, y: String) -> bool: return int(Officers.get_state(x)["age"]) > int(Officers.get_state(y)["age"]))
	if not kids.is_empty():
		return kids[0]
	var sp: String = spouse(id)
	if sp != "" and Officers.is_active(sp):
		return sp
	for other: String in Relationship.with_tag(id, "sworn"):
		if Officers.is_active(other):
			return other
	return ""


## 주인공이 죽었다: 후계자가 이어받거나, 없으면 게임 오버
static func succeed(cause: String) -> void:
	var old: String = GameState.player_id
	var heir: String = heir_of(old)
	var o: Dictionary = Officers.get_state(old)
	if heir == "":
		GameState.flags["game_over"] = {"name": Officers.display_name(old), "cause": cause, "year": TimeManager.year, "month": TimeManager.month,
			"rank_key": Officers.rank_row(old).get("name_key", ""), "fame": int(o.get("fame", 0))}
		SaveManager.game_in_progress = false
		return
	var h: Dictionary = Officers.get_state(heir)
	# 물려받는 것: 금 전부, 명성 일부, 동료(후계자 자신 제외), 고용 부대, 용병단·계약, 평판
	h["gold"] = int(h.get("gold", 0)) + int(o.get("gold", 0))
	h["fame"] = int(h.get("fame", 0)) + int(int(o.get("fame", 0)) * float(cfg("death", "fame_inherit", 0.5)))
	for key: String in ["hired", "company", "contract", "reputation", "quests"]:
		if o.has(key) and not h.has(key):
			h[key] = o[key]
	h["perks"] = h.get("perks", [])
	h.erase("leader")
	var comps: Array = []
	for c: String in Career.companions(old):
		if c != heir:
			comps.append(c)
			Officers.get_state(c)["leader"] = heir
	h["companions"] = comps
	if h.get("rank", "none") == "none":
		h["rank"] = "merc_rookie"
	h["ap"] = Officers.max_ap(heir)
	GameState.player_id = heir
	GameState.flags["succession"] = {"from": Officers.display_name(old), "to": Officers.display_name(heir), "cause": cause}
	log_line(GameAction.msg("FAMILY_SUCCESSION", [Officers.display_name(heir), Officers.display_name(old)]))


## NPC끼리의 혼인 (세대교체): 같은 도시의 미혼 성인 한 쌍
static func _npc_marriages() -> void:
	var chance: float = cfg("children", "npc_marriage_chance", 0.04)
	var opposite: bool = cfg("children", "require_opposite_gender", true)
	for id: String in GameState.officers.keys():
		if id == GameState.player_id or not is_single_adult(id) or not RNG.chance(chance):
			continue
		var s: Dictionary = Officers.get_state(id)
		for other: String in Officers.in_city(s.get("city", ""), id):
			if other == GameState.player_id or not is_single_adult(other):
				continue
			if opposite and Officers.get_state(other).get("gender", "") == s.get("gender", ""):
				continue
			marry(id, other)
			log_line(GameAction.msg("FAMILY_NPC_MARRIED", [Officers.display_name(id), Officers.display_name(other)]))
			break
