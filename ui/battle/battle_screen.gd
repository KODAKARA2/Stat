extends Node2D
## 전투 화면 (GDD §8): 세로 7×10 격자. 아래쪽 패널에 명령 버튼을 모아 엄지로 조작한다.
## 흐름: 아군 부대 누르기 → 파란 칸 눌러 이동 → [공격]/[전법]/[대기] → 모두 행동하면 적 차례.
## 규칙 계산은 전부 BattleRules/BattleAI가 하고, 여기서는 보여 주기와 입력만 한다.

const CELL: float = 96.0
const BOARD_ORIGIN: Vector2 = Vector2(24, 84)
const MOVE_COLOR: Color = Color(0.35, 0.6, 1.0, 0.38)
const ATTACK_COLOR: Color = Color(1.0, 0.3, 0.25, 0.38)
const SKILL_COLOR: Color = Color(1.0, 0.65, 0.2, 0.38)
const HEAL_COLOR: Color = Color(0.4, 1.0, 0.5, 0.38)

const LONG_PRESS_MS: int = 450
const CLASH_SECONDS: float = 0.62     # 칼 부딪힘 연출 길이

var state: BattleState
var _press_cell: Vector2i = Vector2i(-1, -1)
var _press_time: int = -1
var _long_press_done: bool = false
var _tokens: Dictionary = {}           # uid → UnitToken
var _mode: String = "idle"             # idle / move / action / attack / skill_list / skill / busy / ended
var _selected: BattleUnit
var _origin_cell: Vector2i
var _reach: Dictionary = {}
var _cells: Array[Vector2i] = []       # 지금 칠해 둔 칸
var _cells_color: Color = MOVE_COLOR
var _pending: Vector2i = Vector2i(-1, -1)
var _skill: Dictionary = {}

var _board: Node2D
var _terrain: TileMapLayer
var _overlay: Node2D
var _units: Node2D
var _effects: Node2D
var _hud: Control
var _title: Label
var _info: Label
var _preview: Label
var _buttons: HBoxContainer
var _top_panel: Control
var _board_home: Vector2 = BOARD_ORIGIN   # 흔들기 전 말판 자리
var _shake_tween: Tween
var _dueled: Dictionary = {}   # 이번 전투에서 이미 결투한 장수 쌍 (같은 쌍은 한 번만)
var _bottom_panel: Control


func _ready() -> void:
	state = BattleSession.state
	if state == null and "--siege" in OS.get_cmdline_user_args():   # 개발용: 공성전 바로 보기
		WorldSetup.new_game({"name": "테스트", "race": "human", "origin": "leonhart", "background": "knight_bastard", "bonus": {}})
		SaveManager.game_in_progress = false   # 시험 실행은 자동 저장하지 않는다
		Diplomacy.set_war("leonhart", "astra")
		var plan: Dictionary = {"id": "dev", "attacker": "leonhart", "defender": "astra", "from": "rocelle", "to": "calyx", "sent": 3000, "mercs": 0, "merc_cost": 0, "commander": "gabriel", "def_commander": "marcus", "player_side": "", "player_result": ""}
		GameState.flags["planned_attacks"] = [plan]
		Guild.post_war_quests(plan)
		state = BattleSetup.from_war_quest(Guild.city_quests("rocelle").back(), GameState.player_id)
	if state == null:   # 이 장면을 바로 실행했을 때: 시험용 전투
		if GameState.player_id == "":
			WorldSetup.new_game({"name": "테스트", "race": "human", "origin": "leonhart", "background": "knight_bastard", "bonus": {}})
			SaveManager.game_in_progress = false   # 시험 실행은 자동 저장하지 않는다
		state = BattleSetup.from_quest(Guild.make_quest("arden"), GameState.player_id)
	_build_board()
	_build_ui()
	_fit_board.call_deferred()
	_refresh_all()
	_set_mode("idle")
	if not Array(OS.get_cmdline_user_args()).any(func(a: String) -> bool: return a.begins_with("--fx=")):
		_show_battle_name()
	for arg: String in OS.get_cmdline_user_args():   # 개발용: --fx=volley|fire|charge|fortify|heal 전법 연출 바로 보기 (느리게)
		if arg.begins_with("--fx="):
			Engine.time_scale = float(OS.get_environment("FX_SLOW")) if OS.get_environment("FX_SLOW") != "" else 1.0
			var caster: BattleUnit = state.living("ally")[0]
			var foe_cell: Vector2i = state.living("enemy")[1].cell if state.living("enemy").size() > 1 else state.living("enemy")[0].cell
			var skill_id: String = arg.trim_prefix("--fx=")
			var target: Vector2i = caster.cell if skill_id in ["fortify", "heal"] else foe_cell
			_skill_fx(caster, DataDB.get_row("skills", skill_id), target)
	if "--cutin" in OS.get_cmdline_user_args():   # 개발용: 전법 컷인·공격 연출 바로 보기
		var me: BattleUnit = state.leader_of("ally")
		_cut_in(me, tr("SKILL_CHARGE"))
		var foe: BattleUnit = state.living("enemy")[0]
		BattleFx.play(_effects, "clash", _center(foe.cell), _center(foe.cell), Color.WHITE, 3.0)
		_damage_box(state.living("enemy")[1].cell, 59)
		for u: BattleUnit in state.living("ally"):
			if u != me:
				BattleFx.play(_effects, "shot", _center(u.cell), _center(foe.cell), Color(1, 0.88, 0.55), 3.0)
				break


