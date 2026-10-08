extends Node2D
## 메인 화면: 대륙 지도 + 아래 탭. 지도는 고정 배율로 주인공 주변만 보여 준다(끌기·확대 없음, 기획 2026-10-08). 탭 = 도시 정보.
## [도시]·[인물] 탭은 지도 위 가운데 영역에 패널로 뜬다.

const MAP_ZOOM: float = 1.4        # 고정 배율: 주인공 도시와 이웃 도시들이 보이는 정도
const TAP_MAX_MOVE: float = 14.0   # 이만큼 넘게 움직이면 탭으로 치지 않는다
const MAP_SIZE: Vector2 = Vector2(720, 1150)

## 도시 정보창은 두 장: 첫 장은 핵심 + 전쟁 상황, [자세히]를 누르면 둘째 장(나머지 수치 + 소개 글). 글씨를 크게 두기 위해.
const STAT_PAGES: Array = [
	[["STAT_POPULATION", "population"], ["STAT_TROOPS", "troops"], ["STAT_INCOME", "income"], ["STAT_HARVEST", "harvest"]],
	[["STAT_COMMERCE", "commerce"], ["STAT_AGRICULTURE", "agriculture"], ["STAT_SECURITY", "security"], ["STAT_DEFENSE", "defense"]],
]
const TAB_KEYS: PackedStringArray = ["TAB_MAP", "TAB_CITY", "TAB_PEOPLE", "TAB_COMPANY", "TAB_MENU"]

## 시험 실행(이 장면을 바로 실행)할 때 쓰는 기본 주인공
const TEST_PLAYER: Dictionary = {
	"name": "테스트", "race": "human", "gender": "m", "origin": "leonhart", "background": "knight_bastard", "bonus": {},
}

@onready var _camera: Camera2D = $Camera
@onready var _map: Node2D = $MapView
@onready var _hud: Control = %HUD
@onready var _top_bar: Control = %TopBar
@onready var _middle: Control = %Middle
@onready var _bottom: Control = %Bottom
@onready var _date: Label = %Date
@onready var _status: Label = %Status
@onready var _info_panel: Control = %InfoPanel
@onready var _hint: Label = %Hint
@onready var _info: Control = %Info
@onready var _city_name: Label = %CityName
@onready var _city_sub: Label = %CitySub
@onready var _stats: GridContainer = %Stats
@onready var _desc: Label = %Desc
@onready var _city_action: Button = %CityAction
@onready var _next_month: Button = %NextMonth
@onready var _tabs: HBoxContainer = %Tabs
@onready var _toast: Label = %Toast

var _world: WorldMap
var _selected_city: String = ""
var _info_page: int = 0            # 도시 정보창 몇 번째 장 (0 = 요약, 1 = 자세히)
var _page_button: Button
var _overview: bool = false        # 대륙 전도 보기 중인가
var _overview_button: Button
var _tab: String = "TAB_MAP"
var _panel: Control                # 지금 떠 있는 탭 패널 (없으면 null)
var _press_pos: Vector2 = Vector2.ZERO
var _pressing: bool = false
var _dragged: bool = false
var _toast_tween: Tween


