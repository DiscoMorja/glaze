class_name EndTurnButton
extends Button
## End turn, bottom right. Lights up and pulses when nobody this player
## controls has anything left to do; says so while waiting for the partner.

## How it looks: normal, lit up (nothing left to do), or waiting for the
## partner after pressing it.
enum Look { NORMAL, SUGGESTED, WAITING }

var _lit: StyleBoxFlat
var _pulse: Tween


func _ready() -> void:
	text = "End turn"
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(150, 58)
	add_theme_font_size_override("font_size", 17)
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -174
	offset_right = -24
	offset_top = -82
	offset_bottom = -24
	_lit = StyleBoxFlat.new()
	_lit.bg_color = Color(0.16, 0.45, 0.2)
	_lit.border_color = Color(0.4, 1.0, 0.5)
	_lit.set_border_width_all(2)
	_lit.set_corner_radius_all(4)


func show_state(enabled: bool, look: Look) -> void:
	disabled = not enabled
	text = "Waiting for\npartner..." if look == Look.WAITING else "End turn"
	var lit := look == Look.SUGGESTED and enabled
	for state_name in ["normal", "hover", "pressed"]:
		if lit:
			add_theme_stylebox_override(state_name, _lit)
		else:
			remove_theme_stylebox_override(state_name)
	if lit and _pulse == null:
		_pulse = create_tween().set_loops()
		_pulse.tween_property(self, "modulate", Color(1.25, 1.25, 1.25), 0.6)
		_pulse.tween_property(self, "modulate", Color.WHITE, 0.6)
	elif not lit and _pulse != null:
		_pulse.kill()
		_pulse = null
		modulate = Color.WHITE
