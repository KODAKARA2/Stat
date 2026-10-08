class_name BattleAI
extends RefCounted
## 전투 AI: 갈 수 있는 칸마다 "여기서 누구를 치면 얼마나 좋은가"를 점수로 매겨 가장 좋은 수를 고른다.
## 칠 상대가 없으면 가장 가까운 적에게 다가간다. 적 부대와 (자동 시험의) 아군 부대가 같이 쓴다.
##
## 계획: {"move": 칸, "action": "attack"/"skill"/"wait", "target": BattleUnit, "skill": 특기 행, "cell": 전법 칸}

const KILL_BONUS: float = 150.0
const LEADER_BONUS: float = 80.0


static func plan(state: BattleState, unit: BattleUnit) -> Dictionary:
	var best: Dictionary = {"move": unit.cell, "action": "wait", "score": -INF}
	var origin: Vector2i = unit.cell
	var spots: Dictionary = BattleRules.reachable(state, unit)
	for dest: Vector2i in spots:
		unit.cell = dest   # 잠깐 옮겨 놓고 계산
		var stay_bonus: float = (1.0 - float(state.terrain_row(dest).get("defense", 1.0))) * 60.0
		for target: BattleUnit in BattleRules.attack_targets(state, unit, dest):
			var score: float = _attack_score(state, unit, target, 1.0, "", true) + stay_bonus
			if score > best["score"]:
				best = {"move": dest, "action": "attack", "target": target, "score": score}
		for gate: Vector2i in BattleRules.gate_targets(state, unit, dest):
			var dmg: int = BattleRules.gate_damage(unit, false)
			var gscore: float = dmg * 0.6 + (KILL_BONUS if dmg >= int(state.gate_hp[gate]) else 0.0) + stay_bonus
			if gscore > best["score"]:
				best = {"move": dest, "action": "gate", "cell": gate, "score": gscore}
		for skill: Dictionary in unit.battle_skills():
			if not BattleRules.can_use(unit, skill):
				continue
			for cell: Vector2i in BattleRules.skill_cells(state, unit, skill):
				var score: float = _skill_score(state, unit, skill, cell) + stay_bonus
				if score > best["score"]:
					best = {"move": dest, "action": "skill", "skill": skill, "cell": cell, "score": score}
	unit.cell = origin
	if best["action"] == "wait":
		best["move"] = _approach(state, unit, spots)
	return best


## 계획대로 움직이고 행동한다(애니메이션 없이). 행동 결과를 돌려준다.
static func execute(state: BattleState, unit: BattleUnit, p: Dictionary) -> Dictionary:
	BattleRules.move_unit(state, unit, p["move"])
	match p["action"]:
		"attack":
			return BattleRules.attack(state, unit, p["target"])
		"skill":
			return BattleRules.use_skill(state, unit, p["skill"], p["cell"])
		"gate":
			return BattleRules.attack_gate(state, unit, p["cell"])
	unit.acted = true
	return {}


static func _attack_score(state: BattleState, unit: BattleUnit, target: BattleUnit, power: float, kind: String, counter: bool) -> float:
	var dmg: int = BattleRules.damage(state, unit, target, power, kind, false)
	var score: float = minf(dmg, target.troops)
	if dmg >= target.troops:
		score += KILL_BONUS
	if target.leader:
		score += LEADER_BONUS
	var melee: bool = unit.type_row().get("attack_stat", "melee") == "melee" and target.type_row().get("attack_stat", "melee") == "melee"
	if counter and melee and dmg < target.troops and BattleRules.distance(unit.cell, target.cell) == 1:
		score -= BattleRules.damage(state, target, unit, DataDB.balance("battle.counter_ratio", 0.5), "", false) * 0.8
	return score


static func _skill_score(state: BattleState, unit: BattleUnit, skill: Dictionary, cell: Vector2i) -> float:
	var b: Dictionary = skill["battle"]
	var cost_penalty: float = float(b.get("sp", 0)) * 0.5   # 기력은 아껴 쓴다
	match b.get("target", "enemy"):
		"enemy":
			return _attack_score(state, unit, state.unit_at(cell), float(b.get("power", 1.0)), b.get("attack", ""), not b.get("no_counter", false)) - cost_penalty
		"area":
			var score: float = 0.0
			var hits: int = 0
			for c: Vector2i in BattleRules.area_cells(state, cell, int(b.get("radius", 1))):
				var t: BattleUnit = state.unit_at(c)
				if t and t.team != unit.team:
					score += _attack_score(state, unit, t, float(b.get("power", 1.0)), b.get("attack", ""), false)
					hits += 1
			return score - cost_penalty if hits >= 2 else -INF   # 한 명만 맞히려면 그냥 공격이 낫다
		"ally":
			var t: BattleUnit = state.unit_at(cell)
			if t.troops > t.max_troops * 0.6:
				return -INF
			return minf(b.get("heal_base", 60) + unit.mag * float(b.get("heal_per_mag", 2.0)), t.max_troops - t.troops) * 1.2 - cost_penalty
		"self":
			return -INF if BattleRules.attack_targets(state, unit, unit.cell).is_empty() else 30.0 - cost_penalty
	return -INF


## 지금 편의 남은 부대를 전부 AI로 움직인다 (적 차례 / 자동 진행 / 시험용)
static func run_phase(state: BattleState) -> void:
	for unit: BattleUnit in state.living(state.phase):
		if state.check_end() != "":
			return
		if not unit.done():
			execute(state, unit, plan(state, unit))


## 끝날 때까지 양쪽 모두 AI로 (밸런스 시험용)
static func run_to_end(state: BattleState) -> String:
	while state.check_end() == "":
		run_phase(state)
		if state.check_end() == "":
			state.end_phase()
	return state.result


## 칠 상대가 없을 때 다가갈 곳: 가까운 적 → (성을 치는 편이면) 성내 거점 → 성문 앞.
## 길 위에서 이번에 갈 수 있는 가장 앞 칸으로 간다.
static func _approach(state: BattleState, unit: BattleUnit, spots: Dictionary) -> Vector2i:
	var goals: Array[Vector2i] = []
	var foes: Array[BattleUnit] = state.living(BattleState.other(unit.team))
	foes.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool:
		return BattleRules.distance(unit.cell, a.cell) < BattleRules.distance(unit.cell, b.cell))
	for foe: BattleUnit in foes:
		goals.append(foe.cell)
	if unit.team == state.attacker_team() and state.keep_cell.x >= 0:
		goals.append(state.keep_cell)
		for gate: Vector2i in state.gate_hp:
			if int(state.gate_hp[gate]) > 0:
				for d: Vector2i in BattleRules.DIRS:
					if BattleRules.move_cost(state, unit, gate + d) > 0:
						goals.append(gate + d)
	for goal: Vector2i in goals:
		var route: Array[Vector2i] = BattleRules.path(state, unit, goal)
		if route.size() < 2:
			continue
		var best: Vector2i = unit.cell
		for step: Vector2i in route:
			if spots.has(step):
				best = step
		return best
	return unit.cell