func _ready() -> void:
	if not SaveManager.game_in_progress:
		WorldSetup.new_game(TEST_PLAYER)
		SaveManager.game_in_progress = false   # 시험 실행은 사용자 자동 저장을 건드리지 않는다
	_world = WorldMap.shared()
	for problem: String in _world.validate():
		push_warning("지도 데이터: " + problem)
	_map.setup(_world)

	EventBus.month_started.connect(func(_y: int, _m: int) -> void:
		_refresh_all()
		_show_report())
	_next_month.text = tr("BOOT_NEXT_MONTH")
	for big: Control in [_date, _city_name, _next_month]:   # 장면 파일에 적힌 36 → 글씨 크기 설정 반영
		big.add_theme_font_size_override("font_size", Settings.fs(36))
	_next_month.pressed.connect(TimeManager.advance_month)
	_city_action.pressed.connect(_on_city_action)
	# [자세히 ▶] 버튼: 도시 이름 줄 오른쪽 끝
	var name_row: HBoxContainer = UiKit.hbox(8)
	_city_name.get_parent().add_child(name_row)
	_city_name.get_parent().move_child(name_row, _city_name.get_index())
	_city_name.reparent(name_row)
	_city_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_button = UiKit.button(tr("MAP_INFO_MORE"), _toggle_info_page, 56)
	_page_button.focus_mode = Control.FOCUS_NONE
	name_row.add_child(_page_button)
	# [대륙 전도] 버튼: 지도 영역 오른쪽 위
	_overview_button = UiKit.button(tr("MAP_OVERVIEW"), _toggle_overview, 64)
	_overview_button.focus_mode = Control.FOCUS_NONE
	_overview_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_overview_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_overview_button.position += Vector2(-12, 12)
	_middle.add_child(_overview_button)
	_hint.text = tr("MAP_TAP_HINT")
	_toast.add_theme_stylebox_override("normal", UiKit.flat_style(Color(0, 0, 0, 0.85), 8, 16))
	_build_tabs()
	_show_city(Officers.get_state(GameState.player_id).get("city", ""))
	_refresh_all()
	# 레이아웃이 잡힌 다음 프레임에 지도를 맞춘다
	for arg: String in OS.get_cmdline_user_args():   # 개발용: --city=도시id 로 주인공을 그 도시에 두고 보기
		if arg.begins_with("--city="):
			Officers.get_state(GameState.player_id)["city"] = arg.trim_prefix("--city=")
			_show_city(arg.trim_prefix("--city="))
	await get_tree().process_frame
	_focus_player()
	_middle.resized.connect(_focus_player)   # 아래 정보창 높이가 바뀌면 다시 맞춘다
	for arg: String in OS.get_cmdline_user_args():   # 개발용: --event=이벤트id 로 이벤트 바로 보기
		if arg.begins_with("--event="):
			var ev: Dictionary = EventRunner.find_event(arg.trim_prefix("--event="))
			GameState.flags["pending_event"] = {"id": ev.get("id", ""), "speakers": EventRunner._resolve_speakers(ev), "context": {}}
			_check_event()
	if "--duel" in OS.get_cmdline_user_args():   # 개발용: 결투 창 바로 보기
		_start_tavern_duel(GameState.player_id, "gabriel")
	if "--nego" in OS.get_cmdline_user_args():   # 개발용: 설전 창 바로 보기
		_start_negotiation(Negotiation.start("recruit", GameState.player_id, {"target": "gabriel"}))
	if "--found" in OS.get_cmdline_user_args():   # 개발용: 건국 창 바로 보기 (점령전에서 이긴 셈)
		var here: String = Officers.get_state(GameState.player_id)["city"]
		_ask_founding({"city": here, "former": GameState.city_owner(here)})
	if "--ending" in OS.get_cmdline_user_args():   # 개발용: 은퇴 엔딩 화면 바로 보기
		Ending.retire()
		_check_event()


# ── 입력 ─────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	# 지도는 움직이지 않는다: 끌기·휠·두 손가락 확대 없이 탭(누르고 그 자리에서 떼기)만 받는다.
	# 안드로이드는 터치를 마우스로도 보내 주므로 PC와 폰이 같은 코드로 돈다.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressing = true
			_dragged = false
			_press_pos = event.position
		else:
			if _pressing and not _dragged:
				_on_tap(event.position)
			_pressing = false
	elif event is InputEventMouseMotion and _pressing:
		if event.position.distance_to(_press_pos) > TAP_MAX_MOVE:
			_dragged = true


func _on_tap(screen_pos: Vector2) -> void:
	var world_pos: Vector2 = _map.get_canvas_transform().affine_inverse() * screen_pos
	var city_id: String = _map.city_at(world_pos, _camera.zoom.x)
	if _overview and city_id != "":
		_toggle_overview()   # 전도에서 도시를 누르면 내 주변 지도로 돌아가며 그 도시 정보를 띄운다
	_show_city(city_id)


# ── 카메라 ───────────────────────────────────────

