class_name BattleFx
extends Node2D
## 전투 연출 한 조각: 칼 부딪힘(clash) / 베기(slash) / 화살·포탄(shot) / 마법 폭발(burst) / 성문 타격(thud).
## progress 0 → 1로 트윈하면 그림이 바뀌고, 끝나면 스스로 사라진다.
## clash = 고전 삼국지3 느낌: 맞는 부대 위에서 도트 칼 두 자루가 X자로 엇갈리며 서너 번 부딪힌다.

const CLASH_TIMES: int = 3          # 부딪히는 횟수
const SWORD_SCALE: float = 3.0      # 도트 칼 확대 배율 (7×22 → 21×66)
# 도트 칼 (위가 칼끝). O 테두리 W 빛 L 밝은 쇠 D 어두운 쇠 G 금 g 어두운 금 B 손잡이 b 어두운 손잡이
const SWORD_PIXELS: Array = [
	"...O...",
	"..OWO..",
	".OWLDO.", ".OWLDO.", ".OWLDO.", ".OWLDO.", ".OWLDO.", ".OWLDO.", ".OWLDO.",
	".OWLDO.", ".OWLDO.", ".OWLDO.", ".OWLDO.", ".OWLDO.", ".OWLDO.",
	"OOOOOOO",
	"OGGGGgO",
	".OOBOO.",
	"..OBO..",
	"..ObO..",
	"..OGO..",
	"...O...",
]
const SWORD_COLORS: Dictionary = {
	"O": Color("1a1f2e"), "W": Color("ffffff"), "L": Color("cfe0ff"), "D": Color("7f93b8"),
	"G": Color("e8b33a"), "g": Color("9a6a1c"), "B": Color("6b3f22"), "b": Color("3d2414"),
}
const GRIP_ROW: int = 18            # 칼을 돌리는 축 (손잡이)

static var _sword: Texture2D

var kind: String = "slash"
var from: Vector2 = Vector2.ZERO     # shot: 출발점 (부모 좌표)
var to: Vector2 = Vector2.ZERO       # 맞는 칸 가운데
var color: Color = Color.WHITE
var progress: float = 0.0:
	set(value):
		progress = value
		queue_redraw()


## 부모(말판 효과 층)에 연출을 하나 띄우고 끝날 때까지 기다릴 수 있게 돌려준다
static func play(parent: Node2D, fx_kind: String, start: Vector2, target: Vector2, tint: Color, seconds: float) -> BattleFx:
	var fx: BattleFx = BattleFx.new()
	fx.kind = fx_kind
	fx.from = start
	fx.to = target
	fx.color = tint
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 도트가 뭉개지지 않게
	parent.add_child(fx)
	var tween: Tween = fx.create_tween()
	tween.tween_property(fx, "progress", 1.0, seconds)
	tween.tween_callback(fx.queue_free)
	return fx


## 공격하는 부대 종류에 맞는 연출 이름
static func kind_for(attack_stat: String) -> String:
	return {"melee": "clash", "ranged": "shot", "magic": "burst"}.get(attack_stat, "clash")


