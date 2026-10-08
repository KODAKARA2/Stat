class_name BattleRules
extends RefCounted
## 전투 규칙 (GDD §8): 이동 범위, 사거리, 피해 공식, 공격·반격, 전법.
## 플레이어 조작·적 AI·자동 시험이 전부 이 함수들을 쓴다.

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


# ── 이동 ────────────────────────────────────────

## 그 칸에 들어가는 데 드는 이동력. 못 들어가면 -1. 나는 부대는 지형을 무시한다.
static func move_cost(state: BattleState, unit: BattleUnit, cell: Vector2i) -> int:
	if not state.in_bounds(cell):
		return -1
	var cost: int = int(state.terrain_row(cell).get("move", 1))
	if cost <= 0:
		return -1
	return 1 if unit.flying() else cost


## 이번에 갈 수 있는 칸 → 드는 이동력. 아군 칸은 지나갈 수 있지만 멈출 수 없고, 적 칸은 막힌다.
static func reachable(state: BattleState, unit: BattleUnit) -> Dictionary:
	var best: Dictionary = {unit.cell: 0}
	var frontier: Array[Vector2i] = [unit.cell]
	var budget: int = unit.move_points()
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_front()
		for d: Vector2i in DIRS:
			var nxt: Vector2i = cur + d
			var step: int = move_cost(state, unit, nxt)
			if step < 0:
				continue
			var other: BattleUnit = state.unit_at(nxt)
			if other and other.team != unit.team:
				continue
			var total: int = int(best[cur]) + step
			if total <= budget and (not best.has(nxt) or total < int(best[nxt])):
				best[nxt] = total
				frontier.append(nxt)
	var result: Dictionary = {}
	for cell: Vector2i in best:
		var occupant: BattleUnit = state.unit_at(cell)
		if occupant == null or occupant == unit:
			result[cell] = best[cell]
	return result


## Godot의 AStarGrid2D로 실제 걸어갈 길을 구한다 (출발 칸 포함). 길이 없으면 빈 배열.
static func path(state: BattleState, unit: BattleUnit, to: Vector2i) -> Array[Vector2i]:
	var grid: AStarGrid2D = AStarGrid2D.new()
	grid.region = Rect2i(0, 0, state.width, state.height)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.update()
	for y: int in state.height:
		for x: int in state.width:
			var cell: Vector2i = Vector2i(x, y)
			var cost: int = move_cost(state, unit, cell)
			var occupant: BattleUnit = state.unit_at(cell)
			if cost < 0 or (occupant and occupant.team != unit.team and cell != to):
				grid.set_point_solid(cell, true)
			else:
				grid.set_point_weight_scale(cell, cost)
	var result: Array[Vector2i] = []
	for p: Vector2i in grid.get_id_path(unit.cell, to):
		result.append(p)
	return result


static func move_unit(state: BattleState, unit: BattleUnit, to: Vector2i) -> void:
	if state.unit_at(to) == null or state.unit_at(to) == unit:
		unit.cell = to
	unit.moved = true


# ── 사거리와 대상 ────────────────────────────────

static func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## 그 칸에 섰을 때 사거리. 언덕 위 원거리 부대는 +1
static func attack_range(state: BattleState, unit: BattleUnit, from: Vector2i) -> Vector2i:
	var row: Dictionary = unit.type_row()
	var rmin: int = int(row.get("range_min", 1))
	var rmax: int = int(row.get("range_max", 1))
	if row.get("attack_stat", "melee") != "melee":
		rmax += int(state.terrain_row(from).get("ranged_bonus", 0))
	return Vector2i(rmin, rmax)


