class_name DuelPanel
extends Control
## 결투 화면 (3수 예약형). 위: 상대 / 가운데: 3칸 대진표(상대 수는 공개 전 ?) / 아래: 나, 기색, 명령 버튼.
## 3수를 고르고 [확정] → 한 수씩 공개하며 해결 (화면을 누르면 빨리 감기). 쓴 수는 턴이 끝나면 무작위로 다시 채워진다.
## 사용: DuelPanel.open(부모, 내 장수 id, 상대 id) → finished(이긴 사람 id 또는 "" , 결투 상태) 신호.

signal finished(winner_id: String, duel: DuelState)

const CMD_COLORS: Dictionary = {
	"thrust": Color(0.78, 0.3, 0.27), "slash": Color(0.85, 0.52, 0.2), "bash": Color(0.66, 0.6, 0.22),
	"dodge": Color(0.22, 0.6, 0.7), "guard": Color(0.4, 0.45, 0.55), "none": Color(0.25, 0.25, 0.25),
	"flash": Color(0.9, 0.75, 0.3), "read": Color(0.55, 0.45, 0.85), "focus": Color(0.35, 0.7, 0.4), "spell": Color(0.7, 0.35, 0.85),
}
const STEP_SECONDS: float = 0.85

var duel: DuelState
var _title: Label
var _rows: Dictionary = {}          # id → {"bar", "label", "hand", "portrait"}
var _foe_slots: Array[PanelContainer] = []
var _my_slots: Array[PanelContainer] = []
var _pool_label: Label
var _log: Label
var _hint: Label
var _buttons: GridContainer
var _footer: HBoxContainer
var _busy: bool = false
var _fast: bool = false


static func open(parent: Node, a_id: String, b_id: String) -> DuelPanel:
	var panel: DuelPanel = DuelPanel.new()
	panel.duel = Duel.start(a_id, b_id)
	parent.add_child(panel)
	return panel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(func(event: InputEvent) -> void:
		if _busy and event is InputEventMouseButton and event.pressed:
			_fast = true)   # 공개 중에 누르면 빨리 감기
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	for side: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var box: PanelContainer = UiKit.panel(UiKit.PANEL_BG, 16)
	var style: StyleBoxFlat = box.get_theme_stylebox("panel") as StyleBoxFlat
	style.border_color = Color(0.9, 0.35, 0.3)
	style.set_border_width_all(3)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	margin.add_child(box)
	var v: VBoxContainer = UiKit.vbox(10)
	box.add_child(v)
	_title = UiKit.label("", 36, Color(1, 0.55, 0.45))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	v.add_child(_fighter_row(duel.b_id))
	# 대진표: 상대 3칸 / 충돌 누적 / 내 3칸
	v.add_child(_slot_row(_foe_slots))
	_pool_label = UiKit.label("", 24, UiKit.GOLD)
	_pool_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_pool_label)
	v.add_child(_slot_row(_my_slots))
	_log = UiKit.label("", 24, UiKit.TEXT, true)
	_log.custom_minimum_size.y = 60
	_log.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_log)
	v.add_child(_fighter_row(duel.a_id))
	_hint = UiKit.label("", 24, UiKit.GOLD, true)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_hint)
	_buttons = GridContainer.new()
	_buttons.columns = 3
	_buttons.add_theme_constant_override("h_separation", 6)
	_buttons.add_theme_constant_override("v_separation", 6)
	v.add_child(_buttons)
	_footer = UiKit.hbox(8)
	v.add_child(_footer)
	_refresh()


func _fighter_row(id: String) -> Control:
	var row: HBoxContainer = UiKit.hbox(12)
	var portrait: TextureRect = UiKit.portrait(Officers.get_state(id).get("sprite_id", ""), 88)
	row.add_child(portrait)
	var info: VBoxContainer = UiKit.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	info.add_child(UiKit.label(Officers.display_name(id), 24, UiKit.GOLD if id == duel.a_id else UiKit.TEXT))
	var bar: ProgressBar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 18)
	bar.add_theme_stylebox_override("fill", UiKit.flat_style(Color(0.45, 0.8, 0.45) if id == duel.a_id else Color(0.9, 0.4, 0.35), 3, 0))
	bar.add_theme_stylebox_override("background", UiKit.flat_style(Color(0.25, 0.23, 0.2), 3, 0))
	info.add_child(bar)
	var label: Label = UiKit.label("", 24, UiKit.MUTED)
	info.add_child(label)
	var hand: Label = UiKit.label("", 24, UiKit.MUTED, true)
	info.add_child(hand)
	_rows[id] = {"bar": bar, "label": label, "hand": hand, "portrait": portrait}
	return row


