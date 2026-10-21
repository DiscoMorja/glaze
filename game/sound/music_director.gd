class_name MusicDirector
extends Node
## Background music by mood (SoundBank.MUSIC): menu, hub (near the village),
## wilds, dungeon, combat, big_fight (many enemies) and a victory stinger after
## a won fight. Tracks crossfade; each mood plays its tracks in turn. Tracks
## load on a thread (they're large), so a change of mood never stalls a frame.
## Exploring moods wait MOOD_SETTLE_SECONDS before switching, so walking
## along the village edge doesn't flip the music back and forth; fights cut
## in at once.

const FADE_SECONDS := 2.5
const COMBAT_FADE_SECONDS := 0.8
const MOOD_SETTLE_SECONDS := 4.0
## Enemies in a fight from which it gets the big-fight music.
const BIG_FIGHT := 5
const SILENT_DB := -40.0

var mood := ""
var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _next_track := {}
var _loading := ""
var _loading_mood := ""
var _wanted := ""
var _wanted_since := 0.0
var _stinger := false


func _ready() -> void:
	SoundBank.ensure_buses()
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = "Music"
		player.volume_db = SILENT_DB
		add_child(player)
		player.finished.connect(_on_finished.bind(player))
		_players.append(player)


## The mood the world calls for now (see the class notes).
static func mood_for(state: SimState, level: GameLevel, listener: SimEntity) -> String:
	if state == null:
		return ""
	if state.combat.active:
		var enemies := CombatRules.fighters(state, SimEntity.Faction.ENEMIES).size()
		return "big_fight" if enemies >= BIG_FIGHT else "combat"
	var base := level.music if level != null else "wilds"
	if base == "wilds" and level != null and level.hub_group != "" and listener != null:
		for e in state.entities:
			if e.group == level.hub_group and e.is_alive() and e.takes_turns() \
					and SimAbilities.in_range(e.cell, listener.cell, level.hub_radius):
				return "hub"
	return base


## Asks for a mood; exploring moods switch once asked for long enough.
func request(new_mood: String) -> void:
	if new_mood == "" or _stinger:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if new_mood != _wanted:
		_wanted = new_mood
		_wanted_since = now
	var urgent := new_mood in ["combat", "big_fight", "menu"] or mood == ""
	if new_mood != mood and (urgent or now - _wanted_since >= MOOD_SETTLE_SECONDS):
		_switch(new_mood)


## A won fight: the victory stinger, then back to exploring.
func victory() -> void:
	var tracks := SoundBank.music_of("victory")
	if tracks.is_empty():
		return
	_stinger = true
	mood = "victory"
	_load(tracks[0], "victory")


func _process(_delta: float) -> void:
	if _loading == "":
		return
	var status := ResourceLoader.load_threaded_get_status(_loading)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var stream := ResourceLoader.load_threaded_get(_loading) as AudioStream
		var for_mood := _loading_mood
		_loading = ""
		if stream != null and for_mood == mood:
			_crossfade(stream, COMBAT_FADE_SECONDS if mood in ["combat", "big_fight", "victory"] else FADE_SECONDS)
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		_loading = ""


func _switch(new_mood: String) -> void:
	mood = new_mood
	var tracks := SoundBank.music_of(new_mood)
	if tracks.is_empty():
		_fade_out_all()
		return
	var i: int = _next_track.get(new_mood, randi() % tracks.size())
	_next_track[new_mood] = (i + 1) % tracks.size()
	_load(tracks[i % tracks.size()], new_mood)


func _load(path: String, for_mood: String) -> void:
	if ResourceLoader.has_cached(path):
		_crossfade(load(path), COMBAT_FADE_SECONDS if for_mood in ["combat", "big_fight", "victory"] else FADE_SECONDS)
		return
	_loading = path
	_loading_mood = for_mood
	ResourceLoader.load_threaded_request(path, "AudioStream")


func _crossfade(stream: AudioStream, seconds: float) -> void:
	var old := _players[_active]
	_active = 1 - _active
	var new := _players[_active]
	new.stream = stream
	new.volume_db = SILENT_DB
	new.play()
	var tween := create_tween().set_parallel(true)
	tween.tween_property(new, "volume_db", 0.0, seconds)
	if old.playing:
		tween.tween_property(old, "volume_db", SILENT_DB, seconds)
		tween.chain().tween_callback(old.stop)


func _fade_out_all() -> void:
	var tween := create_tween().set_parallel(true)
	for player in _players:
		if player.playing:
			tween.tween_property(player, "volume_db", SILENT_DB, FADE_SECONDS)


## A track ended: the stinger hands back to exploring, a mood plays its next.
func _on_finished(player: AudioStreamPlayer) -> void:
	if player != _players[_active]:
		return
	if _stinger:
		_stinger = false
		var back := _wanted if _wanted != "" else "wilds"
		mood = ""
		_switch(back)
		return
	_switch(mood)
