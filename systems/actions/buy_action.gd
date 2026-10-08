class_name BuyAction
extends GameAction
## 사기 (행동력 0): 장비는 바로 착용하고 원래 것은 되판다. 소모품은 바로 쓴다. params = {"item": id}


func _init() -> void:
	id = "buy"


func check(actor: String, params: Dictionary) -> String:
	var item: Dictionary = DataDB.get_row("items", params.get("item", ""))
	if item.is_empty() or not Shop.available(Officers.get_state(actor).get("city", "")).has(item):
		return "SHOP_FAIL_NOT_SOLD"
	if item["slot"] != "consumable" and Shop.equipped(actor, item["slot"]) == item["id"]:
		return "SHOP_FAIL_OWNED"
	var refund: int = Shop.sell_value(Shop.equipped(actor, item["slot"])) if item["slot"] != "consumable" else 0
	if int(Officers.get_state(actor).get("gold", 0)) + refund < Shop.price(actor, item):
		return "ACT_FAIL_NO_GOLD"
	return ""


func run(actor: String, params: Dictionary) -> Dictionary:
	var s: Dictionary = Officers.get_state(actor)
	var item: Dictionary = DataDB.get_row("items", params["item"])
	var cost: int = Shop.price(actor, item)
	var lines: Array = []
	s["gold"] = int(s["gold"]) - cost
	if item["slot"] == "consumable":
		var use: Dictionary = item.get("use", {})
		if use.has("injury"):
			s["injury"] = maxi(0, int(s.get("injury", 0)) + int(use["injury"]))
		if use.has("energy"):
			s["energy"] = mini(int(s["energy"]) + int(use["energy"]), int(DataDB.balance("energy.max", 100)))
		if use.has("troops"):
			s["troops"] = mini(int(s.get("troops", 0)) + int(use["troops"]), Officers.max_troops(actor))
		lines.append(msg("SHOP_USED", [TranslationServer.translate(item["name_key"]), cost]))
	else:
		var old: String = Shop.equipped(actor, item["slot"])
		if old != "":
			var refund: int = Shop.sell_value(old)
			s["gold"] = int(s["gold"]) + refund
			lines.append(msg("SHOP_SOLD", [TranslationServer.translate(DataDB.get_row("items", old).get("name_key", "")), refund]))
		s.get_or_add("equipment", {})[item["slot"]] = item["id"]
		lines.append(msg("SHOP_EQUIPPED", [TranslationServer.translate(item["name_key"]), cost]))
	return {"item": item["id"], "lines": lines}
