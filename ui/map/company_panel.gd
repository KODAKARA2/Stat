class_name CompanyPanel
extends PanelContainer
## [용병단] 탭: 나의 출세 — 신분·명성·공적·다음 승진 조건, 봉신 정보(나라·영지·이번 달 임무),
## 용병단(결성·계약), 동료(월급·해고), 고용 부대.

signal toast_requested(text: String)
signal modal_requested(content: Control)
signal acted

var _content: VBoxContainer


func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.flat_style(UiKit.PANEL_BG, 0, 16))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_content = UiKit.vbox(10)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	refresh()


func refresh() -> void:
	UiKit.clear(_content)
	var me: String = GameState.player_id
	var s: Dictionary = GameState.player()
	_content.add_child(UiKit.label(tr("COMPANY_TAB_TITLE"), 36, UiKit.GOLD))
	_content.add_child(UiKit.label(tr("COMPANY_STATUS") % [Officers.rank_label(me), int(s.get("fame", 0)), int(s.get("merit", 0))], 24, UiKit.TEXT, true))
	_content.add_child(UiKit.label(Career.next_rank_text(me), 24, UiKit.MUTED, true))
	_content.add_child(UiKit.label("■ " + MercGrade.status_line(me), 24, UiKit.GOLD, true))
	_content.add_child(UiKit.label(tr("GRADE_PERKS") % [int(round((MercGrade.pay_mult(me) - 1.0) * 100))], 24, UiKit.MUTED, true))
	if int(s.get("betrayals", 0)) > 0:
		_content.add_child(UiKit.label(tr("COMPANY_BETRAYALS") % int(s["betrayals"]), 24, UiKit.BAD))

	if Career.is_vassal(me):
		_build_vassal(me, s)
	else:
		_build_company(me, s)
	_build_companions(me)
	_build_family(me)


func _build_vassal(me: String, s: Dictionary) -> void:
	_content.add_child(UiKit.label("■ " + tr("COMPANY_VASSAL") % [Officers.nation_label(me), Officers.rank_label(me)], 24, UiKit.GOLD))
	var city: String = Career.governs(me)
	if city != "":
		_content.add_child(UiKit.label(tr("COMPANY_GOVERNS") % UiKit.city_name(city), 24, UiKit.TEXT))
	var m: Dictionary = s.get("mission", {})
	if m.is_empty():
		_content.add_child(UiKit.label(tr("COMPANY_NO_MISSION"), 24, UiKit.MUTED))
	else:
		_content.add_child(UiKit.label(tr("COMPANY_MISSION") % [Career.mission_text(m), int(m["done"]), int(m["need"])], 24, UiKit.TEXT, true))


func _build_company(me: String, s: Dictionary) -> void:
	_content.add_child(UiKit.label("■ " + tr("TAB_COMPANY"), 24, UiKit.GOLD))
	if Career.has_company(me):
		_content.add_child(UiKit.label(tr("COMPANY_NAME_LINE") % s["company"]["name"], 24, UiKit.TEXT))
		var c: Dictionary = Career.contract(me)
		if c.is_empty():
			_content.add_child(UiKit.label(tr("COMPANY_NO_CONTRACT"), 24, UiKit.MUTED))
		else:
			_content.add_child(UiKit.label(tr("COMPANY_CONTRACT") % [Diplomacy.nation_name(c["employer"]), int(c["months_left"]), Fmt.num(int(c["pay"]))], 24, UiKit.TEXT, true))
	else:
		_content.add_child(UiKit.label(tr("COMPANY_NONE"), 24, UiKit.MUTED))
		var form: Button = UiKit.button(tr("COMPANY_FORM"), func() -> void:
			var r: Dictionary = Actions.execute("form_company", me, {})
			toast_requested.emit(r["reason"] if not r["ok"] else "\n".join(r["lines"]))
			refresh()
			acted.emit())
		form.disabled = Actions.can_execute("form_company", me) != ""
		_content.add_child(form)
	_content.add_child(UiKit.label(tr("COMPANY_HOW_TO_SERVE"), 24, UiKit.MUTED, true))


func _build_companions(me: String) -> void:
	var list: Array = Career.companions(me)
	_content.add_child(UiKit.label("■ " + tr("COMPANY_COMPANIONS") % [list.size(), Career.companion_slots(me)], 24, UiKit.GOLD))
	if list.is_empty():
		_content.add_child(UiKit.label(tr("COMPANY_NO_COMPANIONS"), 24, UiKit.MUTED, true))
	for id: String in list:
		var dismiss: Button = UiKit.button(tr("COMPANY_DISMISS"), func() -> void:
			var r: Dictionary = Actions.execute("dismiss", me, {"target": id})
			toast_requested.emit("\n".join(r["lines"]) if r["ok"] else r["reason"])
			refresh()
			acted.emit())
		var row: PanelContainer = UiKit.officer_row(id, [dismiss], func(oid: String) -> void: modal_requested.emit(OfficerCard.build(oid)))
		_content.add_child(row)
		_content.add_child(UiKit.label("   " + tr("COMPANY_WAGE") % Career.wage(id), 24, UiKit.MUTED))


## 가족과 맹우: 배우자·연인·자녀(나이·종족)·맹우. 승계 순서 안내.
func _build_family(me: String) -> void:
	_content.add_child(UiKit.label("■ " + tr("FAMILY_TITLE"), 24, UiKit.GOLD))
	var lines: PackedStringArray = []
	var sp: String = Family.spouse(me)
	if sp != "":
		lines.append(tr("FAMILY_SPOUSE") % Officers.display_name(sp))
	for lover: String in Relationship.with_tag(me, "lover"):
		if Officers.is_active(lover):
			lines.append(tr("FAMILY_LOVER") % Officers.display_name(lover))
	for child: String in Family.children(me):
		var s: Dictionary = Officers.get_state(child)
		lines.append(tr("FAMILY_CHILD") % [Officers.display_name(child), int(s.get("age", 0)), Officers.race_label(child),
			tr("FAMILY_MINOR") if s.get("minor", false) else tr("FAMILY_ADULT_TAG")])
	for friend: String in Relationship.with_tag(me, "sworn"):
		if Officers.is_active(friend):
			lines.append(tr("FAMILY_SWORN") % Officers.display_name(friend))
	if lines.is_empty():
		_content.add_child(UiKit.label(tr("FAMILY_NONE"), 24, UiKit.MUTED, true))
	for line: String in lines:
		_content.add_child(UiKit.label(line, 24, UiKit.TEXT, true))
	var heir: String = Family.heir_of(me)
	_content.add_child(UiKit.label(tr("FAMILY_HEIR") % (Officers.display_name(heir) if heir != "" else tr("FAMILY_NO_HEIR")), 24, UiKit.MUTED, true))
