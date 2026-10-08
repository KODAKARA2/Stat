class_name WorldMap
extends RefCounted
## 도시 연결 그래프 (GDD §2.3). 인접 목록은 양방향으로 맞춰 두고, 경로 찾기는 Godot의 AStar2D를 쓴다.

var _neighbors: Dictionary = {}   # city_id → PackedStringArray
var _astar: AStar2D = AStar2D.new()
var _point_of: Dictionary = {}    # city_id → AStar 점 번호
var _city_of: Dictionary = {}     # AStar 점 번호 → city_id

static var _shared: WorldMap


## 지도는 판 중에 바뀌지 않으므로 하나만 만들어 같이 쓴다.
static func shared() -> WorldMap:
	if _shared == null:
		_shared = WorldMap.new()
	return _shared


func _init() -> void:
	var rows: Array = DataDB.get_rows("cities")
	for i: int in rows.size():
		var row: Dictionary = rows[i]
		var id: String = row["id"]
		_point_of[id] = i
		_city_of[i] = id
		_neighbors[id] = PackedStringArray()
		_astar.add_point(i, position_of(id))
	for row: Dictionary in rows:
		for other: String in row.get("neighbors", []):
			_connect(row["id"], other)


func city_ids() -> PackedStringArray:
	return PackedStringArray(_point_of.keys())


func position_of(city_id: String) -> Vector2:
	var pos: Array = DataDB.get_row("cities", city_id).get("pos", [0, 0])
	return Vector2(pos[0], pos[1])


func neighbors(city_id: String) -> PackedStringArray:
	return _neighbors.get(city_id, PackedStringArray())


func is_adjacent(a: String, b: String) -> bool:
	return neighbors(a).has(b)


## 출발 도시부터 도착 도시까지의 도시 목록(양 끝 포함). 길이 없으면 빈 배열.
func path(from_id: String, to_id: String) -> PackedStringArray:
	var result: PackedStringArray = []
	if not (_point_of.has(from_id) and _point_of.has(to_id)):
		return result
	for point: int in _astar.get_id_path(_point_of[from_id], _point_of[to_id]):
		result.append(_city_of[point])
	return result


## 같은 나라가 아닌 이웃 도시가 하나라도 있으면 국경 도시
func is_border(city_id: String, owner_of: Callable) -> bool:
	var owner: String = owner_of.call(city_id)
	for other: String in neighbors(city_id):
		if owner_of.call(other) != owner:
			return true
	return false


## 각 국가에 포함된 도시끼리, 그리고 그래프 전체가 이어져 있는지 확인. 문제를 문장으로 돌려준다.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = []
	var ids: PackedStringArray = city_ids()
	for id: String in ids:
		for other: String in DataDB.get_row("cities", id).get("neighbors", []):
			if not _point_of.has(other):
				problems.append("%s: 없는 이웃 '%s'" % [id, other])
		if neighbors(id).is_empty():
			problems.append("%s: 이웃이 없음" % id)
	for id: String in ids:
		if path(ids[0], id).is_empty():
			problems.append("%s: %s에서 갈 수 없음" % [id, ids[0]])
	return problems


func _connect(a: String, b: String) -> void:
	if a == b or not (_point_of.has(a) and _point_of.has(b)) or _neighbors[a].has(b):
		return
	_neighbors[a].append(b)
	_neighbors[b].append(a)
	_astar.connect_points(_point_of[a], _point_of[b])


static func city_name(city_id: String) -> String:
	return TranslationServer.translate(DataDB.get_row("cities", city_id).get("name_key", city_id))
