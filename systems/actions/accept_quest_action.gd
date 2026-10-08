class_name AcceptQuestAction
extends GameAction
## 의뢰 수주 (행동력 0): 지금 도시 길드 게시판에서 의뢰를 받는다. params = {"quest": quest_id}
## 토벌 / 참전 의뢰는 받은 의뢰 목록에, 용병단 전쟁 계약은 계약으로 들어간다.
## 계약 중인 고용국의 적 편 의뢰를 받으면 배신(위약금·평판·명성).


func _init() -> void:
	id = "accept_quest"


func check(actor: String, params: Dictionary) -> String:
	var city: String = Officers.get_state(actor).get("city", "")
	var board_quest: Dictionary = Guild.find(Guild.city_quests(city), params.get("quest", ""))
	if board_quest.is_empty():
		return "ACT_FAIL_NO_QUEST"
	var kind: String = board_quest.get("type", "monster")
	var nation: String = Officers.get_state(actor).get("nation", "")
	if kind == "contract":
		if not Career.has_company(actor):
			return "CONTRACT_FAIL_NO_COMPANY"
		if Career.is_vassal(actor):
			return "CONTRACT_FAIL_VASSAL"
		if not Career.contract(actor).is_empty() and Career.contract(actor)["employer"] == board_quest["employer"]:
			return "CONTRACT_FAIL_SAME"
		return ""
	if kind == "war":
		if Career.is_vassal(actor) and board_quest["enemy"] == nation:
			return "ACT_FAIL_OWN_NATION"   # 봉신은 자기 나라를 칠 수 없다
		for q: Dictionary in Guild.active_quests(actor):
			if q.get("plan", "") == board_quest["plan"]:
				return "ACT_FAIL_BOTH_SIDES"
	var counted: int = 0
	for q: Dictionary in Guild.active_quests(actor):
		if not q.get("order", false):
			counted += 1
	if counted >= int(Guild.cfg("max_active", 2)):
		return "ACT_FAIL_QUEST_FULL"
	return ""


func run(actor: String, params: Dictionary) -> Dictionary:
	var s: Dictionary = Officers.get_state(actor)
	var board: Array = Guild.city_quests(s["city"])
	var quest: Dictionary = Guild.find(board, params["quest"])
	board.erase(quest)
	var lines: Array = []
	var kind: String = quest.get("type", "monster")
	if kind == "contract":
		var betrayal: String = Career.betray_if_needed(actor, quest["employer"])
		if betrayal != "":
			lines.append(betrayal)
		Career.accept_contract(actor, quest)
		lines.append(msg("CONTRACT_SIGNED", [Diplomacy.nation_name(quest["employer"]), int(quest["months"]), Fmt.num(int(quest["pay"]))]))
		return {"quest": quest, "lines": lines}
	if kind == "war":
		var betrayal: String = Career.betray_if_needed(actor, quest["side"])
		if betrayal != "":
			lines.append(betrayal)
	if not s.has("quests"):
		s["quests"] = []
	s["quests"].append(quest)
	lines.append(msg("ACT_QUEST_ACCEPTED", [Guild.quest_title(quest)]))
	return {"quest": quest, "lines": lines}
