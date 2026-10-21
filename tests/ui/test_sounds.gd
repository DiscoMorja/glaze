extends GutTest
## The sound bank names real files (when game/audio is there: the game also
## runs without it), every mood has music, and the property-based choices of
## weapon sounds and voices.


func _has_audio() -> bool:
	return DirAccess.dir_exists_absolute(SoundBank.DIR)


func test_every_cue_variant_is_a_file() -> void:
	if not _has_audio():
		pass_test("no audio folder on this machine")
		return
	for cue: String in SoundBank.CUES:
		for name: String in SoundBank.CUES[cue]:
			assert_ne(SoundBank.resolve(SoundBank.DIR + name), "", "%s: %s" % [cue, name])


func test_every_mood_has_music() -> void:
	if not _has_audio():
		pass_test("no audio folder on this machine")
		return
	for mood: String in SoundBank.MUSIC:
		assert_eq(SoundBank.music_of(mood).size(), SoundBank.MUSIC[mood].size(), mood)


func test_event_cues_exist_in_the_bank() -> void:
	for cue: String in EventSounds.CAST_CUES.values() + EventSounds.LAND_CUES.values():
		assert_true(SoundBank.CUES.has(cue), cue)
	for voice in ["party", "brute", "sneak", "folk"]:
		for what in ["hurt", "death"]:
			assert_true(SoundBank.CUES.has("%s_%s" % [voice, what]), "%s_%s" % [voice, what])


func test_weapon_sounds_follow_the_weapon() -> void:
	var e := SimEntity.character("Ari", SimEntity.Faction.PLAYERS, Vector3i.ZERO, 10, "Greatsword", 5)
	assert_eq(EventSounds.weapon_cues(e), ["heavy_swing", "heavy_hit"] as Array[String])
	e.weapon = "Daggers"
	assert_eq(EventSounds.weapon_cues(e), ["blade_swing", "blade_hit"] as Array[String])
	e.weapon = "Staff"
	assert_eq(EventSounds.weapon_cues(e), ["staff_swing", "staff_hit"] as Array[String])
	e.weapon = "Shortbow"
	assert_eq(EventSounds.weapon_cues(e)[1], "arrow_hit")
	e.weapon = ""
	assert_eq(EventSounds.weapon_cues(e)[1], "punch")
	e.weapon = "Fine sword"  # strength, one-handed but heavy
	assert_eq(EventSounds.weapon_cues(e), ["heavy_swing", "heavy_hit"] as Array[String])
	e.weapon = "Knife"
	assert_eq(EventSounds.weapon_cues(e), ["blade_swing", "blade_hit"] as Array[String])


func test_voices_follow_side_and_weapon() -> void:
	var make := func(faction: SimEntity.Faction, weapon: String) -> SimEntity:
		return SimEntity.character("X", faction, Vector3i.ZERO, 10, weapon, 3)
	assert_eq(EventSounds.voice_of(make.call(SimEntity.Faction.PLAYERS, "Club")), "party")
	assert_eq(EventSounds.voice_of(make.call(SimEntity.Faction.NEUTRAL, "")), "folk")
	assert_eq(EventSounds.voice_of(make.call(SimEntity.Faction.ENEMIES, "Greataxe")), "brute")
	assert_eq(EventSounds.voice_of(make.call(SimEntity.Faction.ENEMIES, "Knife")), "sneak")