# ── 화면 만들기 ─────────────────────────────────

func _build_board() -> void:
	_board = Node2D.new()
	_board.position = BOARD_ORIGIN
	add_child(_board)
	_terrain = TileMapLayer.new()
	_terrain.tile_set = BattleTiles.make_tileset()
	_terrain.scale = Vector2.ONE * (CELL / BattleTiles.TILE)
	_board.add_child(_terrain)
	_overlay = Node2D.new()
	_overlay.draw.connect(_draw_overlay)
	_board.add_child(_overlay)
	_units = Node2D.new()
	_board.add_child(_units)
	_effects = Node2D.new()
	_board.add_child(_effects)
	for y: int in state.height:
		for x: int in state.width:
			_paint_terrain(Vector2i(x, y))
	for u: BattleUnit in state.units:
		var token: UnitToken = UnitToken.new()
		token.setup(u, CELL)
		_units.add_child(token)
		_tokens[u.uid] = token


func _paint_terrain(cell: Vector2i) -> void:
	_terrain.set_cell(cell, 0, Vector2i(BattleTiles.atlas_index(state.terrain_at(cell)), 0))


func _build_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)

	var top: PanelContainer = UiKit.panel(UiKit.PANEL_BG, 12)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size.y = 72
	_hud.add_child(top)
	_top_panel = top
	_title = UiKit.label("", 24, UiKit.GOLD, true)   # 길면 두 줄로 (말판은 _fit_board가 맞춰 줄인다)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_title)

	var bottom: PanelContainer = UiKit.panel(UiKit.PANEL_BG, 16)
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.custom_minimum_size.y = 224
	_hud.add_child(bottom)
	_bottom_panel = bottom
	top.resized.connect(_fit_board)
	bottom.resized.connect(_fit_board)
	var v: VBoxContainer = UiKit.vbox(6)
	bottom.add_child(v)
	_info = UiKit.label("", 24, UiKit.TEXT, true)
	v.add_child(_info)
	_preview = UiKit.label("", 24, UiKit.GOLD, true)
	v.add_child(_preview)
	var filler: Control = Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(filler)
	_buttons = UiKit.hbox(8)
	v.add_child(_buttons)


## 전투 이름: 시작할 때 화면 가운데에 크게 띄웠다가 서서히 사라진다 (누르면 바로 사라짐)
func _show_battle_name() -> void:
	var band: PanelContainer = UiKit.panel(Color(0, 0, 0, 0.72), 24)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v: VBoxContainer = UiKit.vbox(4)
	band.add_child(v)
	var title: Label = UiKit.label(Guild.quest_title(state.quest), 48, UiKit.GOLD, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 10)
	v.add_child(title)
	if state.mode != "field":
		var sub: Label = UiKit.label(tr("BATTLE_MODE_" + state.mode.to_upper()), 24, UiKit.TEXT, true)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(sub)
	var view: Vector2 = get_viewport_rect().size
	band.custom_minimum_size.x = view.x   # 폭을 먼저 정해야 줄바꿈 글씨의 높이가 바로 나온다
	title.custom_minimum_size.x = view.x - 48.0
	_hud.add_child(band)
	band.reset_size()
	band.position = Vector2(0, (view.y - band.size.y) / 2.0 - 80.0)
	band.modulate.a = 0.0
	var tween: Tween = band.create_tween()
	tween.tween_property(band, "modulate:a", 1.0, 0.25)
	tween.tween_interval(1.3)
	tween.tween_property(band, "modulate:a", 0.0, 0.6)
	tween.tween_callback(band.queue_free)


## 위 제목줄과 아래 안내창 사이에 말판이 다 들어가게 크기·위치를 맞춘다 (글씨를 키워 안내창이 커져도 아랫줄이 안 가려지게)
func _fit_board() -> void:
	if _board == null or _top_panel == null or _bottom_panel == null:
		return
	var view: Vector2 = get_viewport_rect().size
	var top: float = _top_panel.size.y + 6.0
	var avail: Vector2 = Vector2(view.x - BOARD_ORIGIN.x * 2.0, view.y - top - _bottom_panel.size.y - 6.0)
	var board: Vector2 = Vector2(state.width, state.height) * CELL
	var k: float = minf(1.0, minf(avail.x / board.x, avail.y / board.y))
	_board.scale = Vector2(k, k)
	_board.position = Vector2((view.x - board.x * k) / 2.0, top + (avail.y - board.y * k) / 2.0)
	_board_home = _board.position


func _set_buttons(specs: Array) -> void:
	UiKit.clear(_buttons)
	for spec: Array in specs:   # [글, 할 일, (켜짐)]
		var b: Button = UiKit.button(spec[0], spec[1], 72)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if spec.size() > 2:
			b.disabled = not spec[2]
		_buttons.add_child(b)


func _refresh_all() -> void:
	var phase_key: String = "BATTLE_PHASE_ALLY" if state.phase == "ally" else "BATTLE_PHASE_ENEMY"
	# 위 막대는 한 줄: 턴 · 차례 · 금. 전투 이름은 시작할 때 크게 띄웠다 사라진다(_show_battle_name).
	_title.text = tr("BATTLE_TURN_LINE") % [state.turn, tr(phase_key), Fmt.num(int(GameState.player().get("gold", 0)))]
	for uid: int in _tokens:
		(_tokens[uid] as UnitToken).refresh()
	_overlay.queue_redraw()


