extends Node
## JSON 저장: 검증 후 적용, 이전 정상 저장 백업, 교체 오류 확인.
const SAVE_DIR: String = "user://saves"
const AUTO_SLOT: String = "auto"
const MANUAL_SLOTS: PackedStringArray = ["slot1", "slot2", "slot3"]
const SAVE_VERSION: int = 1
var game_in_progress: bool = false
var last_error: String = ""
var recovered_backup: bool = false

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	EventBus.month_ready.connect(_on_month_ready)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if game_in_progress:
			save_game(AUTO_SLOT)

func slot_path(slot: String) -> String:
	return SAVE_DIR.path_join(slot + ".json")

func _valid_slot(slot: String) -> bool:
	return not slot.is_empty() and slot.is_valid_identifier()

func has_save(slot: String) -> bool:
	return _valid_slot(slot) and (FileAccess.file_exists(slot_path(slot)) or FileAccess.file_exists(slot_path(slot) + ".bak"))

func save_game(slot: String) -> bool:
	last_error = ""
	if not _valid_slot(slot):
		return _fail("저장 슬롯 이름이 올바르지 않습니다.")
	var data: Dictionary = {
		"version": SAVE_VERSION, "saved_at": Time.get_datetime_string_from_system(),
		"rng": RNG.to_save(), "time": TimeManager.to_save(), "state": GameState.to_save(),
	}
	if not _valid_data(data):
		return _fail("현재 게임 상태를 저장할 수 없습니다. 기존 저장은 보존했습니다.")
	var path: String = slot_path(slot)
	var tmp_path: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return _fail("저장 파일을 만들 수 없습니다. 저장 공간을 확인해 주세요.")
	file.store_string(JSON.stringify(data))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK or _read_valid(tmp_path).is_empty():
		return _fail("저장 파일 기록에 실패했습니다. 기존 저장은 보존했습니다.")
	# 손상된 본 파일로 정상 백업을 덮어쓰지 않는다.
	if not _read_valid(path).is_empty():
		if DirAccess.copy_absolute(path, path + ".bak.tmp") != OK or DirAccess.rename_absolute(path + ".bak.tmp", path + ".bak") != OK:
			return _fail("이전 저장 백업에 실패했습니다. 기존 저장은 보존했습니다.")
	if DirAccess.rename_absolute(tmp_path, path) != OK:
		return _fail("저장 파일 교체에 실패했습니다. 기존 저장과 백업을 보존했습니다.")
	EventBus.game_saved.emit(slot)
	return true

func load_game(slot: String) -> bool:
	last_error = ""
	recovered_backup = false
	if not _valid_slot(slot):
		return _fail("저장 슬롯 이름이 올바르지 않습니다.")
	var data: Dictionary = _read_valid(slot_path(slot))
	if data.is_empty():
		data = _read_valid(slot_path(slot) + ".bak")
		recovered_backup = not data.is_empty()
	if data.is_empty():
		return _fail("저장이 손상되었거나 지원하지 않는 형식입니다. 다른 슬롯을 선택해 주세요.")
	# 모든 필수 필드 검증이 끝난 뒤에만 실행 중인 판을 바꾼다.
	RNG.from_save(data["rng"])
	TimeManager.from_save(data["time"])
	GameState.from_save(data["state"])
	game_in_progress = true
	EventBus.game_loaded.emit(slot)
	return true

func _on_month_ready(_year: int, _month: int) -> void:
	if game_in_progress and not save_game(AUTO_SLOT):
		EventBus.save_failed.emit(last_error)

func _fail(message: String) -> bool:
	last_error = message
	return false

func _read_valid(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return {}
	return json.data if _valid_data(json.data) else {}

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _valid_data(data: Dictionary) -> bool:
	if data.get("version") != SAVE_VERSION:
		return false
	for key: String in ["rng", "time", "state"]:
		if not data.get(key) is Dictionary:
			return false
	for key: String in ["seed", "state"]:
		var value: Variant = data["rng"].get(key)
		if not (_number(value) or (value is String and value.is_valid_int())):
			return false
	var date: Dictionary = data["time"]
	if not _number(date.get("year")) or not _number(date.get("month")):
		return false
	if float(date["year"]) != floor(float(date["year"])) or date["year"] < 1 or date["month"] < 1 or date["month"] > 12 or float(date["month"]) != floor(float(date["month"])):
		return false
	var state: Dictionary = data["state"]
	for key: String in ["officers", "cities", "nations", "relations", "diplomacy", "flags"]:
		if not state.get(key) is Dictionary:
			return false
	var player: Variant = state.get("player_id")
	if not player is String or player == "" or not state["officers"].has(player):
		return false
	for table: String in ["officers", "cities", "nations", "relations", "diplomacy"]:
		for entry: Variant in state[table].values():
			if not entry is Dictionary:
				return false
	for city: Dictionary in DataDB.get_rows("cities"):
		if not state["cities"].has(city["id"]):
			return false
	for officer: Dictionary in state["officers"].values():
		for key: String in ["city", "rank", "race", "nation"]:
			if not officer.get(key) is String:
				return false
		if not state["cities"].has(officer["city"]) or DataDB.get_row("ranks", officer["rank"]).is_empty() or DataDB.get_row("races", officer["race"]).is_empty():
			return false
		for key: String in ["stats", "potential", "exp"]:
			if not officer.get(key) is Dictionary:
				return false
		for key: String in Officers.stat_keys():
			if not _number(officer["stats"].get(key)) or not _number(officer["potential"].get(key)):
				return false
		for key: String in ["ap", "energy", "gold", "age", "troops", "injury"]:
			if not _number(officer.get(key)):
				return false
		if not officer.get("skills") is Array or not officer.get("alive") is bool:
			return false
	for nation: Dictionary in state["nations"].values():
		if not nation.get("alive") is bool or not _number(nation.get("gold")) or not _number(nation.get("food")):
			return false
	for city: Dictionary in state["cities"].values():
		if not city.get("nation") is String or not state["nations"].has(city["nation"]):
			return false
		for key: String in ["population", "troops", "commerce", "agriculture", "security", "defense"]:
			if not _number(city.get(key)):
				return false
	return true

func peek(slot: String) -> Dictionary:
	if not _valid_slot(slot):
		return {}
	var data: Dictionary = _read_valid(slot_path(slot))
	var backup: bool = data.is_empty()
	if backup:
		data = _read_valid(slot_path(slot) + ".bak")
	if data.is_empty():
		return {}
	var state: Dictionary = data["state"]
	var player: Dictionary = state["officers"][state["player_id"]]
	return {
		"year": int(data["time"]["year"]), "month": int(data["time"]["month"]),
		"name": player.get("name", "?"), "rank_key": DataDB.get_row("ranks", player["rank"]).get("name_key", ""),
		"saved_at": data.get("saved_at", ""), "backup": backup,
	}
