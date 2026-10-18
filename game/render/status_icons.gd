class_name StatusIcons
extends Control
## A row of small status icons over a character (burning, frozen, slowed...),
## each with the turns left in its corner. Drawn with simple vector glyphs, so
## no icon art is needed. Placed by ScreenLabels like the world text.

const SIZE := 18.0
const GAP := 3.0

## Icons to draw: [{"id": status, "color": Color, "count": int (0 = none)}].
var icons: Array[Dictionary] = []:
	set(value):
		icons = value
		custom_minimum_size = Vector2(maxf(icons.size() * (SIZE + GAP) - GAP, 0.0), SIZE)
		size = custom_minimum_size
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Nothing to show (ScreenLabels hides it).
func is_empty() -> bool:
	return icons.is_empty()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for i in icons.size():
		var icon: Dictionary = icons[i]
		var rect := Rect2(i * (SIZE + GAP), 0.0, SIZE, SIZE)
		var color: Color = icon.color
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.06, 0.06, 0.08, 0.85)
		box.border_color = color
		box.set_border_width_all(1)
		box.set_corner_radius_all(3)
		draw_style_box(box, rect)
		_glyph(icon.id, rect.grow(-3.5), color)
		var count: int = icon.get("count", 0)
		if count > 0:
			var text := str(count)
			var at := rect.position + Vector2(SIZE - 5.0, SIZE + 3.0)
			draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color.BLACK)
			draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)


## The symbol for a status, inside r.
func _glyph(id: String, r: Rect2, c: Color) -> void:
	var p := r.position
	var w := r.size.x
	var h := r.size.y
	var mid := r.get_center()
	match id:
		"burning":  # a flame
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(w * 0.5, 0), p + Vector2(w * 0.85, h * 0.55), p + Vector2(w * 0.75, h * 0.9),
				p + Vector2(w * 0.5, h), p + Vector2(w * 0.25, h * 0.9), p + Vector2(w * 0.15, h * 0.55),
				p + Vector2(w * 0.35, h * 0.35)]), c)
			draw_circle(p + Vector2(w * 0.5, h * 0.72), w * 0.17, Color(1, 0.95, 0.6))
		"hot":  # a sun
			draw_circle(mid, w * 0.24, c)
			for k in 8:
				var d := Vector2.from_angle(k * TAU / 8.0)
				draw_line(mid + d * w * 0.33, mid + d * w * 0.5, c, 1.5)
		"cold", "frozen":  # a snowflake; frozen sits on an ice block
			if id == "frozen":
				draw_rect(r, Color(c, 0.35))
			for k in 3:
				var d := Vector2.from_angle(k * TAU / 6.0 + PI / 2.0) * w * 0.5
				draw_line(mid - d, mid + d, c if id == "cold" else Color.WHITE, 1.6)
		"slowed":  # an oil drop
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(w * 0.5, 0), p + Vector2(w * 0.8, h * 0.6), p + Vector2(w * 0.2, h * 0.6)]), c)
			draw_circle(p + Vector2(w * 0.5, h * 0.66), w * 0.31, c)
		"knocked":  # stars over a lying body
			draw_line(p + Vector2(0, h * 0.85), p + Vector2(w, h * 0.85), c, 2.5)
			draw_circle(p + Vector2(w * 0.12, h * 0.7), w * 0.13, c)
			for x: float in [0.3, 0.65]:
				draw_circle(p + Vector2(w * x, h * 0.25), w * 0.1, Color(1, 0.95, 0.6))
		"stagger":  # a zigzag jolt
			draw_polyline(PackedVector2Array([
				p + Vector2(w * 0.6, 0), p + Vector2(w * 0.25, h * 0.5), p + Vector2(w * 0.7, h * 0.5),
				p + Vector2(w * 0.35, h)]), c, 2.0)
		"pinned":  # an arrow stuck in the ground
			draw_line(p + Vector2(w * 0.15, 0), p + Vector2(w * 0.6, h * 0.75), c, 2.0)
			draw_line(p + Vector2(0, h * 0.85), p + Vector2(w, h * 0.85), c, 2.0)
		"distracted":  # a question mark
			draw_arc(p + Vector2(w * 0.5, h * 0.3), w * 0.25, PI, 2.4 * PI, 10, c, 2.0)
			draw_line(p + Vector2(w * 0.5, h * 0.55), p + Vector2(w * 0.5, h * 0.7), c, 2.0)
			draw_circle(p + Vector2(w * 0.5, h * 0.9), w * 0.1, c)
		"suspicious":  # an exclamation mark
			draw_rect(Rect2(p + Vector2(w * 0.38, 0), Vector2(w * 0.24, h * 0.62)), c)
			draw_circle(p + Vector2(w * 0.5, h * 0.88), w * 0.13, c)
		"sneaking":  # a half-closed eye
			draw_arc(mid + Vector2(0, -h * 0.15), w * 0.5, 0.2 * PI, 0.8 * PI, 10, c, 1.8)
			draw_circle(mid + Vector2(0, h * 0.2), w * 0.14, c)
		_:
			draw_circle(mid, w * 0.3, c)
