class_name BattleSetup
extends RefCounted
## 토벌 의뢰 → 전투 한 판 준비: 지도 생성, 아군(주인공 + 길드 임시 용병), 적(몬스터 무리) 배치.


static func from_quest(quest: Dictionary, leader_id: String) -> BattleState:
	var state: BattleState = BattleState.new()
	state.width = int(DataDB.balance("battle.grid_width", 7))
	state.height = int(DataDB.balance("battle.grid_height", 10))
	state.quest = quest
	state.city_id = quest.get("city", "")
	state.turn_limit = int(Guild.cfg("turn_limit", 20))
	_make_terrain(state, DataDB.get_row("cities", state.city_id).get("terrain", "plains"))

	var party: Dictionary = Guild.cfg("parties", {}).get(str(int(quest["tier"])), {})
	# 아군: 주인공(총대장) + 임시 용병
	var allies: Array[BattleUnit] = [officer_unit(leader_id, "ally")]
	allies[0].leader = true
	var helper_types: Array = Guild.cfg("helper_types", [])
	for i: int in int(party.get("helpers", 1)):
		allies.append(helper_unit(helper_types[i % helper_types.size()], i + 1))
	# 주인공이 고용한 부대
	var hired: Array = Guild.hired(leader_id)
	for i: int in hired.size():
		allies.append(hired_unit(hired[i], i))
	allies.append_array(companion_units(leader_id))
	_place(state, allies, state.height - 1, -1)

	# 적: 본대 몬스터 + 호위. 본대 첫 마리가 우두머리
	var enemies: Array[BattleUnit] = []
	var main: Dictionary = DataDB.get_row("monsters", quest["monster"])
	for i: int in int(party.get("main", 1)):
		enemies.append(monster_unit(main))
	enemies[0].leader = true
	var escort_tier: int = int(party.get("escort_tier", 0))
	if escort_tier > 0:
		var terrain: String = DataDB.get_row("cities", state.city_id).get("terrain", "plains")
		for i: int in int(party.get("escort", 0)):
			enemies.append(monster_unit(RNG.pick(Guild.monsters_for(terrain, escort_tier))))
	# 주인공 쪽 동료·고용 부대가 많으면 적 호위도 늘어난다 (같은 단계)
	var extra: int = int((Guild.hired(leader_id).size() + Career.companions(leader_id).size()) * float(Guild.cfg("party_scale", 0.5)))
	if extra > 0:
		var terrain2: String = DataDB.get_row("cities", state.city_id).get("terrain", "plains")
		for i: int in extra:
			enemies.append(monster_unit(RNG.pick(Guild.monsters_for(terrain2, int(quest["tier"])))))
	_place(state, enemies, 0, 1)
	state.begin_phase("ally")
	return state


static func officer_unit(officer_id: String, team: String) -> BattleUnit:
	var s: Dictionary = Officers.get_state(officer_id)
	var u: BattleUnit = BattleUnit.new()
	u.team = team
	u.officer_id = officer_id
	u.name = Officers.display_name(officer_id)
	u.short = u.name.left(1)
	u.unit_type = s.get("unit_type", "infantry")
	u.max_troops = Officers.max_troops(officer_id)
	u.troops = clampi(int(s.get("troops", u.max_troops)), 1, u.max_troops)
	u.str_ = Officers.stat(officer_id, "str")
	u.lead = Officers.stat(officer_id, "lead")
	u.mag = Officers.stat(officer_id, "mag")
	u.sp = int(s.get("energy", 100))
	u.skills = s.get("skills", []).duplicate()
	u.traits = DataDB.get_row("races", s.get("race", "")).get("traits", []).duplicate()
	u.sprite_id = s.get("sprite_id", "")
	return u


static func helper_unit(row: Dictionary, number: int) -> BattleUnit:
	var u: BattleUnit = BattleUnit.new()
	u.team = "ally"
	u.source_id = row["id"]
	u.name = TranslationServer.translate(row["name_key"]) % number
	u.short = TranslationServer.translate(DataDB.get_row("unit_types", row["unit_type"]).get("name_key", "?")).left(1)
	u.unit_type = row["unit_type"]
	u.troops = int(row["troops"])
	u.max_troops = u.troops
	u.str_ = int(row["str"])
	u.lead = int(row["lead"])
	u.mag = int(row.get("mag", 0))
	u.sp = 0
	u.sprite_id = "unit_" + String(row["unit_type"])
	return u


