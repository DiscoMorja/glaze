class_name TradeCommand
extends SimCommand
## Outside combat: a party member buys items (indices into the trader's
## inventory) and sells items (indices into their own) with a trader next to
## them, in one deal. Gold makes up the difference both ways; the deal fails
## if either side can't pay. Prices (price_of / offer_for):
##   - buying costs the item's value, 5 % less per rank of the buyer's
##     Charisma (rounded up); a suspicious trader asks half again
##   - selling fetches half the value, 5 % more per rank of the seller's
##     Charisma (rounded down); money (Gold, Coins) is taken at full value
##   - a trader won't buy what was stolen from its own group (it knows its
##     own things); anything else stolen sells, and loses its stolen tag

const TYPE := "trade"
const REACH := 2

var buyer_id: int
var trader_id: int
var buy: Array[int] = []
var sell: Array[int] = []


func _init(p_buyer_id: int = -1, p_trader_id: int = -1, p_buy: Array[int] = [], p_sell: Array[int] = []) -> void:
	buyer_id = p_buyer_id
	trader_id = p_trader_id
	buy = p_buy.duplicate()
	sell = p_sell.duplicate()


func get_type() -> String:
	return TYPE


func actor_id() -> int:
	return buyer_id


## Percent of an item's value per rank of Charisma off buying, onto selling.
const CHARISMA_PERCENT := 5


@warning_ignore("integer_division")
static func price_of(trader: SimEntity, item: String, buyer: SimEntity = null) -> int:
	var percent := 100 - CHARISMA_PERCENT * (buyer.charisma if buyer != null else 0)
	var value := (SimItems.value_of(item) * percent + 99) / 100
	return value * 3 / 2 if trader.suspicious else value


@warning_ignore("integer_division")
static func offer_for(item: String, seller: SimEntity = null) -> int:
	var value := SimItems.value_of(item)
	if SimItems.has_property(item, "money"):
		return value
	return value * (50 + CHARISMA_PERCENT * (seller.charisma if seller != null else 0)) / 100


## The trader refuses this item from this seller (it was stolen from them).
static func refuses(trader: SimEntity, seller: SimEntity, item: String) -> bool:
	for tag in seller.stolen:
		if tag.get_slice(":", 1) == item and int(tag.get_slice(":", 0)) == trader.pack and trader.pack > 0:
			return true
	return false


## Someone the buyer can trade with right now.
static func can_trade(state: SimState, buyer: SimEntity, trader: SimEntity) -> bool:
	if state.combat.active or buyer == null or trader == null or buyer == trader:
		return false
	if buyer.faction != SimEntity.Faction.PLAYERS or not buyer.is_alive():
		return false
	if not trader.trader or not trader.is_alive() or trader.faction != SimEntity.Faction.NEUTRAL:
		return false
	return maxi(absi(trader.cell.x - buyer.cell.x), absi(trader.cell.z - buyer.cell.z)) <= REACH


## Gold the buyer pays (negative: receives) for this deal.
static func balance(trader: SimEntity, buyer: SimEntity, p_buy: Array[int], p_sell: Array[int]) -> int:
	var total := 0
	for i in p_buy:
		total += price_of(trader, trader.inventory[i], buyer)
	for i in p_sell:
		total -= offer_for(buyer.inventory[i], buyer)
	return total


static func _valid_indices(indices: Array[int], size: int) -> bool:
	var seen := {}
	for i in indices:
		if i < 0 or i >= size or seen.has(i):
			return false
		seen[i] = true
	return true


func validate(state: SimState) -> bool:
	var buyer := state.get_entity(buyer_id)
	var trader := state.get_entity(trader_id)
	if not can_trade(state, buyer, trader) or (buy.is_empty() and sell.is_empty()):
		return false
	if not _valid_indices(buy, trader.inventory.size()) or not _valid_indices(sell, buyer.inventory.size()):
		return false
	for i in sell:
		if refuses(trader, buyer, buyer.inventory[i]):
			return false
	var pay := balance(trader, buyer, buy, sell)
	return buyer.gold >= pay and trader.gold >= -pay


func execute(state: SimState) -> void:
	var buyer := state.get_entity(buyer_id)
	var trader := state.get_entity(trader_id)
	var pay := balance(trader, buyer, buy, sell)
	buyer.gold -= pay
	trader.gold += pay
	var bought: Array[String] = []
	for i in buy:
		bought.append(trader.inventory[i])
	var sold: Array[String] = []
	for i in sell:
		sold.append(buyer.inventory[i])
	for item in bought:
		trader.inventory.erase(item)
		buyer.inventory.append(item)
	for item in sold:
		CrimeRules.move_item(buyer, trader, buyer.inventory.find(item))
	trader.stolen.clear()  # fenced: it's the trader's now
	var event := state.emit_event(SimEvent.Type.TRADED, trader.cell, trader.id, buyer.id, pay)
	event.text = ", ".join(bought + sold)


func to_dict() -> Dictionary:
	return {"type": TYPE, "buyer_id": buyer_id, "trader_id": trader_id, "buy": buy.duplicate(), "sell": sell.duplicate()}


static func from_dict(data: Dictionary) -> TradeCommand:
	var p_buy: Array[int] = []
	p_buy.assign(data.buy)
	var p_sell: Array[int] = []
	p_sell.assign(data.sell)
	return TradeCommand.new(data.buyer_id, data.trader_id, p_buy, p_sell)
