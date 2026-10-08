class_name CityPanel
extends PanelContainer
## [도시] 탭: 주인공이 있는 도시에서 할 수 있는 행동(수행·휴식)과 그 도시 인물(방문·교류).

signal toast_requested(text: String)
signal modal_requested(content: Control)
signal acted                        # 행동을 해서 화면(행동력 등)을 새로 그려야 할 때
signal duel_requested(a_id: String, b_id: String)   # 술집 시비 → 지도 화면이 결투 창을 띄운다
signal battle_requested(quest: Dictionary)          # 출진 → 전투 화면으로
signal negotiation_requested(nego: Dictionary)      # 설전 → 지도 화면이 설전 창을 띄운다

const LOG_LINES: int = 6

var _content: VBoxContainer
var _log: Array[String] = []
var _train_open: bool = false


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
	var player: String = GameState.player_id
	var city: String = Officers.get_state(player).get("city", "")
	var row: Dictionary = DataDB.get_row("cities", city)
	var nation: Dictionary = Nations.row(GameState.city_owner(city))

	_content.add_child(UiKit.label(UiKit.city_name(city), 36, Color.html(nation.get("color", "#cccccc")).lightened(0.25)))
	_content.add_child(UiKit.label(tr(row.get("desc_key", "")), 24, UiKit.MUTED, true))

	# 내 행동
	_content.add_child(UiKit.label("■ " + tr("CITY_MY_ACTIONS"), 24, UiKit.GOLD))
	var actions: GridContainer = GridContainer.new()
	actions.columns = 3
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	_content.add_child(actions)
	var train: Button = UiKit.button(_action_text("ACTION_TRAIN", "train"), func() -> void:
		_train_open = not _train_open
		refresh())
	var rest: Button = UiKit.button(_action_text("ACTION_REST", "rest"), _do.bind("rest", {}, ""))
	var tavern: Button = UiKit.button(_action_text("CITY_TAVERN", "tavern"), _tavern)
	var shop: Button = UiKit.button(tr("CITY_SHOP") + "\n" + tr("UI_AP_FREE"), _open_shop)
	var row_buttons: Array = [train, rest, tavern, shop]
	if not Career.is_vassal(player) and GameState.city_owner(city) != "" and Officers.rank_order(player) >= int(Career.cfg("serve", "min_rank_order", 2)):
		row_buttons.append(UiKit.button(_action_text("CITY_SERVE", "serve"), _serve))
	for b: Button in row_buttons:
		b.custom_minimum_size.y = 88
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(b)
	if _train_open:
		_content.add_child(_build_train_choices(player))

	_build_govern(player, city)
	_build_conquest(player, city)
	_build_guild(player, city)

	# 이 도시의 인물
	var people: PackedStringArray = Officers.in_city(city, player)
	_content.add_child(UiKit.label("■ " + tr("CITY_PEOPLE_HERE") % people.size(), 24, UiKit.GOLD))
	if people.is_empty():
		_content.add_child(UiKit.label(tr("CITY_NOBODY"), 24, UiKit.MUTED))
	for id: String in people:
		var visit: Button = UiKit.button(tr("ACTION_VISIT"), _do.bind("visit", {"target": id}, id))
		var interact: Button = UiKit.button(tr("ACTION_INTERACT_SHORT"), _do.bind("interact", {"target": id}, id))
		var buttons: Array = [visit, interact]
		if Career.is_free_agent(id):
			buttons.append(UiKit.button(tr("ACTION_RECRUIT"), _do.bind("recruit", {"target": id}, id)))
			buttons.append(UiKit.button(tr("NEGO_BTN_RECRUIT"), _negotiate.bind({"kind": "recruit", "target": id})))
		# 관계 행동: 할 수 있는 것 하나만 (청혼 > 고백 > 맹세)
		var rel_checks: Dictionary = {"propose": Family.can_propose(player, id), "confess": Family.can_confess(player, id), "swear": Family.can_swear(player, id)}
		for rel: String in ["propose", "confess", "swear"]:
			if rel_checks[rel] == "":
				buttons.append(UiKit.button(tr("ACTION_" + rel.to_upper()), _do.bind(rel, {"target": id}, id)))
				break
		_content.add_child(UiKit.officer_row(id, buttons, _show_card))

	# 최근 결과
	if not _log.is_empty():
		_content.add_child(UiKit.label("■ " + tr("CITY_LOG"), 24, UiKit.GOLD))
		for line: String in _log:
			_content.add_child(UiKit.label(line, 24, UiKit.TEXT, true))