func _slot_row(store: Array[PanelContainer]) -> HBoxContainer:
	var row: HBoxContainer = UiKit.hbox(8)
	for i: int in Duel.SLOTS:
		var card: PanelContainer = PanelContainer.new()
		card.custom_minimum_size = Vector2(0, 64)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var l: Label = UiKit.label("", 24, Color.WHITE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 6)
		card.add_child(l)
		row.add_child(card)
		store.append(card)
	return row


func _set_card(card: PanelContainer, cmd: String, text: String = "", highlight: bool = false) -> void:
	var color: Color = CMD_COLORS.get(cmd, Color(0.18, 0.17, 0.15))
	var st: StyleBoxFlat = UiKit.flat_style(color if cmd != "" else Color(0.18, 0.17, 0.15), 8, 4)
	st.border_color = Color.WHITE if highlight else color.lightened(0.3)
	st.set_border_width_all(4 if highlight else (2 if cmd != "" else 1))
	card.add_theme_stylebox_override("panel", st)
	(card.get_child(0) as Label).text = text if text != "" else (_cmd_name(cmd) if cmd != "" else "")


static func _cmd_name(cmd: String) -> String:
	return TranslationServer.translate("DUEL_CMD_" + cmd.to_upper())


func _stats(id: String, hp_value: int, sp_value: int) -> void:
	var r: Dictionary = _rows[id]
	(r["bar"] as ProgressBar).max_value = int(duel.max_hp[id])
	(r["bar"] as ProgressBar).value = hp_value
	(r["label"] as Label).text = tr("DUEL_HP") % [hp_value, int(duel.max_hp[id]), sp_value]


func _hand_text(id: String) -> String:
	var parts: PackedStringArray = []
	for c: String in ["thrust", "slash", "bash", "dodge"]:
		parts.append("%s %d" % [_cmd_name(c), Duel.remaining(duel, id, c)])
	var sp_names: PackedStringArray = []
	for s: String in duel.specials[id]:
		sp_names.append(_cmd_name(s))
	var text: String = " · ".join(parts)
	if not sp_names.is_empty():
		text += "\n" + tr("DUEL_SPECIALS") % ", ".join(sp_names)
	return text


## 예약 중 화면 (턴 시작 / 수를 고를 때마다)
func _refresh() -> void:
	_title.text = tr("DUEL_TITLE") % [mini(duel.turn, int(Duel.cfg("turns", 5))), int(Duel.cfg("turns", 5))]
	for id: String in [duel.a_id, duel.b_id]:
		_stats(id, int(duel.hp[id]), int(duel.sp[id]))
		(_rows[id]["hand"] as Label).text = _hand_text(id)
	var plan: Array = duel.plan[duel.a_id]
	for i: int in Duel.SLOTS:
		var foe_text: String = "?"
		if duel.stunned[duel.b_id] and i == 0:
			foe_text = tr("DUEL_STUNNED_SLOT")
		_set_card(_foe_slots[i], "", foe_text)
		var mine: String = String(plan[i]) if i < plan.size() else ""
		var mine_text: String = "" if mine != "" else (tr("DUEL_STUNNED_SLOT") if duel.stunned[duel.a_id] and i == 0 else "%d" % (i + 1))
		_set_card(_my_slots[i], mine, mine_text, i == plan.size())
	_pool_label.text = tr("DUEL_POOL") % duel.pool if duel.pool > 0 else tr("DUEL_RULE_LINE")
	_hint.text = tr("DUEL_HINT_LINE") % [int(duel.hint.get("slot", 0)) + 1, tr("DUEL_KIND_" + String(duel.hint.get("kind", "attack")).to_upper())]
	UiKit.clear(_buttons)
	UiKit.clear(_footer)
	if duel.finished():
		_show_result()
		return
	for c: String in Duel.BASICS + (duel.specials[duel.a_id] as Array):
		var left: int = Duel.remaining(duel, duel.a_id, c)
		var label: String = _cmd_name(c)
		if Duel.SPECIALS.has(c):
			label += "\n" + tr("DUEL_SP_COST") % Duel.sp_cost(c)
		else:
			label += "\n" + ("∞" if left < 0 else "×%d" % left)
		var b: Button = UiKit.button(label, _pick.bind(c), 72)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = Duel.can_add(duel, duel.a_id, c) != ""
		var st: StyleBoxFlat = UiKit.flat_style(CMD_COLORS[c].darkened(0.35), 6, 6)
		st.border_color = CMD_COLORS[c]
		st.set_border_width_all(2)
		b.add_theme_stylebox_override("normal", st)
		_buttons.add_child(b)
	var undo: Button = UiKit.button(tr("DUEL_UNDO"), func() -> void:
		Duel.remove_last(duel, duel.a_id)
		_refresh(), 72)
	undo.disabled = plan.is_empty()
	undo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.add_child(undo)
	var help: Button = UiKit.button("?", _show_help, 72)
	help.custom_minimum_size.x = 72
	_footer.add_child(help)
	var go: Button = UiKit.button(tr("DUEL_CONFIRM") % plan.size(), _confirm, 72)
	go.disabled = plan.size() < Duel.SLOTS
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.add_child(go)


