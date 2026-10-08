class_name EventPanel
extends Control
## 이벤트 대화 창: 장면을 하나씩 넘기고, 선택지를 고르면 효과와 결과를 보여 준다.
## 사용: EventPanel.open(부모) — EventRunner.pending()에 있는 이벤트를 연다. 끝나면 finished 신호.

signal finished

var _event: Dictionary
var _scene_index: int = 0
var _box: VBoxContainer
var _result_lines: Array = []


static func open(parent: Node) -> EventPanel:
	var panel: EventPanel = EventPanel.new()
	parent.add_child(panel)
	return panel


func _ready() -> void:
	_event = EventRunner.find_event(EventRunner.pending().get("id", ""))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	for side: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 140)
	add_child(margin)
	var panel: PanelContainer = UiKit.panel(UiKit.PANEL_BG, 20)
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel") as StyleBoxFlat
	style.border_color = UiKit.GOLD
	style.set_border_width_all(2)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	margin.add_child(panel)
	_box = UiKit.vbox(14)
	panel.add_child(_box)
	if _event.is_empty():
		_finish()
		return
	_show_scene()


func _scenes() -> Array:
	return _event.get("scenes", [])


func _show_scene() -> void:
	UiKit.clear(_box)
	if _scene_index >= _scenes().size():
		_finish()
		return
	var scene: Dictionary = _scenes()[_scene_index]
	if scene.has("choice"):
		_show_choices(scene)
		return
	var speaker: String = EventRunner.speaker_id(scene.get("speaker", "narrator"))
	if speaker != "":
		var head: HBoxContainer = UiKit.hbox(16)
		head.add_child(UiKit.portrait(Officers.get_state(speaker).get("sprite_id", ""), 96))
		var info: VBoxContainer = UiKit.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UiKit.label(Officers.display_name(speaker), 36, UiKit.GOLD))
		info.add_child(UiKit.label("%s · %s" % [Officers.nation_label(speaker), Officers.rank_label(speaker)], 24, UiKit.MUTED))
		head.add_child(info)
		_box.add_child(head)
		var bubble: PanelContainer = UiKit.panel(UiKit.ROW_BG, 16)
		bubble.add_child(UiKit.label("“%s”" % tr(scene.get("text_key", "")), 24, UiKit.TEXT, true))
		_box.add_child(bubble)
	else:
		_box.add_child(UiKit.label(tr(scene.get("text_key", "")), 24, UiKit.TEXT, true))   # 서술
	_box.add_child(UiKit.button(tr("EV_NEXT"), _next, 80))


func _show_choices(scene: Dictionary) -> void:
	# 바로 앞 장면의 문장을 위에 남겨 둔다
	if _scene_index > 0:
		var prev: Dictionary = _scenes()[_scene_index - 1]
		if prev.has("text_key"):
			_box.add_child(UiKit.label(tr(prev["text_key"]), 24, UiKit.MUTED, true))
	for entry: Dictionary in EventRunner.available_choices(scene):
		var ch: Dictionary = entry["choice"]
		var b: Button = UiKit.button(tr(ch.get("text_key", "")), _choose.bind(ch), 80)
		b.disabled = not entry["enabled"]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_box.add_child(b)


func _choose(ch: Dictionary) -> void:
	_result_lines = EventRunner.apply_effects(ch.get("effects", []))
	UiKit.clear(_box)
	_box.add_child(UiKit.label(tr(ch.get("text_key", "")), 24, UiKit.GOLD, true))
	for line: String in _result_lines:
		_box.add_child(UiKit.label(line, 24, UiKit.GOOD, true))
	_scene_index += 1
	var last: bool = _scene_index >= _scenes().size()
	_box.add_child(UiKit.button(tr("EV_CLOSE" if last else "EV_NEXT"), _show_scene, 80))


func _next() -> void:
	_scene_index += 1
	_show_scene()


func _finish() -> void:
	EventRunner.clear_pending()
	finished.emit()
	queue_free()
