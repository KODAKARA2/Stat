class_name FormCompanyAction
extends GameAction
## 용병단 결성 (행동력 0): 용병대장이 되면 이름을 걸고 용병단을 만든다. 전쟁 계약을 맺을 수 있다.


func _init() -> void:
	id = "form_company"


func check(actor: String, _params: Dictionary) -> String:
	if Career.has_company(actor):
		return "COMPANY_FAIL_ALREADY"
	if not Officers.rank_row(actor).get("can_form_company", false):
		return "COMPANY_FAIL_RANK"
	return ""


func run(actor: String, params: Dictionary) -> Dictionary:
	var name: String = params.get("name", "")
	if name == "":
		name = msg("COMPANY_DEFAULT_NAME", [Officers.display_name(actor)])
	Officers.get_state(actor)["company"] = {"name": name, "founded": TimeManager.month_index()}
	return {"lines": [msg("COMPANY_FORMED", [name])]}
