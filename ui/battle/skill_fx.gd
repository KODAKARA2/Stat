class_name SkillFx
extends Node2D
## 전법 연출 (모두 코드로 그린다, 그림 파일 없음). elapsed(초)를 0 → duration으로 트윈하면 그려지고 끝나면 사라진다.
##  volley  일제사격: 화살 여러 발이 포물선을 그리며 시간차로 범위에 쏟아지고, 꽂힐 때마다 불꽃·먼지
##  fire    화염술: 시전자 발밑 마법진 → 불덩이 → 폭발 고리 + 범위에 솟는 불길과 연기
##  impact  돌격 충돌: 흰 번쩍임 + 충격파 고리 + 사방으로 튀는 파편
##  shield  축성: 푸른 육각 방패가 펼쳐지고 빛 알갱이가 솟는다
##  heal    치료: 초록 빛기둥 + 피어오르는 반짝이 + 발밑 고리
##  dash    돌격 잔상: 지나간 길을 따라 속도선

var kind: String = "volley"
var from: Vector2 = Vector2.ZERO
var to: Vector2 = Vector2.ZERO
var area: Array[Vector2] = []        # 범위 칸 가운데들 (volley, fire)
var duration: float = 1.0
var elapsed: float = 0.0:
	set(value):
		elapsed = value
		queue_redraw()
var _parts: Array = []               # 미리 정한 입자들 (매 프레임 같은 모양이 되도록)
var level: int = 1                   # 전법 레벨: 높을수록 화살·불길이 많다

const ARROWS: int = 26
const FLAMES: int = 34


static func play(parent: Node2D, fx_kind: String, start: Vector2, target: Vector2, cells: Array[Vector2] = [], skill_level: int = 1) -> SkillFx:
	var fx: SkillFx = SkillFx.new()
	fx.level = skill_level
	fx.kind = fx_kind
	fx.from = start
	fx.to = target
	fx.area = cells.duplicate()
	if fx.area.is_empty():
		fx.area.append(target)
	fx.duration = {"volley": 1.15, "fire": 1.3, "impact": 0.55, "shield": 0.9, "heal": 1.0, "dash": 0.3}.get(fx_kind, 1.0)
	fx._prepare()
	parent.add_child(fx)
	var tween: Tween = fx.create_tween()
	tween.tween_property(fx, "elapsed", fx.duration, fx.duration)
	tween.tween_callback(fx.queue_free)
	return fx


## 결과(피해 숫자)를 띄우기 좋은 순간: 대부분 맞기 시작할 때
func hit_time() -> float:
	return {"volley": 0.55, "fire": 0.62, "impact": 0.05, "shield": 0.35, "heal": 0.4, "dash": 0.3}.get(kind, 0.4)


func _prepare() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	match kind:
		"volley":
			for i: int in int(ARROWS * (1.0 + 0.4 * (level - 1))):
				var cell: Vector2 = area[rng.randi() % area.size()]
				_parts.append({
					"delay": rng.randf_range(0.0, 0.32), "fly": rng.randf_range(0.36, 0.46),
					"start": from + Vector2(rng.randf_range(-14, 14), rng.randf_range(-10, 6)),
					"end": cell + Vector2(rng.randf_range(-34, 34), rng.randf_range(-30, 26)),
					"arc": rng.randf_range(110, 190),
					"bulge": rng.randf_range(-70, 70),   # 부채꼴로 퍼지는 정도 (세로 말판에서 포물선이 보이게)
				})
		"fire":
			for i: int in int(FLAMES * (1.0 + 0.4 * (level - 1))):
				var cell: Vector2 = area[rng.randi() % area.size()]
				_parts.append({
					"delay": 0.6 + rng.randf_range(0.0, 0.3), "life": rng.randf_range(0.35, 0.6),
					"pos": cell + Vector2(rng.randf_range(-40, 40), rng.randf_range(-30, 34)),
					"rise": rng.randf_range(40, 95), "size": rng.randf_range(9, 18), "drift": rng.randf_range(-12, 12),
				})
		"impact":
			for i: int in 14:
				var ang: float = rng.randf_range(0, TAU)
				_parts.append({"dir": Vector2.from_angle(ang), "speed": rng.randf_range(140, 300), "size": rng.randf_range(3, 7)})
		"shield", "heal":
			for i: int in 16:
				_parts.append({
					"x": rng.randf_range(-36, 36), "delay": rng.randf_range(0.0, 0.45),
					"rise": rng.randf_range(50, 100), "size": rng.randf_range(3, 6),
				})