func _unit_line(u: BattleUnit) -> String:
	var text: String = tr("BATTLE_UNIT_LINE") % [u.name, Fmt.num(u.troops), Fmt.num(u.max_troops), u.morale, u.sp]
	text += " · " + tr(u.type_row().get("name_key", ""))
	if u.leader:
		text += " · " + tr("BATTLE_LEADER")
	text += " · " + tr(state.terrain_row(u.cell).get("name_key", ""))
	return text


# ── 상태(모드) ──────────────────────────────────

func _set_mode(mode: String) -> void:
	_mode = mode
	_preview.text = ""
	match mode:
		"idle":
			_selected = null
			_show_cells([], MOVE_COLOR)
			_info.text = tr("BATTLE_HINT_SELECT") + _siege_line()
			_set_buttons([[tr("BATTLE_END_TURN"), _end_turn], [tr("BATTLE_AUTO"), _auto_turn], [tr("BATTLE_RETREAT"), _ask_retreat]])
		"move":
			_reach = BattleRules.reachable(state, _selected)
			_show_cells(_reach.keys(), MOVE_COLOR)
			_info.text = _unit_line(_selected) + "\n" + tr("BATTLE_HINT_MOVE")
			_set_buttons([_bonus_button(), [tr("BATTLE_CANCEL"), func() -> void: _set_mode("idle")]])
		"action":
			var cells: Array[Vector2i] = _attack_cells(_selected)
			_show_cells(cells, ATTACK_COLOR)
			_info.text = _unit_line(_selected)
			_set_buttons([
				[tr("BATTLE_ATTACK"), func() -> void: _set_mode("attack"), not cells.is_empty()],
				[tr("BATTLE_SKILL"), func() -> void: _set_mode("skill_list"), not _selected.battle_skills().is_empty()],
				[tr("BATTLE_WAIT"), _wait_selected],
				_bonus_button(),
				[tr("BATTLE_CANCEL"), _undo_move],
			])
		"attack":
			_pending = Vector2i(-1, -1)
			_show_cells(_attack_cells(_selected), ATTACK_COLOR)
			_info.text = tr("BATTLE_HINT_TARGET")
			_set_buttons([[tr("BATTLE_CONFIRM_ATTACK"), _confirm, false], [tr("BATTLE_CANCEL"), func() -> void: _set_mode("action")]])
		"skill_list":
			var specs: Array = []
			for skill: Dictionary in _selected.battle_skills():
				var cost: int = int(skill["battle"].get("sp", 0))
				var usable: bool = BattleRules.can_use(_selected, skill) and not BattleRules.skill_cells(state, _selected, skill).is_empty()
				specs.append([tr("BATTLE_SKILL_LINE") % [SkillLevels.title(skill), cost], _choose_skill.bind(skill), usable])
			specs.append([tr("BATTLE_CANCEL"), func() -> void: _set_mode("action")])
			_info.text = _unit_line(_selected)
			_set_buttons(specs)
		"skill":
			_pending = Vector2i(-1, -1)
			var target: String = _skill["battle"].get("target", "enemy")
			_show_cells(BattleRules.skill_cells(state, _selected, _skill), HEAL_COLOR if target == "ally" else SKILL_COLOR)
			_info.text = SkillLevels.title(_skill) + ": " + tr(_skill["desc_key"]) + "\n" + tr("BATTLE_HINT_SKILL_TARGET")
			_set_buttons([[tr("BATTLE_CONFIRM_ATTACK"), _confirm, false], [tr("BATTLE_CANCEL"), func() -> void: _set_mode("skill_list")]])
			if target == "self":
				_pending = _selected.cell
				_set_buttons([[tr("BATTLE_CONFIRM_ATTACK"), _confirm, true], [tr("BATTLE_CANCEL"), func() -> void: _set_mode("skill_list")]])
		"busy", "ended":
			_show_cells([], MOVE_COLOR)
			_set_buttons([])
	_refresh_all()


func _show_cells(cells: Array, color: Color) -> void:
	_cells.clear()
	for c: Vector2i in cells:
		_cells.append(c)
	_cells_color = color
	_overlay.queue_redraw()


func _draw_overlay() -> void:
	# 공성: 성 안 거점(★)과 성문 내구도 막대
	if state.keep_cell.x >= 0:
		var center: Vector2 = (Vector2(state.keep_cell) + Vector2(0.5, 0.5)) * CELL
		var pts: PackedVector2Array = []
		for i: int in 10:
			var r: float = 30.0 if i % 2 == 0 else 13.0
			pts.append(center + Vector2.from_angle(-PI / 2 + i * PI / 5) * r)
		_overlay.draw_colored_polygon(pts, Color(1, 0.84, 0.3, 0.55))
		pts.append(pts[0])
		_overlay.draw_polyline(pts, Color(1, 0.9, 0.5), 2.0)
	var max_hp: float = float(DataDB.get_row("terrain", "gate").get("hp", 500))
	for g: Vector2i in state.gate_hp:
		if int(state.gate_hp[g]) > 0:
			var bar: Rect2 = Rect2(Vector2(g) * CELL + Vector2(8, CELL - 16), Vector2(CELL - 16, 8))
			_overlay.draw_rect(bar, Color(0, 0, 0, 0.7))
			_overlay.draw_rect(Rect2(bar.position, Vector2(bar.size.x * int(state.gate_hp[g]) / max_hp, bar.size.y)), Color(1, 0.7, 0.3))
	for c: Vector2i in _cells:
		var rect: Rect2 = Rect2(Vector2(c) * CELL, Vector2(CELL, CELL))
		_overlay.draw_rect(rect.grow(-3), _cells_color)
		_overlay.draw_rect(rect.grow(-3), Color(_cells_color, 0.9), false, 2.0)
	# 범위 전법은 맞을 칸까지 미리 보여 준다
	if _mode == "skill" and _pending.x >= 0 and _skill["battle"].get("target", "") == "area":
		for c: Vector2i in BattleRules.area_cells(state, _pending, int(_skill["battle"].get("radius", 1))):
			_overlay.draw_rect(Rect2(Vector2(c) * CELL, Vector2(CELL, CELL)).grow(-6), Color(1, 0.4, 0.1, 0.45))
	if _pending.x >= 0:
		_overlay.draw_rect(Rect2(Vector2(_pending) * CELL, Vector2(CELL, CELL)).grow(-2), Color.WHITE, false, 4.0)
	if _selected:
		_overlay.draw_rect(Rect2(Vector2(_selected.cell) * CELL, Vector2(CELL, CELL)).grow(-2), Color(1, 0.9, 0.4), false, 4.0)