## 용병 길드: 받은 의뢰(여기서 출발 가능하면 [출발]) + 이 도시 게시판(수주)
func _build_guild(player: String, city: String) -> void:
	_content.add_child(UiKit.label("■ " + tr("CITY_GUILD_SECTION"), 24, UiKit.GOLD))
	var mine: Array = Guild.active_quests(player)
	if not mine.is_empty():
		_content.add_child(UiKit.label(tr("GUILD_MY_QUESTS"), 24, UiKit.MUTED))
		for q: Dictionary in mine:
			var go: Button = UiKit.button(tr("GUILD_GO") + "\n" + tr("UI_AP_COST") % Actions.ap_cost("subjugate", player), _start_quest.bind(q["id"]), 88)
			go.disabled = q["city"] != city
			_content.add_child(_quest_row(q, go, true))
	var board: Array = Guild.city_quests(city)
	if board.is_empty():
		_content.add_child(UiKit.label(tr("GUILD_NO_QUEST"), 24, UiKit.MUTED))
	for q: Dictionary in board:
		_content.add_child(_quest_row(q, UiKit.button(tr("GUILD_ACCEPT"), _accept_quest.bind(q["id"]), 88), false))
		# 용병단 계약은 받기 전에 한 번 보수를 교섭할 수 있다
		if q.get("type", "") == "contract" and not q.get("negotiated", false) and Actions.can_execute("negotiate", player, {"kind": "contract", "quest": q["id"]}) == "":
			_content.add_child(UiKit.button(tr("NEGO_BTN_CONTRACT") + " · " + tr("UI_AP_COST") % Actions.ap_cost("negotiate", player), _negotiate.bind({"kind": "contract", "quest": q["id"]}), 72))
	_build_hire(player)
	var hire_officer: Button = UiKit.button(tr("GUILD_HIRE_OFFICER") % int(Career.cfg("hire_officer", "cost", 120)), _hire_officer, 88)
	hire_officer.disabled = not Career.has_free_slot(player)
	_content.add_child(hire_officer)


## 용병 고용: 지금 계약 중인 부대 + 고용 버튼(종류별)
func _build_hire(player: String) -> void:
	var hired: Array = Guild.hired(player)
	_content.add_child(UiKit.label(tr("HIRE_TITLE") % [hired.size(), Guild.max_hired(player)], 24, UiKit.MUTED))
	for i: int in hired.size():
		var entry: Dictionary = hired[i]
		var row: Dictionary = Guild.helper_type(entry["type"])
		_content.add_child(UiKit.label("· " + tr("HIRE_LINE") % [Guild.hired_name(entry["type"], i + 1), Fmt.num(int(entry["troops"])), Fmt.num(int(row.get("troops", 0))), int(entry["months"])], 24, UiKit.TEXT, true))
	var buttons: HBoxContainer = UiKit.hbox(8)
	_content.add_child(buttons)
	for row: Dictionary in Guild.cfg("helper_types", []):
		var unit_name: String = tr(DataDB.get_row("unit_types", row["unit_type"]).get("name_key", ""))
		var b: Button = UiKit.button(tr("HIRE_BUTTON") % [unit_name, Guild.hire_cost(player, row["id"])], _hire.bind(row["id"]), 88)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = hired.size() >= Guild.max_hired(player)
		buttons.add_child(b)


func _hire(type_id: String) -> void:
	var result: Dictionary = Actions.execute("hire", GameState.player_id, {"type": type_id})
	toast_requested.emit(result["reason"] if not result["ok"] else "\n".join(result["lines"]))
	refresh()
	acted.emit()


func _quest_row(q: Dictionary, action: Button, show_city: bool) -> PanelContainer:
	var row: PanelContainer = UiKit.panel(UiKit.ROW_BG, 10)
	var h: HBoxContainer = UiKit.hbox(12)
	row.add_child(h)
	var war: bool = q.get("type", "monster") in ["war", "contract"]
	var side: String = q.get("side", q.get("employer", ""))
	var icon: String = Nations.row(side).get("sprite_id", "") if war else DataDB.get_row("monsters", q["monster"]).get("sprite_id", "")
	h.add_child(UiKit.portrait(icon, 64))
	var info: VBoxContainer = UiKit.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	var title_color: Color = Color.html(Nations.row(side).get("color", "#ffffff")).lightened(0.3) if war \
		else [UiKit.TEXT, UiKit.TEXT, Color(1, 0.75, 0.4), UiKit.BAD][clampi(int(q["tier"]), 0, 3)]
	info.add_child(UiKit.label(Guild.quest_title(q), 24, title_color, true))
	if q.get("type", "") == "war":
		info.add_child(UiKit.label(tr("WAR_QUEST_ENEMY") % Diplomacy.nation_name(q["enemy"]), 24, UiKit.MUTED))
	var deadline: int = int(q["deadline"])
	info.add_child(UiKit.label(tr("GUILD_QUEST_REWARD") % [Fmt.num(MercGrade.pay(GameState.player_id, int(q["gold"]))), int(q["fame"]), (deadline - 1) / 12 + 1, (deadline - 1) % 12 + 1], 24, UiKit.MUTED, true))
	if show_city:
		info.add_child(UiKit.label(tr("GUILD_QUEST_WHERE") % UiKit.city_name(q["city"]), 24, UiKit.MUTED))
	action.custom_minimum_size.x = 120
	h.add_child(action)
	return row


