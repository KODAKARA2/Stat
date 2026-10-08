class_name UnitToken
extends Node2D
## 말판 위 부대 하나. 장수는 초상화(팀 색 테두리), 병종·몬스터는 투명 배경 전신 그림(팀 색 발판),
## 그림이 없으면 팀 색 원 + 글자 한 자.
## 아래쪽 막대 = 남은 병력, 왕관 표시 = 총대장, 어둡게 = 이번 차례 행동 끝.

const ALLY_COLOR: Color = Color(0.3, 0.55, 0.9)
const ENEMY_COLOR: Color = Color(0.85, 0.32, 0.28)

var unit: BattleUnit
var cell_size: float = 96.0
var _label: Label


func setup(u: BattleUnit, size: float) -> void:
	unit = u
	cell_size = size
	_label = Label.new()
	_label.text = u.short
	_label.add_theme_font_size_override("font_size", Settings.fs(36))
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 6)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.size = Vector2(size, size - 16)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	position = cell_to_pos(u.cell)
	refresh()


## 병종·몬스터 전신 그림인가 (장수 초상화가 아니라)
func is_figure() -> bool:
	return unit.sprite_id.begins_with("unit_") or unit.sprite_id.begins_with("mon_")


func cell_to_pos(c: Vector2i) -> Vector2:
	return Vector2(c.x * cell_size, c.y * cell_size)


func refresh() -> void:
	modulate = Color(0.55, 0.55, 0.55) if unit.acted and unit.alive() else Color.WHITE
	_label.visible = not AssetRegistry.has_sprite(unit.sprite_id)
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = Vector2(cell_size, cell_size - 16) / 2.0
	var team_color: Color = ALLY_COLOR if unit.team == "ally" else ENEMY_COLOR
	if AssetRegistry.has_sprite(unit.sprite_id) and is_figure():
		# 병종·몬스터 그림(배경 투명): 팀 색 발판 위에 선다. 적은 좌우를 뒤집어 아군과 마주 보게.
		var foot: Vector2 = Vector2(cell_size / 2.0, cell_size - 26)
		draw_set_transform(foot, 0.0, Vector2(1.0, 0.38))
		draw_circle(Vector2.ZERO, cell_size * 0.4, Color(team_color.darkened(0.35), 0.85))
		draw_arc(Vector2.ZERO, cell_size * 0.4, 0, TAU, 32, team_color.lightened(0.3), 5.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var tex: Texture2D = AssetRegistry.get_texture(unit.sprite_id)
		var side: float = cell_size - 8
		var r: Rect2 = Rect2(Vector2(4, -4), Vector2(side, side))
		if unit.team == "enemy":
			draw_set_transform(Vector2(cell_size, 0), 0.0, Vector2(-1, 1))
		draw_texture_rect(tex, r, false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif AssetRegistry.has_sprite(unit.sprite_id):
		var tex: Texture2D = AssetRegistry.get_texture(unit.sprite_id)
		var r: Rect2 = Rect2(Vector2(8, 4), Vector2(cell_size - 16, cell_size - 24))
		draw_texture_rect(tex, r, false)
		draw_rect(r.grow(2), team_color.lightened(0.2), false, 4.0)   # 아군 파랑 / 적 빨강 테두리
	else:
		draw_circle(center, cell_size * 0.36, team_color.darkened(0.2))
		draw_arc(center, cell_size * 0.36, 0, TAU, 32, team_color.lightened(0.3), 4.0, true)
	if unit.leader:
		var top: Vector2 = Vector2(cell_size / 2.0, 6)
		draw_colored_polygon(PackedVector2Array([top + Vector2(-14, 12), top + Vector2(-14, 0), top + Vector2(-7, 7),
			top + Vector2(0, -2), top + Vector2(7, 7), top + Vector2(14, 0), top + Vector2(14, 12)]), Color(1, 0.84, 0.3))
	# 병력 막대
	var bar: Rect2 = Rect2(10, cell_size - 14, cell_size - 20, 8)
	draw_rect(bar, Color(0, 0, 0, 0.7))
	var ratio: float = clampf(float(unit.troops) / maxf(unit.max_troops, 1), 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), team_color.lightened(0.2))


## 칸을 따라 걸어가기
func walk(path: Array[Vector2i]) -> void:
	var tween: Tween = create_tween()
	for i: int in range(1, path.size()):
		tween.tween_property(self, "position", cell_to_pos(path[i]), 0.09)
	await tween.finished


## 상대 쪽으로 툭 치고 돌아오기
func lunge(toward: Vector2i) -> void:
	var home: Vector2 = position
	var dir: Vector2 = (cell_to_pos(toward) - home).normalized()
	var tween: Tween = create_tween()
	tween.tween_property(self, "position", home + dir * 22.0, 0.08)
	tween.tween_property(self, "position", home, 0.12)
	await tween.finished


func shake() -> void:
	var home: Vector2 = position
	var tween: Tween = create_tween()
	for i: int in 3:
		tween.tween_property(self, "position", home + Vector2(6, 0), 0.03)
		tween.tween_property(self, "position", home - Vector2(6, 0), 0.03)
	tween.tween_property(self, "position", home, 0.03)
	await tween.finished


func fade_out() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.35)
	await tween.finished
	visible = false