# ── 입력 ────────────────────────────────────────

## 짧게 누르기 = 명령, 우클릭 또는 길게 누르기(폰) = 부대 상세
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var cell: Vector2i = _cell_at(event.position)
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_show_unit_info(cell)
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_cell = cell
			_press_time = Time.get_ticks_msec()
			_long_press_done = false
		elif not _long_press_done and cell == _press_cell and state.in_bounds(cell):
			_press_time = -1
			_on_cell(cell)
		else:
			_press_time = -1


func _process(_delta: float) -> void:
	if _press_time >= 0 and not _long_press_done and Time.get_ticks_msec() - _press_time > LONG_PRESS_MS:
		_long_press_done = true
		_press_time = -1
		_show_unit_info(_press_cell)


func _cell_at(screen_pos: Vector2) -> Vector2i:
	var local: Vector2 = (screen_pos - _board.position) / (CELL * _board.scale.x)
	return Vector2i(floori(local.x), floori(local.y))


func _show_unit_info(cell: Vector2i) -> void:
	var u: BattleUnit = state.unit_at(cell) if state.in_bounds(cell) else null
	if u:
		Modal.open(_hud, UnitInfo.build(state, u))


func _on_cell(cell: Vector2i) -> void:
	var u: BattleUnit = state.unit_at(cell)
	match _mode:
		"idle":
			if u and u.team == "ally" and not u.acted and state.phase == "ally":
				_select(u)
			elif u:
				_info.text = _unit_line(u)
		"move":
			if cell == _selected.cell:
				_set_mode("action")
			elif _reach.has(cell):
				_move_selected(cell)
			elif u and u.team == "ally" and not u.acted:
				_select(u)
			else:
				_set_mode("idle")
				if u:
					_info.text = _unit_line(u)
		"action", "skill_list":
			if u:
				_info.text = _unit_line(u)
		"attack":
			if _cells.has(cell):
				if _pending == cell:
					_confirm()
					return
				_pending = cell
				if u:
					var lo: int = BattleRules.damage(state, _selected, u, 0.9, "", false)
					var hi: int = BattleRules.damage(state, _selected, u, 1.1, "", false)
					_preview.text = tr("BATTLE_PREVIEW") % [lo, hi, Fmt.num(u.troops)]
				else:   # 성문
					var g: int = BattleRules.gate_damage(_selected, false)
					_preview.text = tr("BATTLE_PREVIEW_GATE") % [int(g * 0.9), int(g * 1.1), int(state.gate_hp[cell])]
				var specs: Array = [[tr("BATTLE_CONFIRM_ATTACK"), _confirm], [tr("BATTLE_CANCEL"), func() -> void: _set_mode("action")]]
				if u and u.officer_id != "" and _selected.officer_id != "" and BattleRules.distance(u.cell, _selected.cell) == 1:
					specs.insert(1, [tr("DUEL_CHALLENGE"), _challenge_duel.bind(u)])   # 장수끼리 붙어 있으면 결투
				_set_buttons(specs)
				_overlay.queue_redraw()
		"skill":
			if _cells.has(cell):
				if _pending == cell:
					_confirm()
					return
				_pending = cell
				_set_buttons([[tr("BATTLE_CONFIRM_ATTACK"), _confirm], [tr("BATTLE_CANCEL"), func() -> void: _set_mode("skill_list")]])
				_overlay.queue_redraw()


func _select(u: BattleUnit) -> void:
	_selected = u
	_origin_cell = u.cell
	_set_mode("move")


func _move_selected(cell: Vector2i) -> void:
	_set_mode("busy")
	var route: Array[Vector2i] = BattleRules.path(state, _selected, cell)
	await (_tokens[_selected.uid] as UnitToken).walk(route)
	BattleRules.move_unit(state, _selected, cell)
	_set_mode("action")


func _undo_move() -> void:
	_selected.cell = _origin_cell
	_selected.moved = false
	(_tokens[_selected.uid] as UnitToken).position = Vector2(_origin_cell) * CELL
	_set_mode("move")


func _wait_selected() -> void:
	_selected.acted = true
	_after_player_action()


func _choose_skill(skill: Dictionary) -> void:
	_skill = skill
	_set_mode("skill")


func _confirm() -> void:
	if _pending.x < 0:
		return
	var actor: BattleUnit = _selected
	var cell: Vector2i = _pending
	var mode: String = _mode
	_set_mode("busy")
	if mode == "attack" and state.gate_hp.has(cell) and state.unit_at(cell) == null:
		await _animate_gate(actor, cell)
	elif mode == "attack":
		await _animate_attack(actor, state.unit_at(cell))
	else:
		await _animate_skill(actor, _skill, cell)
	_after_player_action()


