extends Node3D
## A torch or campfire flame: the light's energy and the flame's size waver a
## little, each prop out of step with the others. Presentation only.

@export var light: OmniLight3D
@export var flame: Node3D
@export var strength := 0.25

var _energy := 1.0
var _t := 0.0


func _ready() -> void:
	_t = fposmod(global_position.x * 1.7 + global_position.z * 2.3, 100.0)
	if light != null:
		_energy = light.light_energy


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	var wave := sin(_t * 9.0) * 0.5 + sin(_t * 23.0 + 1.3) * 0.3 + sin(_t * 4.1 + 0.7) * 0.2
	if light != null:
		light.light_energy = _energy * (1.0 + wave * strength)
	if flame != null:
		flame.scale = Vector3.ONE * (1.0 + wave * strength * 0.6)
