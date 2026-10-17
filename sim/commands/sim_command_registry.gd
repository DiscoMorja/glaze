class_name SimCommandRegistry
extends RefCounted
## Rebuilds commands from their serialized dictionaries (network, replays).
## Register every new command type here.


static func from_dict(data: Dictionary) -> SimCommand:
	match str(data.get("type", "")):
		SpawnSurfaceCommand.TYPE:
			return SpawnSurfaceCommand.from_dict(data)
		SpawnGasCommand.TYPE:
			return SpawnGasCommand.from_dict(data)
		IgniteCommand.TYPE:
			return IgniteCommand.from_dict(data)
		ChillCommand.TYPE:
			return ChillCommand.from_dict(data)
	push_error("Unknown sim command type: %s" % data.get("type"))
	return null
