extends Node
## res://data/ 아래 JSON을 전부 읽어 둔다 (GDD §12.3-2).
## 표 이름 = data/ 기준 상대 경로에서 .json을 뺀 것. 예) "nations", "events/tavern"
## 배열 표의 각 항목에 "id"가 있으면 get_row()로 바로 찾을 수 있다.

const DATA_ROOT: String = "res://data"

var _tables: Dictionary = {}   # 표 이름 → 원본 데이터
var _index: Dictionary = {}    # 표 이름 → {id → 행}
var errors: PackedStringArray = []


func _ready() -> void:
	reload()


func reload() -> void:
	_tables.clear()
	_index.clear()
	errors.clear()
	_load_dir(DATA_ROOT)
	EventBus.data_loaded.emit(_tables.size())


func table_names() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray(_tables.keys())
	names.sort()
	return names


func has_table(table: String) -> bool:
	return _tables.has(table)


func get_table(table: String) -> Variant:
	return _tables.get(table)


## 배열 표를 돌려준다. 표가 없거나 배열이 아니면 빈 배열.
func get_rows(table: String) -> Array:
	var data: Variant = _tables.get(table)
	return data if data is Array else []


func get_row(table: String, id: String) -> Dictionary:
	return _index.get(table, {}).get(id, {})


## balance.json 값 조회. "battle.damage.troop_factor" 처럼 점으로 파고든다.
func balance(path: String, default_value: Variant = null) -> Variant:
	var node: Variant = _tables.get("balance", {})
	for key: String in path.split("."):
		if not (node is Dictionary and node.has(key)):
			return default_value
		node = node[key]
	return node


func _load_dir(dir_path: String) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		errors.append("폴더를 열 수 없음: %s" % dir_path)
		return
	for sub: String in dir.get_directories():
		_load_dir(dir_path.path_join(sub))
	for file: String in dir.get_files():
		if file.get_extension() == "json":
			_load_file(dir_path.path_join(file))


func _load_file(path: String) -> void:
	var text: String = FileAccess.get_file_as_string(path)
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		errors.append("%s %d줄: %s" % [path, json.get_error_line(), json.get_error_message()])
		return
	var table: String = path.trim_prefix(DATA_ROOT + "/").trim_suffix(".json")
	var data: Variant = json.data
	# 맨 앞의 "_comment" 같은 설명용 키는 남겨 둔다. 배열 표는 {"rows": [...]} 형태도 허용.
	if data is Dictionary and data.has("rows") and data["rows"] is Array:
		data = data["rows"]
	_tables[table] = data
	if data is Array:
		var by_id: Dictionary = {}
		for row: Variant in data:
			if row is Dictionary and row.has("id"):
				if by_id.has(row["id"]):
					errors.append("%s: id 중복 '%s'" % [table, row["id"]])
				by_id[row["id"]] = row
		_index[table] = by_id