func _after_player_action() -> void:
	_selected = null
	if state.check_end() != "":
		_finish()
	elif state.phase_done():
		_end_turn()
	else:
		_set_mode("idle")


# ── 연출 ────────────────────────────────────────

func _animate_attack(attacker: BattleUnit, target: BattleUnit) -> void:
	await _strike(attacker, target.cell)
	var r: Dictionary = BattleRules.attack(state, attacker, target)
	_damage_box(target.cell, r["damage"])
	await (_tokens[target.uid] as UnitToken).shake()
	if r["counter"] > 0:
		_damage_box(attacker.cell, r["counter"])
		await (_tokens[attacker.uid] as UnitToken).shake()
	await _remove_fallen()


func _animate_skill(unit: BattleUnit, skill: Dictionary, cell: Vector2i) -> void:
	if unit.officer_id != "" and not (_tokens[unit.uid] as UnitToken).is_figure():
		await _cut_in(unit, tr(skill["name_key"]))
	else:
		_popup(unit.cell, tr(skill["name_key"]), Color(1, 0.85, 0.4))
	await _skill_fx(unit, skill, cell)
	var r: Dictionary = BattleRules.use_skill(state, unit, skill, cell)
	for c: Vector2i in r["burned"]:
		_paint_terrain(c)
	for hit: Dictionary in r["hits"]:
		_damage_box(hit["unit"].cell, hit["damage"])
		(_tokens[hit["unit"].uid] as UnitToken).shake()
	for h: Dictionary in r.get("heals", []):
		_popup(h["unit"].cell, tr("BATTLE_HEAL") % h["amount"], Color(0.5, 1, 0.55))
	if int(r.get("level_up", 0)) > 0:
		_level_up_banner(unit, skill, int(r["level_up"]))
	for g: BattleUnit in r.get("guarded", []):
		_popup(g.cell, tr("BATTLE_GUARD"), Color(0.6, 0.8, 1))
	if r.get("counter", 0) > 0:
		_damage_box(unit.cell, r["counter"])
	await get_tree().create_timer(0.35).timeout
	await _remove_fallen()


