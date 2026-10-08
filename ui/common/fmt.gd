class_name Fmt
extends RefCounted
## 화면 표시용 숫자·글자 모양 맞추기


## 12345 → "12,345"
static func num(value: int) -> String:
	var digits: String = str(absi(value))
	var out: String = ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out