func _draw() -> void:
	var t: float = elapsed
	match kind:
		"volley":
			_draw_volley(t)
		"fire":
			_draw_fire(t)
		"impact":
			_draw_impact(t)
		"shield":
			_draw_shield(t)
		"heal":
			_draw_heal(t)
		"dash":
			_draw_dash(t)


# ── 일제사격 ────────────────────────────────────

func _draw_volley(t: float) -> void:
	# 시위 당기는 금빛 고리
	if t < 0.3:
		var k: float = t / 0.3
		draw_arc(from, 20.0 + 26.0 * k, 0, TAU, 32, Color(1, 0.85, 0.4, 1.0 - k), 4.0, true)
	# 맞는 범위가 붉게 깜빡인다
	if t > 0.45 and t < 1.0:
		var a: float = 0.22 * (1.0 - absf(sin((t - 0.45) * 18.0)) * 0.5)
		for c: Vector2 in area:
			draw_rect(Rect2(c - Vector2(46, 40), Vector2(92, 92)), Color(1, 0.25, 0.15, a))
	for p: Dictionary in _parts:
		var local: float = (t - float(p["delay"])) / float(p["fly"])
		if local < 0.0:
			continue
		var start: Vector2 = p["start"]
		var end: Vector2 = p["end"]
		if local < 1.0:
			# 땅 위 그림자는 곧게, 화살은 옆으로 부풀며 높이 떴다가 내리꽂힌다. 높이 뜰수록 크게.
			var ground: Vector2 = _volley_ground(p, local)
			var height: float = 4.0 * local * (1.0 - local)
			var pos: Vector2 = ground + Vector2(0, -float(p["arc"]) * height)
			var nxt: float = minf(1.0, local + 0.03)
			var ahead: Vector2 = _volley_ground(p, nxt) + Vector2(0, -float(p["arc"]) * 4.0 * nxt * (1.0 - nxt))
			draw_circle(ground, 4.0 + 3.0 * height, Color(0, 0, 0, 0.18 + 0.1 * local))
			_draw_arrow(pos, (ahead - pos).normalized(), 1.0, 1.0 + 0.7 * height)
		else:
			# 꽂힌 화살 + 불꽃 + 먼지
			var after: float = (t - float(p["delay"]) - float(p["fly"])) / 0.3
			if after > 1.0:
				continue
			_draw_arrow(end, Vector2(0.3, 1).normalized(), 1.0 - after * 0.6)
			draw_circle(end + Vector2(0, 8), 8.0 + 20.0 * after, Color(0.8, 0.72, 0.55, 0.5 * (1.0 - after)))
			for k: int in 6:
				var dir: Vector2 = Vector2.from_angle(-PI / 2.0 + (k - 2.5) * 0.5)
				draw_line(end + dir * 5.0, end + dir * (10.0 + 18.0 * after), Color(1, 0.92, 0.55, 1.0 - after), 3.0)


## 화살 그림자가 지나는 땅 위 자리: 출발 → 도착 직선에서 옆으로 부풀었다 돌아온다
func _volley_ground(p: Dictionary, local: float) -> Vector2:
	var start: Vector2 = p["start"]
	var end: Vector2 = p["end"]
	var dir: Vector2 = (end - start).normalized()
	var side: Vector2 = Vector2(-dir.y, dir.x)
	return start.lerp(end, local) + side * float(p["bulge"]) * sin(local * PI)