## 도트 칼 텍스처 (한 번만 만든다)
static func sword_texture() -> Texture2D:
	if _sword == null:
		var img: Image = Image.create(7, SWORD_PIXELS.size(), false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for y: int in SWORD_PIXELS.size():
			var row: String = SWORD_PIXELS[y]
			for x: int in row.length():
				if SWORD_COLORS.has(row[x]):
					img.set_pixel(x, y, SWORD_COLORS[row[x]])
		_sword = ImageTexture.create_from_image(img)
	return _sword


## 칼 한 자루: 손잡이(grip)를 축으로 angle만큼 기울여 그린다 (0 = 칼끝이 위)
func _draw_sword(grip: Vector2, angle: float, alpha: float) -> void:
	var tex: Texture2D = sword_texture()
	var size: Vector2 = Vector2(tex.get_width(), tex.get_height()) * SWORD_SCALE
	var pivot: Vector2 = Vector2(3.5, GRIP_ROW + 0.5) * SWORD_SCALE
	draw_set_transform(grip, angle, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-pivot, size), false, Color(1, 1, 1, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	var t: float = progress
	match kind:
		"clash":
			# 두 칼이 벌어졌다가(±75°) X자로 엇갈리며(±32°) 부딪히기를 CLASH_TIMES번. 부딪히는 순간 불꽃.
			var phase: float = t * CLASH_TIMES
			var swing: float = absf(sin(phase * PI))            # 0 = 벌어짐, 1 = 엇갈림
			var spread: float = lerpf(deg_to_rad(75.0), deg_to_rad(32.0), swing)
			var alpha: float = 1.0 if t < 0.85 else (1.0 - t) / 0.15
			var shake: Vector2 = Vector2(2, -1) * (1 if int(phase * 4.0) % 2 == 0 else -1) * swing
			_draw_sword(to + Vector2(-24, 26) + shake, spread, alpha)     # 왼쪽 칼: 칼끝이 오른쪽 위로
			_draw_sword(to + Vector2(24, 26) - shake, -spread, alpha)     # 오른쪽 칼: 칼끝이 왼쪽 위로
			if swing > 0.82:
				var spark: Vector2 = to + Vector2(0, -12)
				var r: float = 6.0 + 10.0 * (swing - 0.82) / 0.18
				for k: int in 4:
					var dir: Vector2 = Vector2.from_angle(PI / 4.0 + k * PI / 2.0)
					draw_line(spark + dir * 3.0, spark + dir * r, Color(1, 1, 0.8, alpha), 3.0)
				draw_rect(Rect2(spark - Vector2(3, 3), Vector2(6, 6)), Color(1, 1, 1, alpha))
		"slash":
			# 대각선으로 그어지는 흰 칼자국 두 줄
			for k: int in 2:
				var off: Vector2 = Vector2(10, -6) * k
				var a: Vector2 = to + Vector2(-34, -30) + off
				var b: Vector2 = to + Vector2(34, 30) + off
				var head: Vector2 = a.lerp(b, minf(1.0, t * 1.8))
				var tail: Vector2 = a.lerp(b, maxf(0.0, t * 1.8 - 0.6))
				draw_line(tail, head, Color(color, 1.0 - t), 7.0 - k * 2.0, true)
		"shot":
			# 출발점 → 맞는 곳으로 날아가는 화살(꼬리 달린 점), 도착하면 작은 불꽃
			var fly: float = minf(1.0, t / 0.7)
			var p: Vector2 = from.lerp(to, fly)
			var dir: Vector2 = (to - from).normalized()
			if fly < 1.0:
				draw_line(p - dir * 26.0, p, Color(color, 0.9), 4.0, true)
				draw_circle(p, 5.0, color)
			else:
				var s: float = (t - 0.7) / 0.3
				for i: int in 6:
					var ang: float = TAU * i / 6.0
					draw_line(to + Vector2.from_angle(ang) * 8.0, to + Vector2.from_angle(ang) * (14.0 + 22.0 * s), Color(color, 1.0 - s), 3.0, true)
		"burst":
			# 커지는 마법 고리 + 가운데 번쩍임
			draw_circle(to, 34.0 * (1.0 - t) + 4.0, Color(color, 0.35 * (1.0 - t)))
			draw_arc(to, 10.0 + 44.0 * t, 0, TAU, 40, Color(color, 1.0 - t), 6.0 * (1.0 - t) + 1.0, true)
			draw_arc(to, 4.0 + 28.0 * t, 0, TAU, 32, Color(Color.WHITE, 0.8 * (1.0 - t)), 3.0, true)
		"thud":
			# 성문을 두드리는 충격파
			draw_arc(to, 12.0 + 40.0 * t, PI * 0.15, PI * 0.85, 20, Color(color, 1.0 - t), 6.0, true)
			draw_arc(to, 12.0 + 40.0 * t, PI * 1.15, PI * 1.85, 20, Color(color, 1.0 - t), 6.0, true)