static func monster_unit(row: Dictionary) -> BattleUnit:
	var u: BattleUnit = BattleUnit.new()
	u.team = "enemy"
	u.source_id = row["id"]
	u.name = TranslationServer.translate(row["name_key"])
	u.short = u.name.left(1)
	u.unit_type = row.get("unit_type", "infantry")
	u.troops = int(row["troops"])
	u.max_troops = u.troops
	u.str_ = int(row["str"])
	u.lead = int(row["lead"])
	u.mag = int(row.get("mag", 0))
	u.traits = row.get("traits", []).duplicate()
	u.sprite_id = row.get("sprite_id", "")
	return u


## 줄 하나에 가운데부터 좌우로 벌려 세운다. 줄이 차면 다음 줄(step 방향)로.
static func _place(state: BattleState, list: Array[BattleUnit], start_row: int, step: int) -> void:
	var order: Array[int] = []
	var mid: int = state.width / 2
	for i: int in state.width:
		order.append(mid + (i + 1) / 2 * (1 if i % 2 == 1 else -1))
	var row: int = start_row
	var col_index: int = 0
	for u: BattleUnit in list:
		while true:
			if col_index >= order.size():
				col_index = 0
				row += step
			var cell: Vector2i = Vector2i(order[col_index], row)
			col_index += 1
			if state.unit_at(cell) == null and BattleRules.move_cost(state, u, cell) > 0:
				u.cell = cell
				state.add_unit(u)
				break


static func _make_terrain(state: BattleState, city_terrain: String) -> void:
	var rules: Dictionary = DataDB.get_table("battle_maps")
	var weights: Dictionary = rules.get("by_city_terrain", {}).get(city_terrain, {})
	var spawn: int = int(rules.get("spawn_rows", 2))
	state.terrain.resize(state.width * state.height)
	for y: int in state.height:
		for x: int in state.width:
			var t: String = "plains"
			var roll: float = RNG.randf()
			if roll < float(weights.get("forest", 0.1)):
				t = "forest"
			elif roll < float(weights.get("forest", 0.1)) + float(weights.get("hill", 0.1)):
				t = "hill"
			state.set_terrain(Vector2i(x, y), t)
	# 강: 가운데쯤을 가로지르고, 건널 수 있는 여울(평지) 몇 칸
	if RNG.chance(float(weights.get("river_chance", 0.3))):
		var ry: int = RNG.randi_range(int(rules.get("river_min_row", 3)), int(rules.get("river_max_row", 6)))
		var fords: Array = []
		while fords.size() < int(rules.get("river_fords", 2)):
			var fx: int = RNG.randi_range(0, state.width - 1)
			if not fords.has(fx):
				fords.append(fx)
		for x: int in state.width:
			state.set_terrain(Vector2i(x, ry), "plains" if fords.has(x) else "river")
	# 출발 줄은 강이 없게
	for y: int in state.height:
		if y < spawn or y >= state.height - spawn:
			for x: int in state.width:
				if state.terrain_at(Vector2i(x, y)) == "river":
					state.set_terrain(Vector2i(x, y), "plains")


## 주인공이 길드에서 고용한 부대 (병력은 지난 전투에서 남은 만큼)
static func hired_unit(entry: Dictionary, index: int) -> BattleUnit:
	var row: Dictionary = Guild.helper_type(entry["type"])
	var u: BattleUnit = helper_unit(row, index + 1)
	u.name = Guild.hired_name(entry["type"], index + 1)
	u.troops = maxi(1, int(entry["troops"]))
	u.hire_index = index
	return u


# ── 참전 의뢰: 공성전 (M4) ───────────────────────

