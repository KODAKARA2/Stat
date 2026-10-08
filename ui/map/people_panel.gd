class_name PeoplePanel
extends PanelContainer
## [인물] 탭: 나 → 아는 사람 → 나머지 순으로 전체 인물 목록. 누르면 상세.

signal modal_requested(content: Control)

var _content: VBoxContainer


func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.flat_style(UiKit.PANEL_BG, 0, 16))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_content = UiKit.vbox(8)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	refresh()


func refresh() -> void:
	UiKit.clear(_content)
	var player: String = GameState.player_id
	var known: Array = []
	var others: Array = []
	for id: String in GameState.officers:
		if id == player or not Officers.is_active(id):
			continue
		(known if Relationship.has_met(player, id) else others).append(id)
	known.sort_custom(func(a: String, b: String) -> bool: return Relationship.affinity(player, a) > Relationship.affinity(player, b))
	others.sort_custom(func(a: String, b: String) -> bool: return Officers.rank_order(a) > Officers.rank_order(b))

	_content.add_child(UiKit.officer_row(player, [], _show_card))
	_content.add_child(UiKit.label("■ " + tr("PEOPLE_KNOWN") % known.size(), 24, UiKit.GOLD))
	for id: String in known:
		_content.add_child(UiKit.officer_row(id, [], _show_card))
	_content.add_child(UiKit.label("■ " + tr("PEOPLE_OTHERS") % others.size(), 24, UiKit.GOLD))
	for id: String in others:
		_content.add_child(UiKit.officer_row(id, [], _show_card))


func _show_card(id: String) -> void:
	modal_requested.emit(OfficerCard.build(id))
