class_name Shop
extends RefCounted
## 상점 (GDD §3.3): 도시마다 파는 물건(나라·수도 제한), 값(하플링 할인), 장비 보너스는 Officers.stat에 반영된다.


static func cfg(key: String, default_value: Variant) -> Variant:
	return DataDB.balance("shop." + key, default_value)


## 이 도시 상점에 있는 물건
static func available(city_id: String) -> Array:
	var owner: String = GameState.city_owner(city_id)
	var capital: bool = DataDB.get_row("cities", city_id).get("capital", false)
	var list: Array = []
	for item: Dictionary in DataDB.get_rows("items"):
		var nations: Array = item.get("nations", [])
		if not nations.is_empty() and not nations.has(owner):
			continue
		if item.get("capital_only", false) and not capital:
			continue
		list.append(item)
	return list


static func price(buyer: String, item: Dictionary) -> int:
	var p: float = float(item.get("price", 0))
	if Officers.has_trait(buyer, "shop_discount"):
		p *= 1.0 - float(cfg("halfling_discount", 0.2))
	return int(round(p))


static func sell_value(item_id: String) -> int:
	return int(int(DataDB.get_row("items", item_id).get("price", 0)) * float(cfg("sell_ratio", 0.5)))


static func equipped(id: String, slot: String) -> String:
	return str(Officers.get_state(id).get("equipment", {}).get(slot, ""))


static func bonus_text(item: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key: String in item.get("bonus", {}):
		parts.append("%s %+d" % [Officers.stat_label(key), int(item["bonus"][key])])
	for key: String in item.get("use", {}):
		parts.append(GameAction.msg("ITEM_USE_" + key.to_upper(), [absi(int(item["use"][key]))]))
	return ", ".join(parts)
