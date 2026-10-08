class_name TalkPopup
extends RefCounted
## 대화 창 내용물: [얼굴] 이름 / "대사" / 결과 줄들. 방문·교류 결과에 쓰고, M6 이벤트 대화창의 바탕이 된다.


static func build(speaker_id: String, speech: String, lines: Array) -> Control:
	var root: VBoxContainer = UiKit.vbox(12)
	var head: HBoxContainer = UiKit.hbox(16)
	root.add_child(head)
	head.add_child(UiKit.portrait(Officers.get_state(speaker_id).get("sprite_id", ""), 96))
	var info: VBoxContainer = UiKit.vbox(4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(info)
	info.add_child(UiKit.label(Officers.display_name(speaker_id), 36, UiKit.GOLD))
	info.add_child(UiKit.label("%s · %s" % [Officers.nation_label(speaker_id), Officers.rank_label(speaker_id)], 24, UiKit.MUTED))
	var bubble: PanelContainer = UiKit.panel(UiKit.ROW_BG, 16)
	bubble.add_child(UiKit.label("“%s”" % speech, 24, UiKit.TEXT, true))
	root.add_child(bubble)
	for line: String in lines:
		root.add_child(UiKit.label(line, 24, UiKit.GOOD, true))
	return root
