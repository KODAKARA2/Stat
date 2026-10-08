class_name DuelState
extends RefCounted
## 결투 한 판의 상태 (GDD §6.1, 2026-10-08 3수 예약형으로 개편). a = 주인공 쪽(조작), b = 상대(AI).
## 진행: 턴마다 양쪽이 3수를 예약 → 동시에 공개하며 한 수씩 해결 → 쓴 횟수만큼 무작위 보충.

var a_id: String
var b_id: String
var hp: Dictionary = {}        # id → 남은 체력
var max_hp: Dictionary = {}
var sp: Dictionary = {}        # id → 기력
var hand: Dictionary = {}      # id → {명령: 남은 횟수} (방어는 무한이라 없음)
var specials: Dictionary = {}  # id → [쓸 수 있는 필살기]
var plan: Dictionary = {}      # id → [이번 턴 예약 3수]
var stunned: Dictionary = {}   # id → true면 다음 수가 빈틈으로 무효
var pool: int = 0              # 충돌 누적: 다음에 맞는 쪽이 이만큼 더 받는다
var turn: int = 1
var log: Array = []            # 이번 턴 결과 [{slot, a_cmd, b_cmd, a_dmg, b_dmg, text, events}]
var hint: Dictionary = {}      # {"slot": 0~2, "kind": "attack"/"guard"/"special"} 이번 턴 상대 기색 (턴 시작에 한 번 정함)
var result: String = ""        # 끝났으면 "a" / "b" / "draw"


func other(id: String) -> String:
	return b_id if id == a_id else a_id


func finished() -> bool:
	return result != ""


## 이긴 사람 id. 무승부면 ""
func winner() -> String:
	match result:
		"a":
			return a_id
		"b":
			return b_id
	return ""