func _draw_arrow(pos: Vector2, dir: Vector2, alpha: float = 1.0, size: float = 1.0) -> void:
	var side: Vector2 = Vector2(-dir.y, dir.x) * size
	var d: Vector2 = dir * size
	var tail: Vector2 = pos - d * 40.0
	draw_line(tail, pos, Color(0.12, 0.08, 0.05, alpha), 6.0 * size)                  # 테두리
	draw_line(tail, pos, Color(0.62, 0.42, 0.22, alpha), 3.5 * size)                  # 화살대
	draw_colored_polygon(PackedVector2Array([pos + d * 11.0, pos + side * 6.0, pos - side * 6.0]), Color(0.9, 0.93, 1.0, alpha))   # 촉
	draw_line(tail, tail - d * 10.0 + side * 7.0, Color(0.95, 0.3, 0.25, alpha), 3.0 * size)   # 붉은 깃
	draw_line(tail, tail - d * 10.0 - side * 7.0, Color(0.95, 0.3, 0.25, alpha), 3.0 * size)


# ── 화염술 ──────────────────────────────────────

func _draw_fire(t: float) -> void:
	# 1) 시전자 발밑 마법진 (0 ~ 0.4)
	if t < 0.45:
		var k: float = clampf(t / 0.15, 0.0, 1.0)
		var fade: float = 1.0 if t < 0.3 else (0.45 - t) / 0.15
		var c: Color = Color(1, 0.55, 0.15, fade)
		var center: Vector2 = from + Vector2(0, 26)
		draw_set_transform(center, 0.0, Vector2(1.0, 0.45))
		draw_arc(Vector2.ZERO, 44.0 * k, 0, TAU, 40, c, 4.0, true)
		draw_arc(Vector2.ZERO, 30.0 * k, 0, TAU, 32, Color(1, 0.85, 0.4, fade), 2.0, true)
		for i: int in 8:
			var ang: float = t * 6.0 + i * TAU / 8.0
			draw_circle(Vector2.from_angle(ang) * 37.0 * k, 4.0, Color(1, 0.95, 0.6, fade))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 2) 불덩이 (0.3 ~ 0.6)
	if t > 0.3 and t < 0.62:
		var k: float = (t - 0.3) / 0.32
		var pos: Vector2 = from.lerp(to, k) + Vector2(0, -60.0 * 4.0 * k * (1.0 - k))
		for i: int in 6:   # 꼬리
			var back: float = maxf(0.0, k - i * 0.05)
			var tp: Vector2 = from.lerp(to, back) + Vector2(0, -60.0 * 4.0 * back * (1.0 - back))
			draw_circle(tp, 22.0 - i * 3.0, Color(1, 0.4 + i * 0.05, 0.1, 0.6 - i * 0.08))
		draw_circle(pos, 30.0, Color(1, 0.45, 0.1, 0.35))   # 열기
		draw_circle(pos, 22.0, Color(1, 0.55, 0.15))
		draw_circle(pos, 12.0, Color(1, 0.97, 0.7))
	# 3) 폭발 (0.6 ~ 1.3)
	if t >= 0.6:
		var k: float = (t - 0.6) / 0.7
		if k < 0.25:
			draw_circle(to, 70.0 * (1.0 - k * 2.0), Color(1, 1, 0.85, 0.85 * (1.0 - k * 4.0)))
		draw_arc(to, 30.0 + 150.0 * k, 0, TAU, 48, Color(1, 0.5, 0.1, 0.9 * (1.0 - k)), 10.0 * (1.0 - k) + 2.0, true)
		draw_arc(to, 20.0 + 100.0 * k, 0, TAU, 40, Color(1, 0.85, 0.3, 0.7 * (1.0 - k)), 4.0, true)
	for p: Dictionary in _parts:
		var life: float = (t - float(p["delay"])) / float(p["life"])
		if life < 0.0 or life > 1.0:
			continue
		var pos: Vector2 = Vector2(p["pos"]) + Vector2(float(p["drift"]) * life, -float(p["rise"]) * life)
		var col: Color = Color(1, 0.95, 0.5).lerp(Color(1, 0.45, 0.1), minf(1.0, life * 2.0))
		if life > 0.6:
			col = Color(1, 0.45, 0.1).lerp(Color(0.25, 0.22, 0.2), (life - 0.6) / 0.4)   # 연기로
		col.a = 1.0 - life * 0.8
		draw_circle(pos, float(p["size"]) * (1.0 - life * 0.5), col)


# ── 돌격 ────────────────────────────────────────