## 전법 연출 (SkillFx). 피해가 들어가기 시작하는 순간까지 기다렸다 돌아온다 — 나머지 연출은 뒤에서 계속 흐른다.
func _skill_fx(unit: BattleUnit, skill: Dictionary, cell: Vector2i) -> void:
	var b: Dictionary = skill.get("battle", {})
	var cells: Array[Vector2] = []
	for c: Vector2i in BattleRules.area_cells(state, cell, int(b.get("radius", 0))):
		cells.append(_center(c))
	var token: UnitToken = _tokens[unit.uid]
	match skill.get("id", ""):
		"volley":
			var fx: SkillFx = SkillFx.play(_effects, "volley", _center(unit.cell), _center(cell), cells, int(skill.get("level", 1)))
			await get_tree().create_timer(fx.hit_time()).timeout
			_shake_board(6.0, 0.45)
		"fire":
			var fx: SkillFx = SkillFx.play(_effects, "fire", _center(unit.cell), _center(cell), cells, int(skill.get("level", 1)))
			await get_tree().create_timer(fx.hit_time()).timeout
			_flash(Color(1, 0.55, 0.2), 0.35)
			_shake_board(10.0, 0.5)
		"charge":
			# 잔상 속도선을 남기며 끝까지 달려들었다가 돌아온다 → 충돌
			SkillFx.play(_effects, "dash", _center(unit.cell), _center(cell))
			var home: Vector2 = token.position
			var hit_pos: Vector2 = token.cell_to_pos(cell) - (token.cell_to_pos(cell) - home).normalized() * 30.0
			var tween: Tween = token.create_tween()
			tween.tween_property(token, "position", home.lerp(home - (hit_pos - home).normalized() * 18.0, 1.0), 0.1)   # 뒤로 살짝 물러섰다가
			tween.tween_property(token, "position", hit_pos, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			await tween.finished
			SkillFx.play(_effects, "impact", _center(cell), _center(cell))
			BattleFx.play(_effects, "clash", _center(cell), _center(cell), Color.WHITE, CLASH_SECONDS * 0.7)
			_flash(Color.WHITE, 0.18)
			_shake_board(14.0, 0.4)
			var back: Tween = token.create_tween()
			back.tween_property(token, "position", home, 0.22).set_delay(0.12)
			await get_tree().create_timer(0.3).timeout
		"fortify":
			var fx: SkillFx = SkillFx.play(_effects, "shield", _center(unit.cell), _center(unit.cell))
			await get_tree().create_timer(fx.hit_time()).timeout
		"heal":
			var fx: SkillFx = SkillFx.play(_effects, "heal", _center(unit.cell), _center(cell))
			await get_tree().create_timer(fx.hit_time()).timeout
		_:
			if cell != unit.cell:
				await _strike(unit, cell)


## 전법 레벨업: 그 부대 위에 크게 "돌격 Lv2!" 를 띄우고 잠깐 머문다
func _level_up_banner(unit: BattleUnit, skill: Dictionary, lv: int) -> void:
	var l: Label = UiKit.label(tr("SKILL_LEVEL_UP") % [tr(skill["name_key"]), lv], 36, UiKit.GOLD)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 10)
	_effects.add_child(l)
	l.reset_size()
	l.position = _center(unit.cell) - Vector2(l.size.x / 2.0, CELL * 0.9)
	l.pivot_offset = l.size / 2.0
	l.scale = Vector2(0.3, 0.3)
	var tween: Tween = l.create_tween()
	tween.tween_property(l, "scale", Vector2(1.15, 1.15), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(l, "scale", Vector2.ONE, 0.1)
	tween.tween_interval(1.1)
	tween.tween_property(l, "modulate:a", 0.0, 0.4)
	tween.tween_callback(l.queue_free)
	SkillFx.play(_effects, "heal", _center(unit.cell), _center(unit.cell))   # 빛기둥으로 축하


## 말판 흔들기 (세기 px, 시간 초)
func _shake_board(strength: float, seconds: float) -> void:
	var home: Vector2 = _board_home
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()   # 흔들기가 겹치면 앞의 것은 멈추고 제자리에서 다시
	var tween: Tween = _board.create_tween()
	_shake_tween = tween
	var steps: int = maxi(2, int(seconds / 0.04))
	for i: int in steps:
		var k: float = 1.0 - float(i) / steps
		tween.tween_property(_board, "position", home + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength * k, 0.04)
	tween.tween_property(_board, "position", home, 0.04)


## 화면 번쩍임
func _flash(color: Color, seconds: float) -> void:
	var rect: ColorRect = ColorRect.new()
	rect.color = Color(color, 0.55)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.add_child(rect)
	var tween: Tween = rect.create_tween()
	tween.tween_property(rect, "color:a", 0.0, seconds)
	tween.tween_callback(rect.queue_free)


## 칸 가운데 (말판 좌표)
func _center(cell: Vector2i) -> Vector2:
	return Vector2(cell) * CELL + Vector2(CELL / 2.0, CELL / 2.0 - 8.0)


## 공격 연출: 근접은 툭 치고 칼 두 자루가 X자로 부딪히기(고전 삼국지3 느낌), 활·공성은 날아가는 화살, 마법은 폭발 고리
func _strike(attacker: BattleUnit, cell: Vector2i) -> void:
	var kind: String = BattleFx.kind_for(attacker.type_row().get("attack_stat", "melee"))
	match kind:
		"clash":
			await (_tokens[attacker.uid] as UnitToken).lunge(cell)
			BattleFx.play(_effects, "clash", _center(cell), _center(cell), Color.WHITE, CLASH_SECONDS)
			await get_tree().create_timer(CLASH_SECONDS * 0.9).timeout
		"slash":
			await (_tokens[attacker.uid] as UnitToken).lunge(cell)
			BattleFx.play(_effects, "slash", _center(cell), _center(cell), Color(1, 1, 0.92), 0.25)
		"shot":
			BattleFx.play(_effects, "shot", _center(attacker.cell), _center(cell), Color(1, 0.88, 0.55), 0.38)
			await get_tree().create_timer(0.27).timeout
		_:
			BattleFx.play(_effects, "burst", _center(cell), _center(cell), Color(0.65, 0.6, 1.0), 0.4)
			await get_tree().create_timer(0.2).timeout


## 전법 컷인: 장수 초상화가 화면을 가로질러 들어오며 전법 이름을 외친다
func _cut_in(unit: BattleUnit, skill_name: String) -> void:
	var team_color: Color = UnitToken.ALLY_COLOR if unit.team == "ally" else UnitToken.ENEMY_COLOR
	var band: Control = Control.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var view: Vector2 = get_viewport_rect().size
	band.size = Vector2(view.x, 220)
	band.position = Vector2(0, (view.y - band.size.y) / 2.0 - 60.0)
	_hud.add_child(band)
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(team_color.darkened(0.6), 0.88)
	bg.size = band.size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(bg)
	for y: float in [0.0, band.size.y - 6.0]:
		var edge: ColorRect = ColorRect.new()
		edge.color = team_color.lightened(0.3)
		edge.position = Vector2(0, y)
		edge.size = Vector2(band.size.x, 6)
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.add_child(edge)
	var portrait: TextureRect = UiKit.portrait(unit.sprite_id, 200)
	portrait.position = Vector2(-220, 10)
	band.add_child(portrait)
	var who: Label = UiKit.label(unit.name, 24, UiKit.TEXT)
	who.position = Vector2(760, 52)
	band.add_child(who)
	var name_label: Label = UiKit.label(skill_name, 48, UiKit.GOLD)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 10)
	name_label.position = Vector2(760, 96)
	band.add_child(name_label)
	band.modulate.a = 0.0
	var tween: Tween = band.create_tween()
	tween.tween_property(band, "modulate:a", 1.0, 0.08)
	tween.parallel().tween_property(portrait, "position:x", 40.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(who, "position:x", 268.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(name_label, "position:x", 268.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.45)
	tween.tween_property(band, "modulate:a", 0.0, 0.15)
	tween.tween_callback(band.queue_free)
	await tween.finished


func _remove_fallen() -> void:
	_refresh_all()
	for u: BattleUnit in state.units:
		var token: UnitToken = _tokens[u.uid]
		if not u.alive() and token.visible:
			await token.fade_out()


## 피해 숫자: 남색 상자에 흰 숫자 (고전 삼국지3처럼). 맞은 칸 위에 톡 튀어나왔다가 사라진다.
func _damage_box(cell: Vector2i, amount: int) -> void:
	var box: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("1c2a6b")
	style.border_color = Color.WHITE
	style.set_border_width_all(3)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	box.add_theme_stylebox_override("panel", style)
	var l: Label = UiKit.label(Fmt.num(amount), 36, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_effects.add_child(box)
	box.reset_size()
	box.position = _center(cell) - Vector2(box.size.x / 2.0, CELL * 0.62)
	box.pivot_offset = box.size / 2.0
	box.scale = Vector2(0.4, 0.4)
	var tween: Tween = box.create_tween()
	tween.tween_property(box, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.65)
	tween.tween_property(box, "modulate:a", 0.0, 0.2)
	tween.tween_callback(box.queue_free)


func _popup(cell: Vector2i, text: String, color: Color) -> void:
	var l: Label = UiKit.label(text, 36, color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	l.position = Vector2(cell) * CELL + Vector2(8, 10)
	_effects.add_child(l)
	var tween: Tween = l.create_tween().set_parallel()
	tween.tween_property(l, "position:y", l.position.y - 40, 0.7)
	tween.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.3)
	tween.chain().tween_callback(l.queue_free)


# ── 차례 진행 ───────────────────────────────────

func _end_turn() -> void:
	_set_mode("busy")
	state.end_phase()                  # → 적 차례
	await _run_ai_phase()
	if state.check_end() != "":
		_finish()
		return
	state.end_phase()                  # → 다음 턴 아군 차례
	if state.check_end() != "":        # 제한 턴
		_finish()
		return
	_set_mode("idle")


func _auto_turn() -> void:
	_set_mode("busy")
	await _run_ai_phase()
	if state.check_end() != "":
		_finish()
		return
	_end_turn()


## 지금 편의 남은 부대를 AI로 하나씩, 보이게 움직인다
func _run_ai_phase() -> void:
	_refresh_all()
	for unit: BattleUnit in state.living(state.phase):
		if state.check_end() != "":
			return
		if unit.done():
			continue
		# 적 장수가 옆의 아군 장수에게 결투를 걸어올 수 있다 (받으면 그 결투가 이 부대의 행동)
		if await _ai_challenge(unit):
			_refresh_all()
			continue
		var p: Dictionary = BattleAI.plan(state, unit)
		if p["move"] != unit.cell:
			await (_tokens[unit.uid] as UnitToken).walk(BattleRules.path(state, unit, p["move"]))
		BattleRules.move_unit(state, unit, p["move"])
		match p["action"]:
			"attack":
				await _animate_attack(unit, p["target"])
			"skill":
				await _animate_skill(unit, p["skill"], p["cell"])
			"gate":
				await _animate_gate(unit, p["cell"])
			_:
				unit.acted = true
		_refresh_all()


func _ask_retreat() -> void:
	var box: VBoxContainer = UiKit.vbox(12)
	box.add_child(UiKit.label(tr("BATTLE_RETREAT_CONFIRM"), 24, UiKit.TEXT, true))
	var retreat: Button = UiKit.button(tr("BATTLE_RETREAT"))
	box.add_child(retreat)
	var modal: Modal = Modal.open(_hud, box, "BATTLE_CANCEL")
	retreat.pressed.connect(func() -> void:
		modal.close()
		state.result = "lose"
		_finish())


func _finish() -> void:
	_set_mode("ended")
	var outcome: Dictionary = BattleOutcome.apply(state)
	BattleSession.state = null
	if SaveManager.game_in_progress:
		SaveManager.save_game(SaveManager.AUTO_SLOT)
	var box: VBoxContainer = UiKit.vbox(8)
	box.add_child(UiKit.label(tr("BATTLE_WIN" if outcome["won"] else "BATTLE_LOSE"), 36, UiKit.GOLD if outcome["won"] else UiKit.BAD))
	for line: String in outcome["lines"]:
		box.add_child(UiKit.label(line, 24, UiKit.TEXT, true))
	box.add_child(UiKit.spacer(8))
	box.add_child(UiKit.label(tr("BATTLE_REPORT_TITLE"), 24, UiKit.MUTED))
	for line: String in outcome["report"]:
		box.add_child(UiKit.label(line, 24, UiKit.MUTED, true))
	var modal: Modal = Modal.open(_hud, box, "BATTLE_BACK")
	modal.closed.connect(func() -> void: get_tree().change_scene_to_file("res://ui/map/map_screen.tscn"))


# ── 공성 ────────────────────────────────────────

## 공격할 수 있는 칸: 적 부대 + (성을 치는 편이면) 성문
func _attack_cells(u: BattleUnit) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for t: BattleUnit in BattleRules.attack_targets(state, u, u.cell):
		cells.append(t.cell)
	for g: Vector2i in BattleRules.gate_targets(state, u, u.cell):
		cells.append(g)
	return cells


func _animate_gate(unit: BattleUnit, cell: Vector2i) -> void:
	await (_tokens[unit.uid] as UnitToken).lunge(cell)
	BattleFx.play(_effects, "thud", _center(cell), _center(cell), Color(1, 0.8, 0.45), 0.3)
	var r: Dictionary = BattleRules.attack_gate(state, unit, cell)
	_damage_box(cell, r["damage"])
	if r["broken"]:
		_paint_terrain(cell)
		_popup(cell + Vector2i(0, 1) if cell.y < state.height - 1 else cell, tr("BATTLE_GATE_BROKEN"), Color(1, 0.9, 0.4))
	await get_tree().create_timer(0.3).timeout
	_refresh_all()


## 공성전 안내 한 줄: 성문 내구도, 거점, 버티기 턴
func _siege_line() -> String:
	if state.mode == "field":
		return ""
	var parts: PackedStringArray = []
	var max_hp: int = int(DataDB.get_row("terrain", "gate").get("hp", 500))
	for g: Vector2i in state.gate_hp:
		parts.append(tr("BATTLE_GATE_LINE") % [maxi(0, int(state.gate_hp[g])), max_hp])
	parts.append(tr("BATTLE_HINT_KEEP") if state.mode == "siege_attack" else tr("BATTLE_HINT_DEFEND") % state.turn_limit)
	return "\n" + " · ".join(parts)


# ── 포상 ────────────────────────────────────────

## [포상 금 N] 버튼 (줄 수 없으면 꺼짐)
func _bonus_button() -> Array:
	var ok: bool = BattleRules.bonus_check(state, _selected) == ""
	# 오를 사기는 일부러 안 보여 준다 — 돈만 먹히는 순간을 같이 보며 웃는 게 재미 (기획 확정)
	return [tr("BATTLE_BONUS") % BattleRules.bonus_cost(_selected), _give_bonus, ok]


func _give_bonus() -> void:
	var reason: String = BattleRules.bonus_check(state, _selected)
	if reason != "":
		_preview.text = tr(reason)
		return
	var cost: int = BattleRules.bonus_cost(_selected)
	var gained: int = BattleRules.give_bonus(state, _selected)
	_popup(_selected.cell, tr("BATTLE_BONUS_POP") % gained if gained > 0 else tr("BATTLE_BONUS_POP_NONE"), Color(1, 0.85, 0.3))
	var mode: String = _mode
	_set_mode(mode)   # 버튼·정보 다시 그리기 (행동은 쓰지 않음)
	_preview.text = tr("BATTLE_BONUS_DONE" if gained > 0 else "BATTLE_BONUS_WASTED") % [_selected.name, cost, _selected.morale]


# ── 결투 ────────────────────────────────────────

func _pair_key(x: BattleUnit, y: BattleUnit) -> String:
	return "%d|%d" % [mini(x.uid, y.uid), maxi(x.uid, y.uid)]


## AI 부대가 결투를 걸까? 옆에 결투해 보지 않은 아군(주인공 편) 장수가 있고, 성격·무력 차이로 마음이 동하면.
## 플레이어가 받으면 결투, 거절하면 그 아군 부대 사기 하락. 결투를 했으면 true (이 부대의 행동은 끝)
func _ai_challenge(unit: BattleUnit) -> bool:
	if unit.officer_id == "" or unit.team != "enemy" or unit.troops <= 0:
		return false
	var target: BattleUnit = null
	for other: BattleUnit in state.living("ally"):
		if other.officer_id != "" and BattleRules.distance(other.cell, unit.cell) == 1 and not _dueled.has(_pair_key(unit, other)):
			target = other
			break
	if target == null or not Duel.wants_to_challenge(unit.officer_id, target.officer_id):
		return false
	_dueled[_pair_key(unit, target)] = true
	# 묻기: 받는다 / 거절한다
	var box: VBoxContainer = UiKit.vbox(12)
	box.add_child(TalkPopup.build(unit.officer_id, VisitAction.speech_variant("DUEL_AI_CHALLENGE"), []))
	box.add_child(UiKit.label(tr("DUEL_AI_ASK") % [unit.name, target.name, absi(int(Duel.cfg("refuse_morale", -10)))], 24, UiKit.TEXT, true))
	var accept: Button = UiKit.button(tr("DUEL_ACCEPT"), Callable(), 88)
	box.add_child(accept)
	var modal: Modal = Modal.open(_hud, box, "DUEL_DECLINE")
	var chose: Array = [false]
	accept.pressed.connect(func() -> void:
		chose[0] = true
		modal.close())
	await modal.closed
	if not chose[0]:
		target.morale = clampi(target.morale + int(Duel.cfg("refuse_morale", -10)), 0, 100)
		_preview.text = tr("DUEL_DECLINED") % target.name
		_refresh_all()
		return false
	var panel: DuelPanel = DuelPanel.open(_hud, target.officer_id, unit.officer_id)
	var result: Array = await panel.finished
	var lines: Array = Duel.apply_battle(state, target, unit, result[1])
	unit.acted = true
	await _remove_fallen()
	_preview.text = "\n".join(lines)
	return true


## 장수끼리 맞붙었을 때 결투 신청. 상대가 거절하면 그 부대 사기가 떨어지고, 행동은 그대로 남는다.
func _challenge_duel(target: BattleUnit) -> void:
	var me: BattleUnit = _selected
	if not Duel.accepts(me.officer_id, target.officer_id):
		target.morale = clampi(target.morale + int(Duel.cfg("refuse_morale", -10)), 0, 100)
		_preview.text = tr("DUEL_REFUSED") % target.name
		_popup(target.cell, tr("BATTLE_DAMAGE") % absi(int(Duel.cfg("refuse_morale", -10))), Color(0.8, 0.8, 1))
		_refresh_all()
		return
	_set_mode("busy")
	var panel: DuelPanel = DuelPanel.open(_hud, me.officer_id, target.officer_id)
	var result: Array = await panel.finished
	_dueled[_pair_key(me, target)] = true
	var lines: Array = Duel.apply_battle(state, me, target, result[1])
	me.acted = true
	await _remove_fallen()
	_preview.text = "\n".join(lines)
	var keep: String = _preview.text
	_after_player_action()
	_preview.text = keep
