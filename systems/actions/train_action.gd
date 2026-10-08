class_name TrainAction
extends GameAction
## 수행: 능력 1개를 골라 경험치를 얻는다. 기력을 쓴다. params = {"stat": "str" 등}


func _init() -> void:
	id = "train"


func check(actor: String, params: Dictionary) -> String:
	var key: String = params.get("stat", "")
	if not Officers.stat_keys().has(key):
		return "ACT_FAIL_NO_STAT"
	if int(Officers.get_state(actor)["energy"]) < int(cfg("energy", 15)):
		return "ACT_FAIL_TIRED"
	if Progression.is_capped(actor, key):
		return "ACT_FAIL_CAPPED"
	return ""


func run(actor: String, params: Dictionary) -> Dictionary:
	var s: Dictionary = Officers.get_state(actor)
	var key: String = params["stat"]
	s["energy"] = int(s["energy"]) - int(cfg("energy", 15))
	var r: Dictionary = Progression.add_exp(actor, key, RNG.randi_range(int(cfg("exp_min", 20)), int(cfg("exp_max", 32))))
	var label: String = Officers.stat_label(key)
	var lines: Array = [msg("ACT_TRAIN_EXP", [label, r["exp"], r["progress"], r["need"]])]
	if r["gained"] > 0:
		lines.append(msg("ACT_TRAIN_UP", [label, r["before"], r["after"]]))
	if r["capped"]:
		lines.append(msg("ACT_TRAIN_CAPPED", [label]))
	r["stat"] = key
	r["lines"] = lines
	return r
