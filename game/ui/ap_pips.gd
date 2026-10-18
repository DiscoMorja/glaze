class_name ApPips
extends Control
## Action points as circles: filled green = available, orange = would be spent
## by the previewed action, hollow = spent or room to bank more (see
## CombatRules.AP_CAP). Size is set per use (party frames, the action bar).

var radius := 6.0
var spacing := 16.0
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
	custom_minimum_size = Vector2(maxf(total * spacing, spacing), radius * 2.0 + 4.0)
	queue_redraw()


func _draw() -> void:
	for i in total:
		var center := Vector2(radius + 2.0 + i * spacing, radius + 2.0)
		if i < available - pending:
			draw_circle(center, radius, COLOR_AVAILABLE)
			draw_arc(center, radius, 0.0, TAU, 24, Color(0, 0, 0, 0.6), 1.0, true)
		elif i < available:
			draw_circle(center, radius, COLOR_PENDING)
			draw_arc(center, radius, 0.0, TAU, 24, Color(0, 0, 0, 0.6), 1.0, true)
		else:
			draw_circle(center, radius - 1.0, Color(0, 0, 0, 0.35))
			draw_arc(center, radius - 1.0, 0.0, TAU, 24, COLOR_SPENT, 2.0, true)