## 고정 배율로 주인공이 있는 도시를 '보이는 지도 영역'(위 막대와 아래 정보창 사이) 가운데에 둔다.
## 지도 끝 근처에서는 바깥 빈 곳이 보이지 않게 멈춘다.
func _focus_player() -> void:
	if _overview:
		_fit_whole_map()
		return
	var z: float = MAP_ZOOM
	_camera.zoom = Vector2(z, z)
	_map.set_label_scale(z)
	var view: Vector2 = get_viewport_rect().size
	var top: float = _middle.global_position.y
	var h: float = maxf(_middle.size.y, 1.0)
	var focus: Vector2 = _world.position_of(Officers.get_state(GameState.player_id).get("city", ""))
	# 화면 y = view/2 + (월드 y - 카메라 y) × z  →  보이는 영역 가운데(top + h/2)에 focus가 오도록
	var offset_y: float = (top + h / 2.0 - view.y / 2.0) / z
	var cam: Vector2 = focus - Vector2(0, offset_y)
	var half_w: float = view.x / 2.0 / z
	var half_h: float = h / 2.0 / z
	cam.x = clampf(cam.x, half_w, maxf(half_w, MAP_SIZE.x - half_w)) if MAP_SIZE.x > half_w * 2.0 else MAP_SIZE.x / 2.0
	var center_y: float = clampf(focus.y, half_h, maxf(half_h, MAP_SIZE.y - half_h)) if MAP_SIZE.y > half_h * 2.0 else MAP_SIZE.y / 2.0
	cam.y = center_y - offset_y
	_camera.position = cam


## 대륙 전도: 보이는 지도 영역에 대륙 전체를 맞춘다 (끌기·확대는 여전히 없음)
func _fit_whole_map() -> void:
	var view: Vector2 = get_viewport_rect().size
	var top: float = _middle.global_position.y
	var h: float = maxf(_middle.size.y, 1.0)
	var z: float = minf(view.x / MAP_SIZE.x, h / MAP_SIZE.y) * 0.98
	_camera.zoom = Vector2(z, z)
	_map.set_label_scale(z)
	_camera.position = MAP_SIZE / 2.0 - Vector2(0, (top + h / 2.0 - view.y / 2.0) / z)


func _toggle_overview() -> void:
	_overview = not _overview
	_overview_button.text = tr("MAP_OVERVIEW_BACK") if _overview else tr("MAP_OVERVIEW")
	_info_panel.visible = _panel == null and not _overview   # 전도를 볼 땐 정보창을 접어 지도를 크게
	_focus_player.call_deferred()   # 정보창이 접히고 영역 크기가 바뀐 뒤에 맞춘다


# ── 화면 갱신 ────────────────────────────────────

func _refresh_all() -> void:
	_date.text = tr("BOOT_DATE") % [TimeManager.year, TimeManager.month, TimeManager.season_name()]
	var p: Dictionary = GameState.player()
	var max_ap: int = Officers.max_ap(GameState.player_id)
	var dots: String = "●".repeat(int(p["ap"])) + "○".repeat(maxi(0, max_ap - int(p["ap"])))
	_status.text = MercGrade.label(GameState.player_id) + "   " + tr("HUD_STATUS") % [dots, int(p["energy"]), Fmt.num(int(p["gold"]))]
	_map.queue_redraw()
	if _world != null:
		_focus_player()   # 다른 도시로 옮겼으면 지도도 따라간다
	_show_city(_selected_city)
	if _panel and _panel.has_method("refresh"):
		_panel.refresh()
	_check_event.call_deferred()


