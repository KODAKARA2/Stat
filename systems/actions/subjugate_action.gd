class_name SubjugateAction
extends GameAction
## 의뢰 수행(토벌 출발): 받은 의뢰의 도시에서 전투를 시작한다. params = {"quest": quest_id}
## 실제 전투는 화면(ui/battle)이 돌리고, 끝나면 BattleOutcome이 정산한다.


func _init() -> void:
	id = "subjugate"


func check(actor: String, params: Dictionary) -> String:
	var s: Dictionary = Officers.get_state(actor)
	var quest: Dictionary = Guild.find(Guild.active_quests(actor), params.get("quest", ""))
	if quest.is_empty():
		return "ACT_FAIL_NO_QUEST"
	if quest.get("type", "") == "war" and WarSystem.find_plan(quest.get("plan", "")).is_empty():
		return "ACT_FAIL_PLAN_GONE"
	if quest["city"] != s.get("city", ""):
		return "ACT_FAIL_QUEST_ELSEWHERE"
	if int(s.get("injury", 0)) > 0:
		return "ACT_FAIL_INJURED"
	if int(s.get("troops", 0)) <= 0:
		return "ACT_FAIL_NO_TROOPS"
	return ""


func run(actor: String, params: Dictionary) -> Dictionary:
	var quest: Dictionary = Guild.find(Guild.active_quests(actor), params["quest"])
	return {"quest": quest, "battle": true, "lines": [msg("ACT_SUBJUGATE_START", [Guild.quest_title(quest)])]}
