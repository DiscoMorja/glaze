class_name ApPips
extends Control
## Action points as circles: filled green = available, orange = would be spent
## by the previewed action, hollow = spent this turn.

const RADIUS := 6.0
const SPACING := 16.0
const COLOR_AVAILABLE := Color(0.3, 0.95, 0.4)
const COLOR_PENDING := Color(1.0, 0.6, 0.15)
const COLOR_SPENT := Color(0.3, 0.95, 0.4, 0.55)

var available := 0
var total := 0
var pending := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_points(p_available: int, p_total: int, p_pending: int = 0) -> void:
	available = p_available
	total = maxi(p_total, p_available)
	pending = clampi(p_pending, 0, available)
	custom_minimum_size = Vector2(maxf(total * SPACING, SPACING), RADIUS * 2.0 + 4.0)
	queue_redraw()


func _draw() -> void:
	for i in total:
		var center := Vector2(RADIUS + 2.0 + i * SPACING, RADIUS + 2.0)
		if i < available - pending:
			draw_circle(center, RADIUS, COLOR_AVAILABLE)
		elif i < available:
			draw_circle(center, RADIUS, COLOR_PENDING)
		else:
			draw_arc(center, RADIUS - 1.0, 0.0, TAU, 20, COLOR_SPENT, 2.0, true)
