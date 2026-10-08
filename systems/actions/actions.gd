class_name Actions
extends RefCounted
## 행동 목록. 플레이어 UI와 NPC AI 모두 Actions.execute("visit", 무장id, {...})로 행동한다.

static var _registry: Dictionary = {}


static func get_action(action_id: String) -> GameAction:
	if _registry.is_empty():
		for action: GameAction in [MoveAction.new(), VisitAction.new(), InteractAction.new(), TrainAction.new(), RestAction.new(),
				AcceptQuestAction.new(), SubjugateAction.new(), HireAction.new(), RecruitAction.new(), HireOfficerAction.new(),
				DismissAction.new(), FormCompanyAction.new(), ServeAction.new(), TavernAction.new(), GovernAction.new(), LaunchWarAction.new(),
				BuyAction.new(), ConfessAction.new(), ProposeAction.new(), SwearAction.new(),
				DeclareIndependenceAction.new(), ConquestAction.new(), NegotiateAction.new()]:
			_registry[action.id] = action
	return _registry.get(action_id)


static func can_execute(action_id: String, actor: String, params: Dictionary = {}) -> String:
	var action: GameAction = get_action(action_id)
	return action.can_execute(actor, params) if action else "ACT_FAIL_UNKNOWN"


static func execute(action_id: String, actor: String, params: Dictionary = {}) -> Dictionary:
	var action: GameAction = get_action(action_id)
	if action == null:
		return {"ok": false, "action": action_id, "reason": TranslationServer.translate("ACT_FAIL_UNKNOWN"), "lines": []}
	return action.execute(actor, params)


static func ap_cost(action_id: String, actor: String, params: Dictionary = {}) -> int:
	var action: GameAction = get_action(action_id)
	return action.ap_cost(actor, params) if action else 0