func _accept_quest(quest_id: String) -> void:
	var result: Dictionary = Actions.execute("accept_quest", GameState.player_id, {"quest": quest_id})
	toast_requested.emit(result["reason"] if not result["ok"] else "\n".join(result["lines"]))
	refresh()
	acted.emit()


func _start_quest(quest_id: String) -> void:
	var result: Dictionary = Actions.execute("subjugate", GameState.player_id, {"quest": quest_id})
	if not result["ok"]:
		toast_requested.emit(result["reason"])
		return
	BattleSession.start(result["quest"], get_tree())


func _build_train_choices(player: String) -> GridContainer:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for key: String in Officers.stat_keys():
		var value: int = Officers.base_stat(player, key)
		var text: String = "%s %d" % [Officers.stat_label(key), value]
		if Progression.is_capped(player, key):
			text += "\n" + tr("CARD_CAPPED")
		else:
			text += "\n%d/%d" % [int(Officers.get_state(player)["exp"].get(key, 0)), Progression.exp_needed(value)]
		var b: Button = UiKit.button(text, _do.bind("train", {"stat": key}, ""), 96)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
	return grid


func _action_text(key: String, action_id: String) -> String:
	return tr(key) + "\n" + tr("UI_AP_COST") % Actions.ap_cost(action_id, GameState.player_id)


func _do(action_id: String, params: Dictionary, speaker: String) -> void:
	var result: Dictionary = Actions.execute(action_id, GameState.player_id, params)
	if not result["ok"]:
		toast_requested.emit(result["reason"])
		return
	for line: String in result["lines"]:
		_log.push_front(line)
	_log.resize(mini(_log.size(), LOG_LINES))
	if speaker != "" and result.has("speech"):
		modal_requested.emit(TalkPopup.build(speaker, result["speech"], result["lines"]))
	elif not result["lines"].is_empty():
		toast_requested.emit("\n".join(result["lines"]))
	refresh()
	acted.emit()


func _show_card(id: String) -> void:
	modal_requested.emit(OfficerCard.build(id))


## 영지 통치: 다스리는 도시에 있을 때만 (성주). 개발·방어·징병, 그리고 이웃 적 도시로 출진.
func _build_govern(player: String, city: String) -> void:
	if Career.governs(player) != city:
		return
	var n: String = GameState.city_owner(city)
	_content.add_child(UiKit.label("■ " + tr("CITY_GOVERN_SECTION"), 24, UiKit.GOLD))
	_content.add_child(UiKit.label(tr("GOVERN_TREASURY") % [Diplomacy.nation_name(n), Fmt.num(int(GameState.nations[n]["gold"]))], 24, UiKit.MUTED))
	var gov: GovernAction = Actions.get_action("govern") as GovernAction
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_content.add_child(grid)
	for spec: Array in [["commerce", tr("GOVERN_COMMERCE") % gov.cost(player, "commerce")],
			["agriculture", tr("GOVERN_AGRICULTURE") % gov.cost(player, "agriculture")],
			["defense", tr("GOVERN_DEFENSE_BTN") % gov.cost(player, "defense")],
			["conscript", tr("GOVERN_CONSCRIPT_BTN") % [gov.conscript_amount(player), gov.cost(player, "conscript")]]]:
		var b: Button = UiKit.button(spec[1], _do.bind("govern", {"kind": spec[0]}, ""), 88)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
	for other: String in WorldMap.shared().neighbors(city):
		if Diplomacy.at_war(n, GameState.city_owner(other)):
			var launch: Button = UiKit.button(tr("GOVERN_LAUNCH") % [UiKit.city_name(other), Actions.ap_cost("launch_war", player)], _launch.bind(other), 88)
			_content.add_child(launch)
	# 군주: 전쟁 중인 나라와 휴전 교섭
	if Officers.track(player) == "ruler":
		for other: String in Diplomacy.alive_nations():
			if Diplomacy.at_war(n, other) and Personnel.ruler_of(other) != "":
				_content.add_child(UiKit.button(tr("NEGO_BTN_TRUCE") % [Diplomacy.nation_name(other), Actions.ap_cost("negotiate", player)], _negotiate.bind({"kind": "truce", "nation": other}), 88))
	# 독립 선언: 성주 이상, 아직 군주가 아닐 때
	if Founding.independence_check(player) == "":
		_content.add_child(UiKit.button(tr("FOUND_INDEPENDENCE_BTN") % Actions.ap_cost("declare_independence", player), _declare_independence, 88))


