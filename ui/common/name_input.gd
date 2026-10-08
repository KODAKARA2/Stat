class_name NameInput
extends VBoxContainer
## 이름 입력칸 + 게임 안 한글 자판(두벌식). 근성영애와 같은 방식.
## Windows에서 Godot의 한글 입력기가 조합 중인 앞 글자를 지우고(한 글자씩만 입력됨),
## 다른 버튼을 누르면 확정 안 된 글자가 사라지는 문제가 있어서:
##  ① 자판 버튼으로 자모를 넣으면 Hangul.compose로 직접 조합한다 (휴대폰에서도 똑같이 동작)
##  ② 입력칸에서 포커스가 빠질 때·값을 읽을 때 운영체제 입력기로 조합 중인 글자를 확정한다(apply_ime)
## 입력칸에 영문 입력·붙여넣기(Ctrl+V)도 여전히 된다.

signal changed(text: String)

const ROWS: Array = [
	["ㅂ", "ㅈ", "ㄷ", "ㄱ", "ㅅ", "ㅛ", "ㅕ", "ㅑ", "ㅐ", "ㅔ"],
	["ㅁ", "ㄴ", "ㅇ", "ㄹ", "ㅎ", "ㅗ", "ㅓ", "ㅏ", "ㅣ"],
	["⇧", "ㅋ", "ㅌ", "ㅊ", "ㅍ", "ㅠ", "ㅜ", "ㅡ", "←"],
]
const SHIFTED: Dictionary = {"ㅂ": "ㅃ", "ㅈ": "ㅉ", "ㄷ": "ㄸ", "ㄱ": "ㄲ", "ㅅ": "ㅆ", "ㅐ": "ㅒ", "ㅔ": "ㅖ"}

var edit: LineEdit
var max_len: int = 8
var _shift: bool = false
var _keys: Dictionary = {}       # 원래 자모 → 버튼
var _base: String = ""           # 자판으로 조합 중인 부분 앞의 확정된 글자
var _seq: Array = []             # 조합 중인 자모 목록
var _last_shown: String = ""     # 자판이 마지막으로 만든 입력칸 내용 (직접 고쳤는지 확인용)
var _msg: Label


static func make(initial: String = "", length: int = 8, key_width: int = 58) -> NameInput:
	var n: NameInput = NameInput.new()
	n.max_len = length
	n._build(initial, key_width)
	return n


func _build(initial: String, key_width: int) -> void:
	add_theme_constant_override("separation", 6)
	edit = LineEdit.new()
	edit.max_length = max_len
	edit.custom_minimum_size.y = 64
	edit.add_theme_font_size_override("font_size", Settings.fs(36))
	edit.text = initial
	edit.text_changed.connect(func(t: String) -> void: changed.emit(t))
	edit.focus_exited.connect(commit_ime)
	add_child(edit)
	for row: Array in ROWS:
		var hb: HBoxContainer = HBoxContainer.new()
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		hb.add_theme_constant_override("separation", 4)
		for k: String in row:
			var b: Button = Button.new()
			b.text = k
			b.focus_mode = Control.FOCUS_NONE   # 누를 때 입력칸 포커스를 뺏지 않는다
			b.custom_minimum_size = Vector2(key_width + (14 if k == "⇧" or k == "←" else 0), 64)
			b.add_theme_font_size_override("font_size", Settings.fs(34))   # 낱자 모양이 작아서 조금 크게
			for state: String in ["normal", "hover", "pressed", "disabled"]:   # 좌우 여백을 줄여 큰 글씨에서도 한 줄에 10칸
				var st: StyleBox = b.get_theme_stylebox(state).duplicate()
				st.content_margin_left = 2
				st.content_margin_right = 2
				b.add_theme_stylebox_override(state, st)
			b.pressed.connect(_key.bind(k))
			hb.add_child(b)
			_keys[k] = b
		add_child(hb)
	var bottom: HBoxContainer = HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	var clear: Button = UiKit.button(TranslationServer.translate("NAME_CLEAR"), func() -> void: set_text(""), 56)
	clear.focus_mode = Control.FOCUS_NONE
	bottom.add_child(clear)
	_msg = UiKit.label("", 24, UiKit.BAD)
	_msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom.add_child(_msg)
	add_child(bottom)


## 지금 이름 (운영체제 입력기로 조합 중인 글자도 확정해서)
func get_text() -> String:
	commit_ime()
	return edit.text.strip_edges()


func show_error(text: String) -> void:
	_msg.text = text


func set_text(t: String) -> void:
	_base = t
	_seq = []
	_show()


## 입력칸에서 운영체제 입력기로 조합 중인(아직 확정 안 된) 한글이 있으면 확정한다
func commit_ime() -> void:
	if edit.has_ime_text():
		edit.apply_ime()


func _key(k: String) -> void:
	_msg.text = ""
	commit_ime()
	# 입력칸을 직접 고쳤으면(영문 입력·붙여넣기) 그 내용을 확정된 글자로 삼고 새로 조합을 시작한다
	if edit.text != _last_shown:
		_base = edit.text
		_seq = []
	match k:
		"⇧":
			_shift = not _shift
			_refresh_shift()
			return
		"←":
			if not _seq.is_empty():
				_seq.pop_back()
			elif _base.length() > 0:
				_base = _base.left(_base.length() - 1)
		_:
			var j: String = SHIFTED.get(k, k) if _shift else k
			var trial: Array = _seq.duplicate()
			trial.append(j)
			if (_base + Hangul.compose(trial)).length() > max_len:
				_msg.text = TranslationServer.translate("NAME_TOO_LONG") % max_len
				return
			_seq = trial
			if _shift:
				_shift = false
				_refresh_shift()
	_show()


func _show() -> void:
	_last_shown = _base + Hangul.compose(_seq)
	edit.text = _last_shown
	edit.caret_column = edit.text.length()
	changed.emit(edit.text)


func _refresh_shift() -> void:
	for k: String in SHIFTED:
		(_keys[k] as Button).text = SHIFTED[k] if _shift else k
	(_keys["⇧"] as Button).modulate = UiKit.GOLD if _shift else Color.WHITE
