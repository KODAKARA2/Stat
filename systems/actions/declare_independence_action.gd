class_name DeclareIndependenceAction
extends GameAction
## 독립 선언 (행동력 1): 성주 이상이 다스리는 도시에서 새 나라를 세운다. 원 소속국과 전쟁.
## params = {"name": 나라 이름, "color": "#rrggbb"}


func _init() -> void:
	id = "declare_independence"


func check(actor: String, _params: Dictionary) -> String:
	return Founding.independence_check(actor)


func run(actor: String, params: Dictionary) -> Dictionary:
	var s: Dictionary = Officers.get_state(actor)
	var city: String = s["city"]
	var former: String = s.get("nation", "")
	var name: String = String(params.get("name", "")).strip_edges()
	if name == "":
		name = msg("FOUND_DEFAULT_NAME", [Officers.display_name(actor)])
	var n: String = Founding.found_nation(actor, city, name, params.get("color", Founding.COLORS[0]), former)
	return {"nation": n, "lines": [msg("FOUND_INDEPENDENCE", [name, Diplomacy.nation_name(former)])]}
