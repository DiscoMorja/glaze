extends Node3D
## Dev tool: every character look in a row, holding a weapon each, playing
## idle. Left/Right cycles the state (idle, combat idle, run, attack, cast,
## hit, drink, death); Up/Down steps the camera close to one look (Home:
## all of them). Run game/debug/look_viewer.tscn.

const STATES := ["idle", "combat_idle", "run", "attack", "cast", "hit", "drink", "death"]
const WEAPONS := ["Greatsword", "Fine sword", "Daggers", "Staff", "Knife", "Club", "Greataxe", "Totem", "Spear"]

var _models: Array[CharacterModel] = []
var _state := 0
var _label: Label
var _camera: Camera3D
var _focus := -1


func _ready() -> void:
	UiStyle.apply(get_tree())
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.22, 0.25)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var looks := CharacterLooks.LOOKS.keys()
	var columns := 6
	for i in looks.size():
		var model := CharacterModel.create(looks[i])
		if model == null:
			continue
		add_child(model)
		model.position = Vector3((i % columns) * 1.6 - columns * 0.8, 0, -(i / columns) * 2.2)
		var weapon: String = WEAPONS[i % WEAPONS.size()]
		model.hold(weapon, "Wooden shield" if weapon == "Fine sword" else "")
		var tag := Label3D.new()
		tag.text = "%s\n%s" % [looks[i], weapon]
		tag.position = Vector3(0, 2.1, 0)
		tag.pixel_size = 0.004
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		model.add_child(tag)
		_models.append(model)
	_camera = Camera3D.new()
	add_child(_camera)
	_place_camera()
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_label = Label.new()
	_label.position = Vector2(16, 12)
	canvas.add_child(_label)
	_show()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_RIGHT:
			_state = (_state + 1) % STATES.size()
			_show()
		elif event.keycode == KEY_LEFT:
			_state = posmod(_state - 1, STATES.size())
			_show()
		elif event.keycode in [KEY_UP, KEY_DOWN]:
			_focus = posmod(_focus + (1 if event.keycode == KEY_DOWN else -1), _models.size())
			_place_camera()
		elif event.keycode == KEY_X:
			var axes := [Vector3.ZERO, Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]
			CharacterModel.weapon_axis_override = axes[(axes.find(CharacterModel.weapon_axis_override) + 1) % axes.size()]
			for model in _models:
				model.rehold()
			_show()
		elif event.keycode == KEY_Z:
			var axes := [Vector3.ZERO, Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]
			CharacterModel.shield_axis_override = axes[(axes.find(CharacterModel.shield_axis_override) + 1) % axes.size()]
			for model in _models:
				model.rehold()
			_show()
		elif event.keycode in [KEY_R, KEY_T]:
			var step := 15.0 if not event.shift_pressed else -15.0
			if event.keycode == KEY_R:
				CharacterModel.weapon_roll_tune += step
			else:
				CharacterModel.weapon_tilt_tune += step
			for model in _models:
				model.rehold()
			_show()
		elif event.keycode == KEY_HOME:
			_focus = -1
			_place_camera()


func _place_camera() -> void:
	if _focus < 0:
		_camera.position = Vector3(0, 2.6, 5.5)
		_camera.rotation_degrees = Vector3(-18, 0, 0)
		for model in _models:
			model.visible = true
	else:
		var at := _models[_focus].position
		_camera.position = at + Vector3(0.9, 1.5, 1.7)
		_camera.look_at(at + Vector3(0, 1.1, 0))
		for i in _models.size():
			_models[i].visible = i == _focus


func _show() -> void:
	var state: String = STATES[_state]
	_label.text = "%s   (Left/Right)   %d looks   weapon axis %s (X, zero = each rig's own)   shield %s (Z)   roll %+d (R)  tilt %+d (T, shift: back)" % [state, _models.size(), CharacterModel.weapon_axis_override, CharacterModel.shield_axis_override, CharacterModel.weapon_roll_tune, CharacterModel.weapon_tilt_tune]
	for model in _models:
		model.revive()
		if state in ["idle", "combat_idle", "run"]:
			model.set_looping(state)
		elif state == "death":
			model.die()
		else:
			model.set_looping("combat_idle")
			model.play_once(state)
