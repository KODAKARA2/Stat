extends Node
## user://saves/에 JSON으로 저장 (GDD §12.3-6). 수동 슬롯 3개 + 자동 저장 1개.
## 앱이 백그라운드로 내려가거나 창을 닫을 때도 자동 저장한다.

const SAVE_DIR: String = "user://saves"
const AUTO_SLOT: String = "auto"
const MANUAL_SLOTS: PackedStringArray = ["slot1", "slot2", "slot3"]
const SAVE_VERSION: int = 1

## 타이틀 화면처럼 아직 판이 시작되지 않았을 때는 false → 자동 저장 안 함
var game_in_progress: bool = false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	EventBus.month_ended.connect(_on_month_ended)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if game_in_progress:
			save_game(AUTO_SLOT)


func slot_path(slot: String) -> String:
	return SAVE_DIR.path_join(slot + ".json")


func has_save(slot: String) -> bool:
	return FileAccess.file_exists(slot_path(slot))


func save_game(slot: String) -> bool:
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"rng": RNG.to_save(),
		"time": TimeManager.to_save(),
		"state": GameState.to_save(),
	}
	# 임시 파일에 먼저 쓰고 바꿔치기 → 저장 도중 앱이 꺼져도 기존 세이브가 깨지지 않음
	var tmp_path: String = slot_path(slot) + ".tmp"
	var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("세이브 실패: %s" % tmp_path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	DirAccess.rename_absolute(tmp_path, slot_path(slot))
	EventBus.game_saved.emit(slot)
	return true


func load_game(slot: String) -> bool:
	if not has_save(slot):
		return false
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(slot_path(slot))) != OK or not json.data is Dictionary:
		push_error("세이브 파일이 손상됨: %s" % slot)
		return false
	var data: Dictionary = json.data
	RNG.from_save(data.get("rng", {}))
	TimeManager.from_save(data.get("time", {}))
	GameState.from_save(data.get("state", {}))
	game_in_progress = true
	EventBus.game_loaded.emit(slot)
	return true


func _on_month_ended(_year: int, _month: int) -> void:
	if game_in_progress:
		save_game(AUTO_SLOT)


## 슬롯 미리보기: {"year", "month", "name", "rank_key", "saved_at"} (없으면 {})
func peek(slot: String) -> Dictionary:
	if not has_save(slot):
		return {}
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(slot_path(slot))) != OK or not json.data is Dictionary:
		return {}
	var data: Dictionary = json.data
	var state: Dictionary = data.get("state", {})
	var player: Dictionary = state.get("officers", {}).get(state.get("player_id", ""), {})
	return {
		"year": int(data.get("time", {}).get("year", 1)), "month": int(data.get("time", {}).get("month", 1)),
		"name": player.get("name", "?"), "rank_key": DataDB.get_row("ranks", player.get("rank", "none")).get("name_key", ""),
		"saved_at": data.get("saved_at", ""),
	}