func _pick(cmd: String) -> void:
	Duel.add(duel, duel.a_id, cmd)
	_refresh()


## 확정: 한 수씩 공개하며 보여 준다
func _confirm() -> void:
	if _busy:
		return
	_busy = true
	_fast = false
	var my_plan: Array = (duel.plan[duel.a_id] as Array).duplicate()
	var foe_plan: Array = (duel.plan[duel.b_id] as Array).duplicate()
	UiKit.clear(_buttons)
	UiKit.clear(_footer)
	_hint.text = ""
	var steps: Array = Duel.resolve_turn(duel)
	for i: int in Duel.SLOTS:
		_set_card(_foe_slots[i], "", "?")
		_set_card(_my_slots[i], String(my_plan[i]))
	for step: Dictionary in steps:
		var i: int = int(step["slot"])
		_set_card(_foe_slots[i], step["b_cmd"], "", true)
		_set_card(_my_slots[i], step["a_cmd"], "", true)
		_log.text = String(step["text"])
		for id: String in [duel.a_id, duel.b_id]:
			_stats(id, int(step["hp"][id]), int(step["sp"][id]))
		_pool_label.text = tr("DUEL_POOL") % int(step["pool"]) if int(step["pool"]) > 0 else ""
		if int(step["a_dmg"]) > 0:
			_hit(duel.a_id, int(step["a_dmg"]))
		if int(step["b_dmg"]) > 0:
			_hit(duel.b_id, int(step["b_dmg"]))
		if (step["events"] as Array).has("clash"):
			_flash_cards(i)
		await get_tree().create_timer(STEP_SECONDS * (0.25 if _fast else 1.0)).timeout
		_set_card(_foe_slots[i], step["b_cmd"])
		_set_card(_my_slots[i], step["a_cmd"])
	# 아직 안 나온 상대 수도 보여 준다 (결판이 먼저 났을 때)
	for i: int in range(steps.size(), Duel.SLOTS):
		_set_card(_foe_slots[i], String(foe_plan[i]))
	await get_tree().create_timer(0.4 * (0.25 if _fast else 1.0)).timeout
	_busy = false
	if duel.finished():
		_refresh()
	else:
		_log.text = tr("DUEL_NEXT_TURN") % duel.turn
		_refresh()


func _hit(id: String, amount: int) -> void:
	var p: TextureRect = _rows[id]["portrait"]
	var l: Label = UiKit.label("-%d" % amount, 36, Color(1, 0.45, 0.4))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	p.add_child(l)
	l.position = Vector2(10, 10)
	var tween: Tween = create_tween()
	for k: int in 3:
		tween.tween_property(p, "modulate", Color(1, 0.4, 0.4), 0.05)
		tween.tween_property(p, "modulate", Color.WHITE, 0.05)
	var t2: Tween = l.create_tween()
	t2.tween_property(l, "position:y", -20.0, 0.6)
	t2.parallel().tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.2)
	t2.tween_callback(l.queue_free)


## 충돌: 두 칸이 번쩍
func _flash_cards(i: int) -> void:
	for card: PanelContainer in [_foe_slots[i], _my_slots[i]]:
		var tween: Tween = card.create_tween()
		tween.tween_property(card, "modulate", Color(2, 2, 2), 0.06)
		tween.tween_property(card, "modulate", Color.WHITE, 0.2)


func _show_result() -> void:
	var w: String = duel.winner()
	var key: String = "DUEL_DRAW" if w == "" else ("DUEL_WIN" if w == duel.a_id else "DUEL_LOSE")
	_title.text = tr(key)
	_title.add_theme_color_override("font_color", UiKit.GOLD if w == duel.a_id else (UiKit.TEXT if w == "" else UiKit.BAD))
	_hint.text = ""
	var ok: Button = UiKit.button(tr("DUEL_BUTTON_OK"), _close, 88)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.add_child(ok)


func _show_help() -> void:
	var box: VBoxContainer = UiKit.vbox(8)
	box.add_child(UiKit.label(tr("DUEL_HELP_TITLE"), 36, UiKit.GOLD))
	box.add_child(UiKit.label(tr("DUEL_HELP_BODY"), 24, UiKit.TEXT, true))
	Modal.open(self, box)


func _close() -> void:
	finished.emit(duel.winner(), duel)
	queue_free()
