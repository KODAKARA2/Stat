extends Node2D
## 대륙 지도 그리기: 영토 색, 도로, 도시 점, 도시 이름.
## 도시 그림은 AssetRegistry에 "city_capital" / "city_town"이 등록되면 그 그림을 쓰고, 없으면 원으로 그린다.

const LAND_RECT: Rect2 = Rect2(-20, 30, 760, 1110)
const LAND_COLOR: Color = Color(0.29, 0.27, 0.21)
const ROAD_COLOR: Color = Color(0.62, 0.56, 0.42, 0.7)
const BORDER_ROAD_COLOR: Color = Color(0.85, 0.42, 0.32, 0.8)
const CITY_RADIUS: float = 16.0
const CAPITAL_RADIUS: float = 22.0
const TERRITORY_RADIUS: float = 95.0
const TAP_RADIUS: float = 40.0
const LABEL_FONT_SIZE: int = 24

var world: WorldMap
var selected_id: String = ""
var _labels: Dictionary = {}   # city_id → Label
var _pulse: float = 0.0


func setup(world_map: WorldMap) -> void:
	world = world_map
	for id: String in world.city_ids():
		var label: Label = Label.new()
		label.text = tr(DataDB.get_row("cities", id)["name_key"])
		label.add_theme_font_size_override("font_size", Settings.fs(LABEL_FONT_SIZE))
		label.add_theme_color_override("font_outline_color", Color(0.08, 0.07, 0.06))
		label.add_theme_constant_override("outline_size", 6)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		_labels[id] = label
	queue_redraw()


## 카메라 배율이 바뀌어도 글자는 화면에서 같은 크기로 보이게 한다.
func set_label_scale(camera_zoom: float) -> void:
	for id: String in _labels:
		var label: Label = _labels[id]
		label.scale = Vector2.ONE / camera_zoom
		label.reset_size()
		var below: float = (CAPITAL_RADIUS if _is_capital(id) else CITY_RADIUS) + 4.0
		label.position = world.position_of(id) + Vector2(-label.size.x * label.scale.x / 2.0, below)


func select(city_id: String) -> void:
	selected_id = city_id
	queue_redraw()


## 지도 좌표에서 가장 가까운 도시. 반경 밖이면 "".
func city_at(world_pos: Vector2, camera_zoom: float) -> String:
	var best: String = ""
	var best_dist: float = TAP_RADIUS / maxf(camera_zoom, 0.5)
	for id: String in world.city_ids():
		var dist: float = world.position_of(id).distance_to(world_pos)
		if dist < best_dist:
			best = id
			best_dist = dist
	return best


func _process(delta: float) -> void:
	# 선택 표시와 주인공 깃발이 살짝 움직이므로 매 프레임 다시 그린다
	_pulse = fmod(_pulse + delta * 2.0, TAU)
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	draw_rect(LAND_RECT, LAND_COLOR)
	# 영토: 도시마다 나라 색의 옅은 원
	for id: String in world.city_ids():
		draw_circle(world.position_of(id), TERRITORY_RADIUS, _nation_color(id, 0.16))
	# 도로: 국경을 넘는 길은 붉게
	for id: String in world.city_ids():
		for other: String in world.neighbors(id):
			if id < other:
				var cross: bool = GameState.city_owner(id) != GameState.city_owner(other)
				draw_line(world.position_of(id), world.position_of(other),
					BORDER_ROAD_COLOR if cross else ROAD_COLOR, 4.0 if cross else 3.0, true)
	# 도시
	for id: String in world.city_ids():
		var pos: Vector2 = world.position_of(id)
		var capital: bool = _is_capital(id)
		var radius: float = CAPITAL_RADIUS if capital else CITY_RADIUS
		if id == selected_id:
			draw_arc(pos, radius + 8.0 + sin(_pulse) * 3.0, 0.0, TAU, 40, Color(1, 0.9, 0.5), 3.0, true)
		var sprite_id: String = "city_capital" if capital else "city_town"
		if AssetRegistry.has_sprite(sprite_id):
			var tex: Texture2D = AssetRegistry.get_texture(sprite_id)
			draw_texture_rect(tex, Rect2(pos - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, _nation_color(id, 1.0))
		else:
			draw_circle(pos, radius, _nation_color(id, 1.0))
			draw_arc(pos, radius, 0.0, TAU, 32, Color(0.1, 0.09, 0.08), 3.0, true)
			if capital:
				draw_circle(pos, radius * 0.4, Color(0.98, 0.93, 0.75))
	_draw_planned_attacks()
	_draw_player_marker()


## 이번 달 출정 예정: 공격하는 나라 색 화살표 + 목표 도시에 X 표시
func _draw_planned_attacks() -> void:
	for p: Dictionary in WarSystem.plans():
		var from: Vector2 = world.position_of(p["from"])
		var to: Vector2 = world.position_of(p["to"])
		var dir: Vector2 = (to - from).normalized()
		var color: Color = Color.html(Nations.row(p["attacker"]).get("color", "#ff4040")).lightened(0.2)
		var start: Vector2 = from + dir * (CAPITAL_RADIUS + 4)
		var tip: Vector2 = to - dir * (CAPITAL_RADIUS + 6)
		var wobble: float = 1.0 + sin(_pulse * 2.0) * 0.08
		draw_line(start, tip, Color(0, 0, 0, 0.6), 9.0, true)
		draw_line(start, tip, color, 5.0 * wobble, true)
		var side: Vector2 = dir.orthogonal() * 10.0
		draw_colored_polygon(PackedVector2Array([tip + dir * 6, tip - dir * 14 + side, tip - dir * 14 - side]), color)
		var s: float = 9.0
		draw_line(to + Vector2(-s, -s), to + Vector2(s, s), Color(1, 0.25, 0.2), 4.0, true)
		draw_line(to + Vector2(-s, s), to + Vector2(s, -s), Color(1, 0.25, 0.2), 4.0, true)


## 주인공 위치: 도시 위에 작은 깃발. "marker_player" 그림이 등록되면 그걸 쓴다.
func _draw_player_marker() -> void:
	var city: String = GameState.player().get("city", "")
	if city == "":
		return
	var base: Vector2 = world.position_of(city) + Vector2(0, -(CAPITAL_RADIUS if _is_capital(city) else CITY_RADIUS))
	var bob: float = sin(Time.get_ticks_msec() / 300.0) * 2.0
	if AssetRegistry.has_sprite("marker_player"):
		var tex: Texture2D = AssetRegistry.get_texture("marker_player")
		draw_texture(tex, base - Vector2(tex.get_width() / 2.0, tex.get_height() + bob))
		return
	var top: Vector2 = base + Vector2(0, -34 + bob)
	draw_line(base, top, Color(0.1, 0.09, 0.08), 4.0)
	draw_colored_polygon(PackedVector2Array([top, top + Vector2(22, 7), top + Vector2(0, 14)]), Color(0.95, 0.3, 0.25))
	draw_polyline(PackedVector2Array([top, top + Vector2(22, 7), top + Vector2(0, 14)]), Color(0.1, 0.09, 0.08), 2.0)


func _is_capital(city_id: String) -> bool:
	return bool(DataDB.get_row("cities", city_id).get("capital", false))


func _nation_color(city_id: String, alpha: float) -> Color:
	var nation: Dictionary = Nations.row(GameState.city_owner(city_id))
	var color: Color = Color.html(nation.get("color", "#888888"))
	color.a = alpha
	return color