func _show_city(city_id: String) -> void:
	if city_id != _selected_city:
		_info_page = 0   # 다른 도시를 고르면 첫 장부터
	_selected_city = city_id
	_map.select(city_id)
	_info.visible = city_id != ""
	_hint.visible = city_id == ""
	if city_id == "":
		return
	var row: Dictionary = DataDB.get_row("cities", city_id)
	var state: Dictionary = GameState.cities[city_id]
	var nation: Dictionary = Nations.row(state["nation"])
	_city_name.text = tr(row["name_key"])
	_city_name.add_theme_color_override("font_color", Color.html(nation["color"]).lightened(0.25))
	var sub: PackedStringArray = [Nations.display_name(state["nation"]), tr("TERRAIN_" + String(row["terrain"]).to_upper())]
	if row.get("capital", false):
		sub.append(tr("CITY_CAPITAL"))
	_city_sub.text = " · ".join(sub)

	UiKit.clear(_stats)
	for pair: Array in STAT_PAGES[_info_page]:
		var name_label: Label = UiKit.label(tr(pair[0]), 24, UiKit.MUTED)
		var value_label: Label = UiKit.label(Fmt.num(_city_value(city_id, pair[1])), 24, Color.WHITE)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_stats.add_child(name_label)
		_stats.add_child(value_label)
	_desc.text = _war_line(state["nation"]) if _info_page == 0 else tr(row["desc_key"])
	_page_button.text = tr("MAP_INFO_MORE") if _info_page == 0 else tr("MAP_INFO_BACK")
	_update_city_action(city_id)


## 도시 정보창 장 넘기기
func _toggle_info_page() -> void:
	_info_page = 1 - _info_page
	_show_city(_selected_city)


## 도시 정보 아래 버튼: 내가 있는 도시면 [도시 행동], 이웃 도시면 [이동], 멀면 거리만 표시
func _update_city_action(city_id: String) -> void:
	var here: String = Officers.get_state(GameState.player_id).get("city", "")
	_city_action.disabled = false
	if city_id == here:
		_city_action.text = tr("MAP_OPEN_CITY")
	elif _world.is_adjacent(here, city_id):
		_city_action.text = tr("ACTION_MOVE") + " " + tr("UI_AP_COST") % Actions.ap_cost("move", GameState.player_id)
	else:
		_city_action.text = tr("MAP_FAR_AWAY") % (_world.path(here, city_id).size() - 1)
		_city_action.disabled = true


func _on_city_action() -> void:
	var here: String = Officers.get_state(GameState.player_id).get("city", "")
	if _selected_city == here:
		_open_tab("TAB_CITY")
		return
	var result: Dictionary = Actions.execute("move", GameState.player_id, {"to": _selected_city})
	_show_toast(result["reason"] if not result["ok"] else "\n".join(result["lines"]))
	_refresh_all()


# ── 탭 ──────────────────────────────────────────

func _build_tabs() -> void:
	for key: String in TAB_KEYS:
		var button: Button = UiKit.button(tr(key), _open_tab.bind(key), 84)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.name = key
		_tabs.add_child(button)
	_update_tab_buttons()


func _open_tab(key: String) -> void:
	if _panel:
		_panel.queue_free()
		_panel = null
	_tab = key
	match key:
		"TAB_CITY":
			var city_panel: CityPanel = CityPanel.new()
			city_panel.toast_requested.connect(_show_toast)
			city_panel.modal_requested.connect(_open_modal)
			city_panel.acted.connect(_refresh_all)
			city_panel.duel_requested.connect(_start_tavern_duel)
			city_panel.battle_requested.connect(func(quest: Dictionary) -> void: BattleSession.start(quest, get_tree()))
			city_panel.negotiation_requested.connect(_start_negotiation)
			_panel = city_panel
		"TAB_COMPANY":
			var company_panel: CompanyPanel = CompanyPanel.new()
			company_panel.toast_requested.connect(_show_toast)
			company_panel.modal_requested.connect(_open_modal)
			company_panel.acted.connect(_refresh_all)
			_panel = company_panel
		"TAB_MENU":
			var menu_panel: MenuPanel = MenuPanel.new()
			menu_panel.toast_requested.connect(_show_toast)
			_panel = menu_panel
		"TAB_PEOPLE":
			var people_panel: PeoplePanel = PeoplePanel.new()
			people_panel.modal_requested.connect(_open_modal)
			_panel = people_panel
	if _panel:
		_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		_middle.add_child(_panel)
	# 패널이 떠 있으면 지도용 도시 정보는 숨겨 공간을 넓힌다
	_info_panel.visible = _panel == null and not _overview
	_overview_button.visible = _panel == null
	_update_tab_buttons()


