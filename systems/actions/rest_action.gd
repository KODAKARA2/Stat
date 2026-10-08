class_name RestAction
extends GameAction
## 휴식: 기력을 크게 회복하고 부상을 1개월 줄인다.


func _init() -> void:
	id = "rest"


func run(actor: String, _params: Dictionary) -> Dictionary:
	var s: Dictionary = Officers.get_state(actor)
	var before: int = int(s["energy"])
	s["energy"] = mini(before + int(cfg("energy", 40)), int(DataDB.balance("energy.max", 100)))
	s["injury"] = maxi(0, int(s["injury"]) - int(cfg("injury_heal", 1)))
	return {"lines": [msg("ACT_REST_DONE", [before, s["energy"]])]}
