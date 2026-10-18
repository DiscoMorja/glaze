class_name ScreenLabels
extends CanvasLayer
## World text (names, AP, damage numbers) drawn as 2D labels that follow
## points in the 3D world. Drawn after the 3D view, so the text stays crisp at
## any internal resolution or retro style. Labels shrink with distance like
## world text would.

## The one in the scene, for code that makes world text (null if none).
static var instance: ScreenLabels

## Camera distance at which labels show at full size.
const REFERENCE_DISTANCE := 25.0
const MIN_SCALE := 0.8
const MAX_SCALE := 1.2

## Labels following a node: [label (Label or RichTextLabel), anchor node,
## world offset, screen offset in pixels (scaled with the label)].
var _followers: Array = []
## Labels at a world point: [label, point].
var _fixed: Array = []
var _settings := {}  # font size -> LabelSettings


func _ready() -> void:
	layer = 0  # over the 3D view and retro screen pass, under the HUD
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


## A label that follows `anchor` (offset in world units), until it is freed.
func follow(anchor: Node3D, offset: Vector3, font_size: int = 15) -> Label:
	var label := _make(font_size)
	_followers.append([label, anchor, offset, Vector2.ZERO])
	return label


## Like follow(), with BBCode (e.g. [color]) in its text, drawn screen_offset
## pixels from the anchor point (e.g. stacked above another label).
func follow_rich(anchor: Node3D, offset: Vector3, screen_offset: Vector2 = Vector2.ZERO, font_size: int = 13) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_constant_override("outline_size", maxi(font_size / 3, 3))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.visible = false
	add_child(label)
	_followers.append([label, anchor, offset, screen_offset])
	return label


## Any control (e.g. StatusIcons) following `anchor`, placed like the labels.
## Controls with an is_empty() method are hidden while it returns true.
func follow_control(control: Control, anchor: Node3D, offset: Vector3, screen_offset: Vector2 = Vector2.ZERO) -> Control:
	control.visible = false
	add_child(control)
	_followers.append([control, anchor, offset, screen_offset])
	return control


## Moves a follower's screen offset (e.g. icons stacking above a name).
func set_screen_offset(control: Control, screen_offset: Vector2) -> void:
	for entry: Array in _followers:
		if entry[0] == control:
			entry[3] = screen_offset


## Text that rises and fades at a world point, e.g. damage numbers.
func float_text(at: Vector3, text: String, color: Color, font_size: int = 22) -> void:
	var label := _make(font_size)
	label.text = text
	label.modulate = color
	var entry := [label, at]
	_fixed.append(entry)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_method(func(p: Vector3) -> void: entry[1] = p, at, at + Vector3(0, 1.0, 0), 1.0) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(label, "modulate:a", 0.0, 1.0).set_delay(0.4)
	tween.chain().tween_callback(func() -> void:
		_fixed.erase(entry)
		label.queue_free())


func _make(font_size: int) -> Label:
	if not _settings.has(font_size):
		var settings := LabelSettings.new()
		settings.font_size = font_size
		settings.outline_size = maxi(font_size / 3, 3)
		settings.outline_color = Color(0, 0, 0, 0.9)
		_settings[font_size] = settings
	var label := Label.new()
	label.label_settings = _settings[font_size]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible = false
	add_child(label)
	return label


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	for i in range(_followers.size() - 1, -1, -1):
		var entry: Array = _followers[i]
		var label: Control = entry[0]
		var anchor: Node3D = entry[1]
		if not is_instance_valid(label) or not is_instance_valid(anchor):
			if is_instance_valid(label):
				label.queue_free()
			_followers.remove_at(i)
			continue
		if not anchor.is_visible_in_tree():
			label.visible = false
			continue
		_place(label, anchor.global_position + entry[2], camera, entry[3])
	for entry: Array in _fixed:
		_place(entry[0], entry[1], camera)


func _place(label: Control, at: Vector3, camera: Camera3D, screen_offset: Vector2 = Vector2.ZERO) -> void:
	var empty: bool = label.call("is_empty") if label.has_method("is_empty") else label.get("text") == ""
	if camera == null or empty or camera.is_position_behind(at):
		label.visible = false
		return
	var scale := clampf(REFERENCE_DISTANCE / camera.global_position.distance_to(at), MIN_SCALE, MAX_SCALE)
	label.scale = Vector2(scale, scale)
	var size := label.get_combined_minimum_size()
	if label is RichTextLabel:
		var rich := label as RichTextLabel
		size = Vector2(rich.get_content_width(), rich.get_content_height())
	label.size = size
	label.pivot_offset = Vector2(size.x / 2.0, size.y)
	label.position = (camera.unproject_position(at) + screen_offset * scale - Vector2(size.x / 2.0, size.y)).round()
	label.visible = true