static func cells_in_range(state: BattleState, center: Vector2i, rmin: int, rmax: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y: int in range(center.y - rmax, center.y + rmax + 1):
		for x: int in range(center.x - rmax, center.x + rmax + 1):
			var c: Vector2i = Vector2i(x, y)
			var d: int = distance(center, c)
			if state.in_bounds(c) and d >= rmin and d <= rmax:
				cells.append(c)
	return cells


static func attack_targets(state: BattleState, unit: BattleUnit, from: Vector2i) -> Array[BattleUnit]:
	var r: Vector2i = attack_range(state, unit, from)
	var list: Array[BattleUnit] = []
	for c: Vector2i in cells_in_range(state, from, r.x, r.y):
		var u: BattleUnit = state.unit_at(c)
		if u and u.team != unit.team:
			list.append(u)
	return list


# ── 피해 ────────────────────────────────────────

## 피해 = 병력 × troop_factor × (공격능력 + 보정) / (방어측 통솔 + 보정) × 상성 × 지형 × 방어버프 × 난수 (GDD §8.4)
## randomize = false면 난수 없이 평균값 (미리보기·AI용)
static func damage(state: BattleState, attacker: BattleUnit, defender: BattleUnit, power: float = 1.0,
		kind: String = "", randomize: bool = true) -> int:
	var tf: float = DataDB.balance("battle.damage.troop_factor", 0.25)
	var off: float = DataDB.balance("battle.damage.stat_offset", 50)
	var value: float = attacker.troops * tf * (attacker.attack_power(kind) + off) / (defender.lead + off)
	var type_row: Dictionary = attacker.type_row()
	if not type_row.get("fixed_damage", false):
		value *= float(type_row.get("counters", {}).get(defender.unit_type, 1.0))
	value *= float(state.terrain_row(defender.cell).get("defense", 1.0))
	value *= defender.guard * power * morale_mult(attacker) * taken_mult(defender)
	if randomize:
		value *= RNG.randf_range(DataDB.balance("battle.damage.random_min", 0.9), DataDB.balance("battle.damage.random_max", 1.1))
	return 0 if morale_mult(attacker) <= 0.0 else maxi(1, int(round(value)))   # 사기 0이면 피해도 0


## 사기에 따른 피해 배율: 사기 100 = 1.0, 사기 0 = min_mult
static func morale_mult(unit: BattleUnit) -> float:
	var lo: float = DataDB.balance("battle.morale.min_mult", 0.5)
	return lo + (1.0 - lo) * clampf(unit.morale / 100.0, 0.0, 1.0)


## 사기에 따른 받는 피해 배율: 사기 100 = 1.0, 1 떨어질 때마다 +1% (사기 0 = 2.0)
## 맞은 쪽 사기 하락 (기획 2026-10-08): 기본 hit_base + (때린 쪽 사기 - 맞은 쪽 사기, 양수일 때) × gap_factor
## 예) 100이 99를 치면 1+1 = 2 → 97, 100이 90을 치면 1+10 = 11 → 79. 사기가 밀리기 시작하면 걷잡을 수 없다.
## + 잃은 병력 비율 × loss_scale (큰 피해를 입으면 그만큼 더 흔들린다)
static func morale_loss(attacker: BattleUnit, defender: BattleUnit, dealt: int = 0) -> int:
	var gap: int = maxi(0, attacker.morale - defender.morale)
	var loss: float = float(DataDB.balance("battle.morale.hit_base", 1)) + gap * float(DataDB.balance("battle.morale.gap_factor", 1.0))
	loss += float(dealt) / maxf(defender.max_troops, 1) * float(DataDB.balance("battle.morale.loss_scale", 0))
	return int(round(loss))


static func taken_mult(unit: BattleUnit) -> float:
	return 1.0 + (100 - clampi(unit.morale, 0, 100)) * float(DataDB.balance("battle.morale.taken_per_point", 0.01))


## 병력을 깎고 사기를 반영한다. 궤멸시키면 같은 편 사기 하락, 공격한 쪽 사기 상승.
static func _hit(state: BattleState, attacker: BattleUnit, defender: BattleUnit, amount: int) -> int:
	var dealt: int = mini(amount, defender.troops)
	defender.troops -= dealt
	if dealt > 0:
		defender.morale = clampi(defender.morale - morale_loss(attacker, defender, dealt), 0, 100)
	if not defender.alive():
		for u: BattleUnit in state.living(defender.team):
			u.morale = clampi(u.morale - int(DataDB.balance("battle.morale.ally_down", 10)), 0, 100)
		attacker.morale = clampi(attacker.morale + int(DataDB.balance("battle.morale.kill_bonus", 10)), 0, 100)
	return dealt


## 일반 공격. 근접끼리 붙으면 살아남은 쪽이 반격한다.
## 돌려주는 값: {"damage", "killed", "counter", "counter_killed"}
static func attack(state: BattleState, attacker: BattleUnit, defender: BattleUnit,
		power: float = 1.0, kind: String = "", allow_counter: bool = true) -> Dictionary:
	var dealt: int = _hit(state, attacker, defender, damage(state, attacker, defender, power, kind))
	var result: Dictionary = {"damage": dealt, "killed": not defender.alive(), "counter": 0, "counter_killed": false}
	var melee_attack: bool = (kind if kind != "" else attacker.type_row().get("attack_stat", "melee")) == "melee"
	var melee_defender: bool = defender.type_row().get("attack_stat", "melee") == "melee"
	if allow_counter and defender.alive() and melee_attack and melee_defender and distance(attacker.cell, defender.cell) == 1:
		var ratio: float = DataDB.balance("battle.counter_ratio", 0.5)
		result["counter"] = _hit(state, defender, attacker, damage(state, defender, attacker, ratio))
		result["counter_killed"] = not attacker.alive()
	attacker.acted = true
	return result


# ── 전법 ────────────────────────────────────────

static func can_use(unit: BattleUnit, skill: Dictionary) -> bool:
	return unit.sp >= int(skill["battle"].get("sp", 0))


## 전법을 쓸 수 있는 칸 목록
static func skill_cells(state: BattleState, unit: BattleUnit, skill: Dictionary) -> Array[Vector2i]:
	var b: Dictionary = skill["battle"]
	var cells: Array[Vector2i] = []
	match b.get("target", "enemy"):
		"self":
			cells.append(unit.cell)
		"enemy":
			for c: Vector2i in cells_in_range(state, unit.cell, int(b.get("range_min", 1)), int(b.get("range_max", 1))):
				var u: BattleUnit = state.unit_at(c)
				if u and u.team != unit.team:
					cells.append(c)
		"ally":
			for c: Vector2i in cells_in_range(state, unit.cell, int(b.get("range_min", 0)), int(b.get("range_max", 1))):
				var u: BattleUnit = state.unit_at(c)
				if u and u.team == unit.team and u.troops < u.max_troops:
					cells.append(c)
		"area":
			cells = cells_in_range(state, unit.cell, int(b.get("range_min", 1)), int(b.get("range_max", 3)))
	return cells


static func area_cells(state: BattleState, center: Vector2i, radius: int) -> Array[Vector2i]:
	return cells_in_range(state, center, 0, radius)


## 전법 사용. 돌려주는 값: {"hits": [{"unit", "damage", "killed"}], "heals": [{"unit", "amount"}], "heal": 첫 회복, "guarded": [부대],
## "burned": [칸], "guard": bool, "level_up": 새 전법 레벨(오르지 않았으면 0)}. 레벨 3 축성·치료는 radius만큼 주변 아군까지.
static func use_skill(state: BattleState, unit: BattleUnit, skill: Dictionary, cell: Vector2i) -> Dictionary:
	var b: Dictionary = skill["battle"]
	var out: Dictionary = {"hits": [], "burned": []}
	unit.sp -= int(b.get("sp", 0))
	match b.get("target", "enemy"):
		"self":
			out["guarded"] = []
			for c: Vector2i in area_cells(state, unit.cell, int(b.get("radius", 0))):
				var ally: BattleUnit = state.unit_at(c)
				if ally and ally.team == unit.team:
					ally.guard = minf(ally.guard, float(b.get("guard", 0.6)))
					out["guarded"].append(ally)
			out["guard"] = true
		"enemy":
			var target: BattleUnit = state.unit_at(cell)
			var r: Dictionary = attack(state, unit, target, float(b.get("power", 1.0)), b.get("attack", ""), not b.get("no_counter", false))
			out["hits"].append({"unit": target, "damage": r["damage"], "killed": r["killed"]})
			out["counter"] = r["counter"]
		"ally":
			out["heals"] = []
			var base_amount: int = int(b.get("heal_base", 60) + unit.mag * float(b.get("heal_per_mag", 2.0)))
			for c: Vector2i in area_cells(state, cell, int(b.get("radius", 0))):
				var target: BattleUnit = state.unit_at(c)
				if target == null or target.team != unit.team or not target.alive():
					continue
				var amount: int = mini(base_amount, target.max_troops - target.troops)
				target.troops += amount
				if amount > 0 or c == cell:
					out["heals"].append({"unit": target, "amount": amount})
			if not out["heals"].is_empty():
				out["heal"] = out["heals"][0]
		"area":
			for c: Vector2i in area_cells(state, cell, int(b.get("radius", 1))):
				var target: BattleUnit = state.unit_at(c)
				if target and target.team != unit.team:
					var dealt: int = _hit(state, unit, target, damage(state, unit, target, float(b.get("power", 1.0)), b.get("attack", "")))
					out["hits"].append({"unit": target, "damage": dealt, "killed": not target.alive()})
				if b.get("burns", false):
					var burns_to: String = state.terrain_row(c).get("burns_to", "")
					if burns_to != "":
						state.set_terrain(c, burns_to)
						out["burned"].append(c)
	unit.acted = true
	out["level_up"] = SkillLevels.add_use(unit.officer_id, skill.get("id", "")) if unit.officer_id != "" else 0
	return out


# ── 공성: 성문 ──────────────────────────────────

## 그 칸에서 칠 수 있는 성문 칸 (성을 치는 편만)
static func gate_targets(state: BattleState, unit: BattleUnit, from: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if state.gate_hp.is_empty() or unit.team != state.attacker_team():
		return cells
	var r: Vector2i = attack_range(state, unit, from)
	for c: Vector2i in state.gate_hp:
		var d: int = distance(from, c)
		if int(state.gate_hp[c]) > 0 and d >= r.x and d <= r.y:
			cells.append(c)
	return cells


## 성문 피해: 방어 통솔 50 기준 공식 × 공성병 배율(structure_mult)
static func gate_damage(unit: BattleUnit, randomize: bool = true) -> int:
	var tf: float = DataDB.balance("battle.damage.troop_factor", 0.15)
	var off: float = DataDB.balance("battle.damage.stat_offset", 50)
	var value: float = unit.troops * tf * (unit.attack_power() + off) / (50.0 + off)
	value *= float(unit.type_row().get("structure_mult", 1.0)) * morale_mult(unit)
	if randomize:
		value *= RNG.randf_range(0.9, 1.1)
	return 0 if morale_mult(unit) <= 0.0 else maxi(1, int(round(value)))


## 성문 공격. 내구도가 0이 되면 무너져 지나갈 수 있는 땅이 된다. {"damage", "broken"}
static func attack_gate(state: BattleState, unit: BattleUnit, cell: Vector2i) -> Dictionary:
	var dmg: int = mini(gate_damage(unit), int(state.gate_hp[cell]))
	state.gate_hp[cell] = int(state.gate_hp[cell]) - dmg
	var broken: bool = int(state.gate_hp[cell]) <= 0
	if broken:
		state.set_terrain(cell, "rubble")
	unit.acted = true
	return {"damage": dmg, "broken": broken}


# ── 포상 (돈으로 사기를 산다) ───────────────────

static func bonus_cost(unit: BattleUnit) -> int:
	return maxi(int(DataDB.balance("battle.morale.bonus_min_cost", 10)), int(ceil(unit.troops * float(DataDB.balance("battle.morale.bonus_cost_per_troop", 0.1)))))


## 못 주면 사유 번역 키, 줄 수 있으면 "". 세 번째부터는 줄 수는 있지만 사기는 안 오른다.
static func bonus_check(state: BattleState, unit: BattleUnit) -> String:
	if unit.team != "ally" or not unit.alive():
		return "BONUS_FAIL_TARGET"
	if unit.morale >= 100:
		return "BONUS_FAIL_FULL"
	if int(GameState.player().get("gold", 0)) < bonus_cost(unit):
		return "ACT_FAIL_NO_GOLD"
	return ""


## 이번에 포상을 주면 오를 사기 (1번째 +20, 2번째 +10, 그 뒤 0)
static func bonus_gain(unit: BattleUnit) -> int:
	var steps: Array = DataDB.balance("battle.morale.bonus_steps", [20, 10])
	return int(steps[unit.bonus_count]) if unit.bonus_count < steps.size() else 0


## 주인공 금에서 내고 사기를 올린다. 실제로 오른 사기를 돌려준다.
static func give_bonus(state: BattleState, unit: BattleUnit) -> int:
	var cost: int = bonus_cost(unit)
	var p: Dictionary = GameState.player()
	p["gold"] = int(p["gold"]) - cost
	state.bonus_spent += cost
	var before: int = unit.morale
	unit.morale = mini(100, unit.morale + bonus_gain(unit))
	unit.bonus_count += 1
	return unit.morale - before
