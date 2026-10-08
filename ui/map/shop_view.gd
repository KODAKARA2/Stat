class_name ShopView
extends VBoxContainer
## 상점 목록 (Modal 안에 넣어 쓴다): 이름·효과·값, [사기]. 산 뒤 목록을 다시 그린다.

signal bought(lines: Array)

const SLOT_ORDER: Array = ["weapon", "armor", "accessory", "consumable"]


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	refresh()


func refresh() -> void:
	UiKit.clear(self)
	var me: String = GameState.player_id
	var city: String = Officers.get_state(me).get("city", "")
	add_child(UiKit.label(tr("SHOP_TITLE") % UiKit.city_name(city), 36, UiKit.GOLD))
	add_child(UiKit.label(tr("SHOP_GOLD") % Fmt.num(int(GameState.player()["gold"])), 24, UiKit.TEXT))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 620
	add_child(scroll)
	var list: VBoxContainer = UiKit.vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var items: Array = Shop.available(city)
	for slot: String in SLOT_ORDER:
		list.add_child(UiKit.label("■ " + tr("SLOT_" + slot.to_upper()), 24, UiKit.GOLD))
		for item: Dictionary in items:
			if item["slot"] != slot:
				continue
			var row: PanelContainer = UiKit.panel(UiKit.ROW_BG, 10)
			var h: HBoxContainer = UiKit.hbox(10)
			row.add_child(h)
			var info: VBoxContainer = UiKit.vbox(2)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(info)
			info.add_child(UiKit.label(tr(item["name_key"]), 24, UiKit.TEXT))
			info.add_child(UiKit.label(Shop.bonus_text(item), 24, UiKit.MUTED, true))
			var owned: bool = slot != "consumable" and Shop.equipped(me, slot) == item["id"]
			var b: Button = UiKit.button(tr("SHOP_OWNED") if owned else tr("SHOP_BUY") % Shop.price(me, item), _buy.bind(item["id"]), 72)
			b.custom_minimum_size.x = 150
			b.disabled = owned or Actions.can_execute("buy", me, {"item": item["id"]}) != ""
			h.add_child(b)
			list.add_child(row)


func _buy(item_id: String) -> void:
	var r: Dictionary = Actions.execute("buy", GameState.player_id, {"item": item_id})
	bought.emit(r["lines"] if r["ok"] else [r["reason"]])
	refresh()
