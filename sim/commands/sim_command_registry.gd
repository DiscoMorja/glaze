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
		MoveCommand.TYPE:
			return MoveCommand.from_dict(data)
		AttackCommand.TYPE:
			return AttackCommand.from_dict(data)
		CastCommand.TYPE:
			return CastCommand.from_dict(data)
		EndTurnCommand.TYPE:
			return EndTurnCommand.from_dict(data)
		StartCombatCommand.TYPE:
			return StartCombatCommand.from_dict(data)
		TravelCommand.TYPE:
			return TravelCommand.from_dict(data)
		SneakCommand.TYPE:
			return SneakCommand.from_dict(data)
		GiveCommand.TYPE:
			return GiveCommand.from_dict(data)
		SortItemCommand.TYPE:
			return SortItemCommand.from_dict(data)
		TalkCommand.TYPE:
			return TalkCommand.from_dict(data)
		ChooseCommand.TYPE:
			return ChooseCommand.from_dict(data)
		LootCommand.TYPE:
			return LootCommand.from_dict(data)
		UseItemCommand.TYPE:
			return UseItemCommand.from_dict(data)
		RestCommand.TYPE:
			return RestCommand.from_dict(data)
		TradeCommand.TYPE:
			return TradeCommand.from_dict(data)
		EquipCommand.TYPE:
			return EquipCommand.from_dict(data)
		SpendPointCommand.TYPE:
			return SpendPointCommand.from_dict(data)
		UseExitCommand.TYPE:
			return UseExitCommand.from_dict(data)
	push_error("Unknown sim command type: %s" % data.get("type"))
	return null
