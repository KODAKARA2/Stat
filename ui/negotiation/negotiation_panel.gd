class_name NegotiationPanel
extends Control
## 설전 화면: 상대 초상화·눈치 힌트·설득 게이지, [논리][감정][위세] 3택.
## 사용: NegotiationPanel.open(부모, 설전 상태) → finished(결과 문장들) 신호. 결과 반영은 닫을 때 한 번.

signal finished(lines: Array)

var nego: Dictionary
var _title: Label
var _bar: ProgressBar
var _gauge: Label
var _hint: Label
var _log: Label
var _buttons: HBoxContainer
var _result: Array = []


static func open(parent: Node, n: Dictionary) -> NegotiationPanel:
	var panel: NegotiationPanel = NegotiationPanel.new()
	panel.nego = n
	parent.add_child(panel)
	return panel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	for side: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 120)
	add_child(margin)
	var box: PanelContainer = UiKit.panel(UiKit.PANEL_BG, 20)
	var style: StyleBoxFlat = box.get_theme_stylebox("panel") as StyleBoxFlat
	style.border_color = Color(0.4, 0.7, 0.95)
	style.set_border_width_all(3)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	margin.add_child(box)
	var v: VBoxContainer = UiKit.vbox(12)
	box.add_child(v)
	_title = UiKit.label("", 36, Color(0.6, 0.85, 1.0))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	v.add_child(UiKit.label(tr("NEGO_KIND_" + String(nego["kind"]).to_upper()), 24, UiKit.MUTED, true))
	# 상대
	var row: HBoxContainer = UiKit.hbox(16)
	row.add_child(UiKit.portrait(Officers.get_state(nego["target"]).get("sprite_id", ""), 112))
	var info: VBoxContainer = UiKit.vbox(4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	info.add_child(UiKit.label(Officers.display_name(nego["target"]), 36, UiKit.TEXT))
	info.add_child(UiKit.label(Officers.rank_label(nego["target"]) + " · " + Officers.nation_label(nego["target"]), 24, UiKit.MUTED))
	v.add_child(row)
	_hint = UiKit.label("", 24, UiKit.GOLD, true)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_hint)
	# 설득 게이지
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 26)
	_bar.add_theme_stylebox_override("fill", UiKit.flat_style(Color(0.4, 0.7, 0.95), 3, 0))
	_bar.add_theme_stylebox_override("background", UiKit.flat_style(Color(0.25, 0.23, 0.2), 3, 0))
	v.add_child(_bar)
	_gauge = UiKit.label("", 24, UiKit.MUTED)
	_gauge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_gauge)
	_log = UiKit.label("", 24, UiKit.TEXT, true)
	_log.custom_minimum_size.y = 64
	_log.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_log)
	_buttons = UiKit.hbox(8)
	v.add_child(_buttons)
	_refresh()


func _refresh() -> void:
	var rounds: int = int(nego["rounds"])
	_title.text = tr("NEGO_TITLE") % [mini(int(nego["round"]), rounds), rounds]
	_bar.max_value = int(nego["goal"])
	_bar.value = mini(int(nego["gauge"]), int(nego["goal"]))
	_gauge.text = tr("NEGO_GAUGE") % [mini(int(nego["gauge"]), int(nego["goal"])), int(nego["goal"])]
	UiKit.clear(_buttons)
	if Negotiation.finished(nego):
		var ok: bool = Negotiation.succeeded(nego)
		if nego["kind"] == "contract":
			_title.text = tr("NEGO_CONTRACT_END") % int(round(Negotiation.pay_mult(nego) * 100))
			_title.add_theme_color_override("font_color", UiKit.GOLD)
		else:
			_title.text = tr("NEGO_WIN" if ok else "NEGO_LOSE")
			_title.add_theme_color_override("font_color", UiKit.GOLD if ok else UiKit.BAD)
		_hint.text = ""
		if _result.is_empty():
			_result = Negotiation.apply(nego)
		var close: Button = UiKit.button(tr("NEGO_OK"), _close, 88)
		close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_buttons.add_child(close)
		return
	_hint.text = tr("NEGO_HINT_" + String(nego["hint"]).to_upper()) % Officers.display_name(nego["target"])
	for a: String in Negotiation.APPROACHES:
		var b: Button = UiKit.button(tr("NEGO_" + a.to_upper()) % Negotiation.power_stat(nego["actor"], a), _play.bind(a), 96)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_buttons.add_child(b)


func _play(approach: String) -> void:
	var r: Dictionary = Negotiation.play(nego, approach)
	_log.text = tr("NEGO_SAID_" + approach.to_upper()) + "\n" + tr("NEGO_REACT_" + String(r["reaction"]).to_upper()) % int(r["gain"])
	_refresh()


func _close() -> void:
	finished.emit(_result)
	queue_free()
