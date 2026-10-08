class_name BattleState
extends RefCounted
## 전투 한 판의 상태: 지형 격자, 부대들, 턴. 그리기는 ui/battle이 하고 여기는 숫자만 안다.

var width: int = 7
var height: int = 10
var terrain: PackedStringArray = []   # y * width + x
var units: Array[BattleUnit] = []
var turn: int = 1
var phase: String = "ally"            # 지금 움직이는 편
var turn_limit: int = 20
var quest: Dictionary = {}
var city_id: String = ""
var result: String = ""               # "" 진행 중 / "win" / "lose"
var mode: String = "field"            # field(들판) / siege_attack(우리가 성을 친다) / siege_defend(우리가 성을 지킨다)
var keep_cell: Vector2i = Vector2i(-1, -1)   # 성내 거점: 공격측이 밟으면 점령
var gate_hp: Dictionary = {}          # 성문 칸 → 남은 내구도
var bonus_spent: int = 0              # 이번 전투에서 포상에 쓴 금
var _next_uid: int = 1


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func terrain_at(cell: Vector2i) -> String:
	return terrain[cell.y * width + cell.x] if in_bounds(cell) else "wall"


func set_terrain(cell: Vector2i, terrain_id: String) -> void:
	if in_bounds(cell):
		terrain[cell.y * width + cell.x] = terrain_id


func terrain_row(cell: Vector2i) -> Dictionary:
	return DataDB.get_row("terrain", terrain_at(cell))


func add_unit(unit: BattleUnit) -> BattleUnit:
	unit.uid = _next_uid
	_next_uid += 1
	unit.start_troops = unit.troops
	units.append(unit)
	return unit


func unit_at(cell: Vector2i) -> BattleUnit:
	for u: BattleUnit in units:
		if u.alive() and u.cell == cell:
			return u
	return null


func living(team: String) -> Array[BattleUnit]:
	var list: Array[BattleUnit] = []
	for u: BattleUnit in units:
		if u.alive() and u.team == team:
			list.append(u)
	return list


func leader_of(team: String) -> BattleUnit:
	for u: BattleUnit in units:
		if u.team == team and u.leader:
			return u
	return null


static func other(team: String) -> String:
	return "enemy" if team == "ally" else "ally"


## 승패 판정 (GDD §8.3): 총대장 격파 또는 전멸. 제한 턴을 넘기면 몬스터가 달아나 실패.
func check_end() -> String:
	if result != "":
		return result
	var ally_leader: BattleUnit = leader_of("ally")
	var enemy_leader: BattleUnit = leader_of("enemy")
	var on_keep: BattleUnit = unit_at(keep_cell) if keep_cell.x >= 0 else null
	if living("ally").is_empty() or (ally_leader and not ally_leader.alive()):
		result = "lose"
	elif living("enemy").is_empty() or (enemy_leader and not enemy_leader.alive()):
		result = "win"
	elif on_keep and on_keep.team == attacker_team():
		result = "win" if attacker_team() == "ally" else "lose"   # 성내 거점 점령
	elif turn > turn_limit:
		result = "win" if mode == "siege_defend" else "lose"      # 성을 지키는 쪽은 버티면 이긴다
	return result


## 공성전에서 성을 치는 편
func attacker_team() -> String:
	return "enemy" if mode == "siege_defend" else "ally"


## 한 편의 차례 시작: 행동 표시와 방어 버프를 초기화
func begin_phase(team: String) -> void:
	phase = team
	for u: BattleUnit in living(team):
		u.moved = false
		u.acted = false
		u.guard = 1.0


func phase_done() -> bool:
	for u: BattleUnit in living(phase):
		if not u.acted:
			return false
	return true


## 아군 → 적 → (턴 +1) → 아군 ...
func end_phase() -> void:
	if phase == "enemy":
		turn += 1
	begin_phase(other(phase))