func _update_tab_buttons() -> void:
	for button: Node in _tabs.get_children():
		(button as Button).disabled = button.name == _tab


func _open_modal(content: Control) -> void:
	Modal.open(_hud, content).closed.connect(_check_event, CONNECT_DEFERRED)


func _show_toast(text: String) -> void:
	_toast.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.4)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)


func _city_value(city_id: String, key: String) -> int:
	match key:
		"income":
			return Economy.city_income(city_id)
		"harvest":
			return Economy.city_harvest(city_id)
	return int(GameState.cities[city_id].get(key, 0))


## 도시 정보 아래 한 줄: 그 나라의 전쟁 상대
func _war_line(nation_id: String) -> String:
	var wars: PackedStringArray = []
	for other: String in Diplomacy.alive_nations():
		if Diplomacy.at_war(nation_id, other):
			wars.append(Diplomacy.nation_name(other))
	return tr("MAP_AT_WAR") % ", ".join(wars) if not wars.is_empty() else tr("MAP_NO_WAR")


## 지난달 정세 보고 (WarSystem이 월말에 GameState.flags["report"]에 남긴 것) + 이번 달 출정 예정
func _show_report() -> void:
	var report: Dictionary = GameState.flags.get("report", {})
	if report.is_empty():
		return
	GameState.flags.erase("report")
	var box: VBoxContainer = UiKit.vbox(6)
	box.add_child(UiKit.label(tr("REPORT_TITLE") % [int(report["year"]), int(report["month"])], 36, UiKit.GOLD))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var line_count: int = 2
	for key: String in ["log", "battles", "deaths", "diplomacy", "people", "economy"]:
		line_count += report.get(key, []).size() * 2 + 1
	line_count += WarSystem.plans().size() + 1
	scroll.custom_minimum_size.y = mini(640, line_count * 30)
	box.add_child(scroll)
	var v: VBoxContainer = UiKit.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	if WarSystem.report_is_empty(report):
		v.add_child(UiKit.label(tr("REPORT_QUIET"), 24, UiKit.MUTED, true))
	for section: Array in [["log", "REPORT_LOG", UiKit.GOOD], ["battles", "REPORT_BATTLES", UiKit.TEXT], ["deaths", "REPORT_DEATHS", UiKit.MUTED],
			["diplomacy", "REPORT_DIPLOMACY", UiKit.TEXT], ["people", "REPORT_PEOPLE", UiKit.TEXT], ["economy", "REPORT_ECONOMY", UiKit.MUTED]]:
		var lines: Array = report.get(section[0], [])
		if lines.is_empty():
			continue
		v.add_child(UiKit.label("■ " + tr(section[1]), 24, UiKit.GOLD))
		for line: String in lines:
			v.add_child(UiKit.label(line, 24, section[2], true))
	var planned: Array = WarSystem.plans()
	if not planned.is_empty():
		v.add_child(UiKit.label("■ " + tr("REPORT_PLANNED"), 24, UiKit.GOLD))
		for p: Dictionary in planned:
			v.add_child(UiKit.label(tr("REPORT_PLAN_LINE") % [Diplomacy.nation_name(p["attacker"]), UiKit.city_name(p["to"]), Diplomacy.nation_name(p["defender"])], 24, UiKit.BAD, true))
	Modal.open(_hud, box).closed.connect(_check_event, CONNECT_DEFERRED)


## 술집 시비 → 결투 창. 끝나면 결과를 알린다.
func _start_tavern_duel(a_id: String, b_id: String) -> void:
	var panel: DuelPanel = DuelPanel.open(_hud, a_id, b_id)
	var result: Array = await panel.finished
	var lines: Array = Duel.apply_tavern(result[1])
	_show_toast("\n".join(lines))
	_refresh_all()


## 설전 창. 끝나면 결과를 알린다.
func _start_negotiation(nego: Dictionary) -> void:
	var panel: NegotiationPanel = NegotiationPanel.open(_hud, nego)
	var lines: Array = await panel.finished
	if not lines.is_empty():
		_show_toast("\n".join(lines))
	_refresh_all()
	_check_event.call_deferred()