func _draw_impact(t: float) -> void:
	var k: float = t / duration
	if k < 0.3:
		draw_circle(to, 50.0 * (1.0 - k / 0.3) + 10.0, Color(1, 1, 1, 0.9 * (1.0 - k / 0.3)))
	draw_arc(to, 20.0 + 110.0 * k, 0, TAU, 40, Color(1, 0.95, 0.75, 1.0 - k), 8.0 * (1.0 - k) + 1.0, true)
	draw_arc(to, 10.0 + 70.0 * k, 0, TAU, 32, Color(1, 0.7, 0.3, 0.8 * (1.0 - k)), 3.0, true)
	for p: Dictionary in _parts:
		var pos: Vector2 = to + Vector2(p["dir"]) * float(p["speed"]) * t + Vector2(0, 260.0 * t * t)
		draw_rect(Rect2(pos - Vector2.ONE * float(p["size"]) / 2.0, Vector2.ONE * float(p["size"])), Color(0.75, 0.62, 0.45, 1.0 - k))


func _draw_dash(t: float) -> void:
	var k: float = t / duration
	var dir: Vector2 = (to - from).normalized()
	var side: Vector2 = Vector2(-dir.y, dir.x)
	for i: int in 7:
		var off: float = (i - 3) * 9.0
		var a: Vector2 = from + side * off
		var b: Vector2 = a.lerp(to + side * off, minf(1.0, k * 1.6))
		draw_line(a.lerp(b, k), b, Color(1, 1, 1, 0.55 * (1.0 - k)), 3.0)


# ── 축성 ────────────────────────────────────────

func _draw_shield(t: float) -> void:
	var k: float = t / duration
	var grow: float = minf(1.0, k / 0.35)
	var fade: float = 1.0 if k < 0.7 else (1.0 - k) / 0.3
	var pts: PackedVector2Array = []
	for i: int in 7:
		pts.append(from + Vector2.from_angle(-PI / 2.0 + i * TAU / 6.0) * 52.0 * grow)
	var fill: PackedVector2Array = pts.slice(0, 6)
	draw_colored_polygon(fill, Color(0.35, 0.6, 1.0, 0.25 * fade))
	draw_polyline(pts, Color(0.6, 0.85, 1.0, fade), 5.0, true)
	draw_arc(from, 60.0 * grow + 8.0 * sin(t * 12.0), 0, TAU, 40, Color(0.7, 0.9, 1.0, 0.4 * fade), 2.0, true)
	_draw_motes(t, Color(0.75, 0.9, 1.0))


# ── 치료 ────────────────────────────────────────

func _draw_heal(t: float) -> void:
	var k: float = t / duration
	var fade: float = minf(1.0, k / 0.2) * (1.0 if k < 0.7 else (1.0 - k) / 0.3)
	for i: int in 4:   # 빛기둥 (안쪽일수록 밝게)
		var w: float = 40.0 - i * 9.0
		draw_rect(Rect2(to.x - w / 2.0, to.y - 150.0, w, 180.0), Color(0.55, 1.0, 0.6, 0.12 * fade * (i + 1)))
	draw_set_transform(to + Vector2(0, 28), 0.0, Vector2(1.0, 0.4))
	draw_arc(Vector2.ZERO, 30.0 + 18.0 * k, 0, TAU, 40, Color(0.6, 1.0, 0.65, fade), 5.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_motes(t, Color(0.75, 1.0, 0.75), to, true)


## 피어오르는 빛 알갱이 (축성은 시전자 주변, 치료는 대상 주변에 십자 모양)
func _draw_motes(t: float, color: Color, center: Vector2 = Vector2.INF, cross: bool = false) -> void:
	var base: Vector2 = from if center == Vector2.INF else center
	for p: Dictionary in _parts:
		var life: float = (t - float(p["delay"])) / 0.5
		if life < 0.0 or life > 1.0:
			continue
		var pos: Vector2 = base + Vector2(float(p["x"]), 30.0 - float(p["rise"]) * life)
		var c: Color = Color(color, 1.0 - life)
		var s: float = float(p["size"])
		if cross:
			draw_rect(Rect2(pos - Vector2(s, s / 3.0), Vector2(s * 2.0, s / 1.5)), c)
			draw_rect(Rect2(pos - Vector2(s / 3.0, s), Vector2(s / 1.5, s * 2.0)), c)
		else:
			draw_circle(pos, s, c)
