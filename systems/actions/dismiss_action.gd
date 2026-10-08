class_name DismissAction
extends GameAction
## 동료 해고 (행동력 0): 그 자리에서 재야로 돌아간다. 친밀도가 크게 떨어진다. params = {"target": id}


func _init() -> void:
	id = "dismiss"


func check(actor: String, params: Dictionary) -> String:
	return "" if Career.companions(actor).has(params.get("target", "")) else "ACT_FAIL_NO_TARGET"


func run(actor: String, params: Dictionary) -> Dictionary:
	var target: String = params["target"]
	Career.remove_companion(actor, target)
	Relationship.add(actor, target, -20)
	return {"lines": [msg("DISMISS_DONE", [Officers.display_name(target)])]}