## 기다리는 이벤트가 있으면 연다. 다른 창(보고서·대화·결투)이 떠 있으면 그게 닫힌 뒤에.
func _check_event() -> void:
	# 게임 오버·승계·아이 이름 짓기가 이벤트보다 먼저
	if GameState.flags.has("game_over"):
		get_tree().change_scene_to_file("res://ui/title/game_over_screen.tscn")
		return
	for child: Node in _hud.get_children():
		if (child is Modal or child is DuelPanel or child is EventPanel or child is NegotiationPanel) and not child.is_queued_for_deletion():
			return
	if GameState.flags.has("succession"):
		var info: Dictionary = GameState.flags["succession"]
		GameState.flags.erase("succession")
		var box: VBoxContainer = UiKit.vbox(12)
		box.add_child(UiKit.label(tr("SUCCESSION_TITLE"), 36, UiKit.GOLD))
		box.add_child(UiKit.label(tr("SUCCESSION_BODY") % [info["from"], info["to"]], 24, UiKit.TEXT, true))
		Modal.open(_hud, box).closed.connect(_check_event, CONNECT_DEFERRED)
		_refresh_all()
		return
	if GameState.flags.has("pending_founding"):
		_ask_founding(GameState.flags["pending_founding"])
		GameState.flags.erase("pending_founding")
		return
	if GameState.flags.has("ending"):
		get_tree().change_scene_to_file("res://ui/title/ending_screen.tscn")
		return
	if GameState.flags.has("pending_naming"):
		_ask_child_name(GameState.flags["pending_naming"])
		GameState.flags.erase("pending_naming")
		return
	if EventRunner.pending().is_empty():
		return
	for child: Node in _hud.get_children():
		if (child is Modal or child is DuelPanel or child is EventPanel or child is NegotiationPanel) and not child.is_queued_for_deletion():
			return
	var panel: EventPanel = EventPanel.open(_hud)
	panel.finished.connect(func() -> void:
		var duel_target: String = GameState.flags.get("pending_duel", "")
		GameState.flags.erase("pending_duel")
		if duel_target != "":
			_start_tavern_duel(GameState.player_id, duel_target)
		else:
			_refresh_all())


## 용병단 점령전에서 이겼다 → 나라 이름을 정하고 건국. 창을 그냥 닫아도 기본 이름으로 세운다.
func _ask_founding(info: Dictionary) -> void:
	var player: String = GameState.player_id
	var default_name: String = tr("FOUND_DEFAULT_NAME") % Officers.display_name(player)
	var done: Array = [false]
	var found: Callable = func(nation_name: String, color: String) -> void:
		if done[0]:
			return
		done[0] = true
		Founding.found_nation(player, info["city"], nation_name, color, info["former"])
	var body: String = tr("FOUND_CONQUEST_BODY") % [UiKit.city_name(info["city"]), Diplomacy.nation_name(info["former"])]
	var modal: Modal = Modal.open(_hud, FoundingDialog.build("FOUND_TITLE", body, default_name, found))
	modal.closed.connect(func() -> void:
		found.call(default_name, Founding.COLORS[0])
		_refresh_all()
		_check_event.call_deferred())


## 주인공의 아이가 태어나면 이름을 짓는다 (GDD §5.2)
func _ask_child_name(child_id: String) -> void:
	var box: VBoxContainer = UiKit.vbox(12)
	box.add_child(UiKit.label(tr("NAMING_TITLE"), 36, UiKit.GOLD))
	box.add_child(UiKit.label(tr("NAMING_BODY") % [Officers.race_label(child_id), tr("GENDER_" + String(Officers.get_state(child_id).get("gender", "m")).to_upper())], 24, UiKit.TEXT, true))
	var name_input: NameInput = NameInput.make(Officers.display_name(child_id), 8, 54)
	box.add_child(name_input)
	var modal: Modal = Modal.open(_hud, box, "NAMING_OK")
	modal.closed.connect(func() -> void:
		var n: String = name_input.get_text()
		if n != "":
			Officers.get_state(child_id)["name"] = n
		_check_event.call_deferred())
