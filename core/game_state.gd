extends Node
## 현재 판의 모든 상태. UI는 여기를 조회만 하고, 바꾸는 건 systems/가 한다.
## 저장하기 쉽도록 전부 Dictionary(JSON으로 그대로 쓸 수 있는 값)로 둔다.

const PLAYER_ID: String = "player"

var player_id: String = ""
var nations: Dictionary = {}    # nation_id → 상태
var cities: Dictionary = {}     # city_id → 상태
var officers: Dictionary = {}   # officer_id → 상태 (플레이어 포함)
var relations: Dictionary = {}  # "a|b" → {"v": 친밀도 변화량, "met": 만난 적 있음} — 0이 아닌 것만 저장
var diplomacy: Dictionary = {}  # "a|b"(나라 쌍) → {"status": "war"/"truce", "months": 남은 휴전 개월}
var flags: Dictionary = {}      # 이벤트 진행 기록, 이번 달 공격 계획, 월말 보고 등


func _ready() -> void:
	# 매월 초 처리(행동력 회복, 나이 등)는 UI보다 먼저 돌아야 하므로 여기서 가장 먼저 연결한다
	EventBus.month_started.connect(func(year: int, month: int) -> void: MonthlyUpdate.start_month(year, month))
	EventBus.month_ended.connect(func(year: int, month: int) -> void: MonthlyUpdate.end_month(year, month))
	EventBus.action_executed.connect(func(actor: String, action_id: String, result: Dictionary) -> void:
		Career.on_action(actor, action_id, result)
		if actor == player_id:
			EventRunner.trigger("on_action", {"action": action_id}))


func reset() -> void:
	player_id = ""
	nations.clear()
	cities.clear()
	officers.clear()
	relations.clear()
	diplomacy.clear()
	flags.clear()


func player() -> Dictionary:
	return officers.get(player_id, {})


func to_save() -> Dictionary:
	return {
		"player_id": player_id,
		"nations": nations,
		"cities": cities,
		"officers": officers,
		"relations": relations,
		"diplomacy": diplomacy,
		"flags": flags,
	}


func from_save(data: Dictionary) -> void:
	player_id = data.get("player_id", "")
	nations = data.get("nations", {})
	cities = data.get("cities", {})
	officers = data.get("officers", {})
	relations = data.get("relations", {})
	diplomacy = data.get("diplomacy", {})
	flags = data.get("flags", {})


func city_owner(city_id: String) -> String:
	return cities.get(city_id, {}).get("nation", "")
