class_name GameAction
extends RefCounted
## 모든 행동의 바탕 (GDD §12.3-4). 플레이어와 NPC가 같은 행동을 같은 규칙으로 쓴다.
## 하위 클래스는 check()와 run()만 채우면 된다. 비용(행동력 등)은 balance.json의 actions.<id>에서 읽는다.
##
## 결과 Dictionary: {"ok": bool, "action": id, "reason": 실패 사유 문장, "lines": [결과 문장...], 그 밖에 행동별 값}

var id: String = ""


func cfg(key: String, default_value: Variant = 0) -> Variant:
	return DataDB.balance("actions.%s.%s" % [id, key], default_value)


func ap_cost(_actor: String, _params: Dictionary) -> int:
	return int(cfg("ap", 1))


## 할 수 있으면 "", 못 하면 사유 번역 키
func check(_actor: String, _params: Dictionary) -> String:
	return ""


func run(_actor: String, _params: Dictionary) -> Dictionary:
	return {}


## 행동력·조건을 모두 확인한 뒤 실행 가능하면 ""(UI에서 버튼을 끄는 데 쓴다)
func can_execute(actor: String, params: Dictionary = {}) -> String:
	var s: Dictionary = Officers.get_state(actor)
	if s.is_empty() or not Officers.is_active(actor):
		return "ACT_FAIL_NO_ACTOR"
	if int(s["ap"]) < ap_cost(actor, params):
		return "ACT_FAIL_NO_AP"
	return check(actor, params)


func execute(actor: String, params: Dictionary = {}) -> Dictionary:
	var reason: String = can_execute(actor, params)
	if reason != "":
		return {"ok": false, "action": id, "reason": TranslationServer.translate(reason), "lines": []}
	Officers.get_state(actor)["ap"] = int(Officers.get_state(actor)["ap"]) - ap_cost(actor, params)
	var result: Dictionary = run(actor, params)
	result["ok"] = true
	result["action"] = id
	if not result.has("lines"):
		result["lines"] = []
	EventBus.action_executed.emit(actor, id, result)
	return result


## 번역 키 + 끼워 넣을 값 → 문장
static func msg(key: String, args: Array = []) -> String:
	var text: String = TranslationServer.translate(key)
	return text % args if not args.is_empty() else text
