class_name BattleUnit
extends RefCounted
## 전투 중의 부대 하나 = 장수(또는 몬스터·임시 용병) 1 + 병력 (GDD §8.2).
## 전투가 끝나면 BattleOutcome이 병력·기력을 원래 장수에게 돌려준다.

var uid: int = 0
var team: String = "ally"          # "ally" / "enemy"
var officer_id: String = ""        # 장수면 무장 id, 몬스터·임시 용병이면 ""
var source_id: String = ""         # 몬스터 id 또는 임시 용병 종류 id
var name: String = ""
var short: String = ""             # 말판에 찍을 한 글자
var unit_type: String = "infantry"
var troops: int = 0
var max_troops: int = 0
var str_: int = 0
var lead: int = 0
var mag: int = 0
var sp: int = 0                    # 기력: 전법에 쓴다
var max_sp: int = 100
var skills: Array = []
var traits: Array = []
var cell: Vector2i = Vector2i.ZERO
var moved: bool = false
var acted: bool = false
var leader: bool = false           # 총대장: 쓰러지면 그 편이 진다
var guard: float = 1.0             # 받는 피해 배율 (축성 등). 자기 차례가 오면 1로 돌아간다
var sprite_id: String = ""
var start_troops: int = 0
var hire_index: int = -1           # 주인공이 고용한 부대면 hired 목록 번호
var morale: int = 100              # 사기 0~100: 낮을수록 주는 피해가 줄고 받는 피해가 는다
var bonus_count: int = 0           # 이번 전투에서 포상을 받은 횟수


func alive() -> bool:
	return troops > 0


func done() -> bool:
	return acted or not alive()


func type_row() -> Dictionary:
	return DataDB.get_row("unit_types", unit_type)


func move_points() -> int:
	var points: int = int(type_row().get("move", 3))
	if traits.has("move_plus_1"):
		points += 1
	if traits.has("move_minus_1"):
		points -= 1
	return maxi(1, points)


func flying() -> bool:
	return traits.has("flying")


## 쓸 수 있는 전법들. 장수 부대면 그 장수의 전법 레벨을 반영한 값 (SkillLevels.row_for, "level" 포함)
func battle_skills() -> Array:
	var result: Array = []
	for skill_id: String in skills:
		var row: Dictionary = SkillLevels.row_for(officer_id, skill_id)
		if row.has("battle"):
			result.append(row)
	return result


## 공격 능력: 근접 = 무력 / 원거리 = (무력+통솔)/2 / 마법 = 마력 (GDD §8.4)
func attack_power(kind: String = "") -> int:
	if kind == "":
		kind = type_row().get("attack_stat", "melee")
	match kind:
		"ranged":
			return int((str_ + lead) / 2.0)
		"magic":
			return mag
	return str_