func _negotiate(params: Dictionary) -> void:
	var result: Dictionary = Actions.execute("negotiate", GameState.player_id, params)
	if not result["ok"]:
		toast_requested.emit(result["reason"])
		return
	negotiation_requested.emit(result["negotiation"])
	refresh()
	acted.emit()


func _declare_independence() -> void:
	var player: String = GameState.player_id
	var former: String = Officers.get_state(player).get("nation", "")
	var body: String = tr("FOUND_INDEPENDENCE_BODY") % [UiKit.city_name(Career.governs(player)), Diplomacy.nation_name(former)]
	modal_requested.emit(FoundingDialog.build("FOUND_TITLE", body, tr("FOUND_DEFAULT_NAME") % Officers.display_name(player),
		func(nation_name: String, color: String) -> void:
			_do("declare_independence", {"name": nation_name, "color": color}, "")))


## 용병단 점령전: 용병대장이 용병단을 이끌고 이웃 도시를 쳐서 나라를 세운다
func _build_conquest(player: String, city: String) -> void:
	if Career.is_vassal(player) or not Officers.rank_row(player).get("can_form_company", false) or not Career.has_company(player):
		return
	var targets: Array = []
	for other: String in WorldMap.shared().neighbors(city):
		if GameState.city_owner(other) != "":
			targets.append(other)
	if targets.is_empty():
		return
	_content.add_child(UiKit.label("■ " + tr("CONQUEST_SECTION"), 24, UiKit.GOLD))
	_content.add_child(UiKit.label(tr("CONQUEST_HINT"), 24, UiKit.MUTED, true))
	for other: String in targets:
		_content.add_child(UiKit.button(tr("CONQUEST_BTN") % [UiKit.city_name(other), Diplomacy.nation_name(GameState.city_owner(other)), Actions.ap_cost("conquest", player)], _conquest.bind(other), 88))


func _conquest(target: String) -> void:
	var result: Dictionary = Actions.execute("conquest", GameState.player_id, {"target": target})
	if not result["ok"]:
		toast_requested.emit(result["reason"])
		return
	battle_requested.emit(result["quest"])


func _launch(target: String) -> void:
	var result: Dictionary = Actions.execute("launch_war", GameState.player_id, {"target": target})
	if not result["ok"]:
		toast_requested.emit(result["reason"])
		return
	battle_requested.emit(result["quest"])


func _tavern() -> void:
	var result: Dictionary = Actions.execute("tavern", GameState.player_id, {})
	if not result["ok"]:
		toast_requested.emit(result["reason"])
		return
	for line: String in result["lines"]:
		_log.push_front(line)
	_log.resize(mini(_log.size(), LOG_LINES))
	match result.get("event", ""):
		"discover":
			modal_requested.emit(TalkPopup.build(result["target"], result["speech"], result["lines"]))
		"brawl":
			duel_requested.emit(GameState.player_id, result["target"])
		_:
			toast_requested.emit("\n".join(result["lines"]))
	refresh()
	acted.emit()


func _serve() -> void:
	var result: Dictionary = Actions.execute("serve", GameState.player_id, {})
	if not result["ok"]:
		toast_requested.emit(result["reason"])
		return
	var speaker: String = result.get("speaker", "")
	if speaker != "":
		modal_requested.emit(TalkPopup.build(speaker, result["speech"], result["lines"]))
	else:
		toast_requested.emit("\n".join(result["lines"]))
	refresh()
	acted.emit()


func _hire_officer() -> void:
	var result: Dictionary = Actions.execute("hire_officer", GameState.player_id, {})
	if not result["ok"]:
		toast_requested.emit(result["reason"])
		return
	var box: VBoxContainer = UiKit.vbox(12)
	box.add_child(TalkPopup.build(result["target"], result["speech"], result["lines"]))
	box.add_child(OfficerCard.build(result["target"]))
	modal_requested.emit(box)
	refresh()
	acted.emit()


func _open_shop() -> void:
	var view: ShopView = ShopView.new()
	view.bought.connect(func(lines: Array) -> void:
		toast_requested.emit("\n".join(lines))
		acted.emit())
	modal_requested.emit(view)