## 참전 의뢰 → 공성전. 공격측이면 위쪽에 적의 성벽, 방어측이면 아래쪽에 우리 성벽.
static func from_war_quest(quest: Dictionary, leader_id: String) -> BattleState:
	var plan: Dictionary = WarSystem.find_plan(quest.get("plan", ""))
	var state: BattleState = BattleState.new()
	state.width = int(DataDB.balance("battle.grid_width", 7))
	state.height = int(DataDB.balance("battle.grid_height", 10))
	state.quest = quest
	state.city_id = quest["target"]
	var attack: bool = quest["attack"]
	state.mode = "siege_attack" if attack else "siege_defend"
	state.turn_limit = int(Guild.war_cfg("attack_turn_limit" if attack else "defend_turn_limit", 20))
	_make_terrain(state, DataDB.get_row("cities", state.city_id).get("terrain", "plains"))
	_make_walls(state, 1 if attack else state.height - 2, 0 if attack else state.height - 1)

	var side: String = quest["side"]
	var enemy: String = quest["enemy"]
	var my_cmd: String = plan.get("commander" if attack else "def_commander", "")
	var foe_cmd: String = plan.get("def_commander" if attack else "commander", "")
	var regulars: int = int(Guild.war_cfg("regulars", 2))
	var my_regulars: int = regulars
	if quest.get("type", "") == "conquest":
		# 용병단 점령전: 우리 편 정규군·지휘관 없이 용병단만. 수비 지휘관은 그 도시에 있는 장수.
		my_regulars = 0
		foe_cmd = NationAI.pick_commander(enemy, state.city_id)
		if foe_cmd != "" and Officers.get_state(foe_cmd).get("city", "") != state.city_id:
			foe_cmd = ""

	var allies: Array[BattleUnit] = [officer_unit(leader_id, "ally")]
	allies[0].leader = true
	var hired: Array = Guild.hired(leader_id)
	for i: int in hired.size():
		allies.append(hired_unit(hired[i], i))
	allies.append_array(companion_units(leader_id))
	if my_cmd != "" and Officers.is_active(my_cmd):
		allies.append(officer_unit(my_cmd, "ally"))
	for i: int in my_regulars:
		allies.append(regular_unit(side, "ally", i, attack))

	var enemies: Array[BattleUnit] = []
	if foe_cmd != "" and Officers.is_active(foe_cmd):
		enemies.append(officer_unit(foe_cmd, "enemy"))
	for i: int in regulars + 1:
		enemies.append(regular_unit(enemy, "enemy", i, not attack))
	enemies[0].leader = true

	if attack:
		_place(state, allies, state.height - 1, -1)
		_place(state, enemies, 0, 1)        # 성 안(0줄)부터, 차면 성벽 앞으로
	else:
		_place(state, allies, state.height - 3, -1)   # 성벽 바로 앞에서 성문을 지킨다
		_place(state, enemies, 0, 1)
	state.begin_phase("ally")
	return state


## 성벽 한 줄(가운데는 성문) + 성 안 거점
static func _make_walls(state: BattleState, wall_row: int, inner_row: int) -> void:
	var gate_x: int = state.width / 2
	var hp: int = int(DataDB.get_row("terrain", "gate").get("hp", 500))
	for x: int in state.width:
		state.set_terrain(Vector2i(x, wall_row), "gate" if x == gate_x else "wall")
		state.set_terrain(Vector2i(x, inner_row), "plains")
	state.gate_hp[Vector2i(gate_x, wall_row)] = hp
	state.keep_cell = Vector2i(gate_x, inner_row)


## 나라 정규군 부대. 그 나라 주력 병종(nations.json main_units)을 돌아가며 쓰고, 성을 치는 쪽은 공성병 1부대를 꼭 넣는다.
static func regular_unit(nation_id: String, team: String, index: int, attacking: bool) -> BattleUnit:
	var rows: Array = DataDB.get_table("war").get("regular_units", [])
	var types: Array = Nations.row(nation_id).get("main_units", ["infantry"])
	var unit_type: String = "siege" if attacking and index == 0 else types[index % types.size()]
	var row: Dictionary = rows[0]
	for r: Dictionary in rows:
		if r["unit_type"] == unit_type:
			row = r
	var u: BattleUnit = BattleUnit.new()
	u.team = team
	u.source_id = row["id"]
	u.name = GameAction.msg("REGULAR_NAME", [Diplomacy.nation_name(nation_id).split(" ")[0],
		TranslationServer.translate(DataDB.get_row("unit_types", unit_type).get("name_key", "")), index + 1])
	u.short = TranslationServer.translate(DataDB.get_row("unit_types", unit_type).get("name_key", "?")).left(1)
	u.unit_type = unit_type
	u.troops = int(row["troops"])
	u.max_troops = u.troops
	u.str_ = int(row["str"])
	u.lead = int(row["lead"])
	u.mag = int(row.get("mag", 0))
	u.sprite_id = "unit_" + unit_type
	return u


## 주인공의 동료 장수 (부상자·병력 없는 사람 제외)
static func companion_units(leader_id: String) -> Array[BattleUnit]:
	var list: Array[BattleUnit] = []
	for id: String in Career.companions(leader_id):
		var s: Dictionary = Officers.get_state(id)
		if int(s.get("injury", 0)) <= 0 and int(s.get("troops", 0)) > 0:
			list.append(officer_unit(id, "ally"))
	return list
