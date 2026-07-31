extends Node
## Ported from server/src/rooms/GameRoom.ts: match/round rules + bot AI, with
## all Colyseus networking (rooms, clients, schema sync, lobby/host controls)
## stripped out. This autoload IS the authoritative match - callers drive it
## with tick()/bot_tick(dt) on a virtual clock and read state directly off
## the public vars below (no client/server split needed locally).
##
## Bots call the exact same handle_x methods a human input message would (with
## a synthetic id), so they're subject to the same zone/range/phase validation
## as a human - no special-cased bypass of any rule. WorldGeometry only
## decides *how a bot moves*; every action still gates on the real
## is_own_home/is_enemy_bedroom/distance checks below.

const WorldGeometryScript = preload("res://autoload/world_geometry.gd")

# Server ranges were a touch more generous than the client's prompt range so
# an action never gets rejected right when the prompt says it's available.
const PICKUP_RANGE: float = 72.0 * WorldGeometryScript.WORLD_SCALE
const LOCK_RESCUE_RANGE: float = 82.0 * WorldGeometryScript.WORLD_SCALE
const ROUND_TIME: float = 300.0
const WINS_NEEDED: int = 2
const PRE_ROUND_COUNTDOWN: float = 3.0
const ROUND_END_PAUSE: float = 3.0
const JAIL_TIME: float = 60.0
const BOT_SPEED: float = 220.0 * WorldGeometryScript.WORLD_SCALE
const BOT_CARRY_SPEED: float = 160.0 * WorldGeometryScript.WORLD_SCALE
const BOT_TICK_MS: float = 250.0

# ---- bot decision weights ----
# Utility-scored AI: every decide cycle a bot scores EVERY plausible action
# (score = value - cost*pathDistance - risk*threat - coordination + noise,
# plus a commit bonus on whatever it's already doing) and adopts the best.
const BOT_DECIDE_MS: float = 1000.0 # re-score cadence: the bot's reaction speed
const BOT_DECIDE_JITTER_MS: float = 300.0 # de-syncs teammates' decide ticks
const BOT_VALUE_DEPOSIT: float = 100000.0 # carrying cash home is near-absolute
const BOT_VALUE_RESCUE: float = 6000.0 # a freed teammate outweighs any single bundle
const BOT_VALUE_DEFEND: float = 4000.0 # scaled by zeal per bot
const BOT_VALUE_BUNDLE: float = 3000.0 # every bundle is worth the same base
const BOT_VALUE_PATROL: float = 150.0 # fallback: wins only when everything else is bad
const BOT_COST_WEIGHT: float = 0.6 # score lost per world-unit of graph path distance
const BOT_RISK_WEIGHT: float = 1400.0 # score lost per enemy sitting on a chokepoint/target
const BOT_VISION_RADIUS: float = 420.0 * WorldGeometryScript.WORLD_SCALE
const BOT_COMMIT_BONUS: float = 700.0 # stickiness: current task wins ties and near-ties
const BOT_COORD_PENALTY: float = 2600.0 # a teammate already handles it - usually pick something else
const BOT_CHOICE_NOISE: float = 250.0 # imperfection: +-jitter per candidate per re-score
const BOT_VIA_ARRIVE: float = 60.0 * WorldGeometryScript.WORLD_SCALE
const BOT_RADIUS: float = 20.0 # fixed world-unit size, does NOT scale with WORLD_SCALE
const BOT_SUBSTEP: float = BOT_RADIUS / 2.0
const BOT_DEFEND_GRACE_MS: float = 1500.0
const BOT_PATROL_MIN_MS: float = 3000.0
const BOT_PATROL_VAR_MS: float = 4000.0
const BOT_PATROL_ARRIVE: float = 40.0 * WorldGeometryScript.WORLD_SCALE

# Loop through the map's shared spine - reachable by BOTH teams.
const PATROL_NODES: Array[String] = ["livingB", "gateB_garden", "garden", "gateA_garden", "livingA"]

const MIN_TEAM_SIZE: int = 2
const MAX_TEAM_SIZE: int = 4
const MIN_BUNDLES: int = 3
const MAX_BUNDLES: int = 5

# ---- match config ----
var team_size: int = 2
var bundles_per_bedroom: int = 5
var bundle_pos: Dictionary = {"bedroomB": [], "bedroomA": []}
var score_slots: Dictionary = {"A": [], "B": []}
var slots: Dictionary = {} # id -> {team, slot}
# Tracks bundles carried away from an enemy's SCORED pile, so that if the
# thief is caught the point is restored to the team that had earned it.
var stolen_from: Dictionary = {} # bundle_id -> team
var bot_ids: Array[String] = []
var bot_minds: Dictionary = {} # id -> BotMind

# ---- match/round state (was the networked Colyseus GameState) ----
var phase: String = "waiting" # "waiting" | "countdown" | "playing" | "roundEnd" | "matchEnd"
var win_score: int = 5
var round_timer: float = ROUND_TIME
var countdown: float = PRE_ROUND_COUNTDOWN
var score_a: int = 0
var score_b: int = 0
var round_number: int = 1
var wins_a: int = 0
var wins_b: int = 0
var round_winner: String = "" # "A" | "B" | ""
var match_winner: String = "" # "A" | "B" | ""
var players: Dictionary = {} # id -> PlayerState
var cash_bundles: Dictionary = {} # id -> CashBundleState

# Virtual sim clock in ms, advanced by the caller's step loop - replaces
# Colyseus's this.clock.currentTime.
var now_ms: float = 0.0

static func win_score_for_bundles(bundles: int) -> int:
	return bundles * 2 - 1

func _pos(o) -> Vector2:
	return Vector2(o.x, o.y)

func _distance(a, b) -> float:
	return _pos(a).distance_to(_pos(b))

func _origin_bedroom(bundle_id: String) -> String:
	return "bedroomB" if bundle_id.begins_with("b") else "bedroomA"

func _origin_position(bundle_id: String) -> Vector2:
	var bedroom := _origin_bedroom(bundle_id)
	var idx := maxi(0, bundle_id.substr(1).to_int() - 1)
	var list: Array = bundle_pos[bedroom]
	return list[mini(idx, list.size() - 1)]

# ---- match setup ----

## Configures a fresh match (replaces onCreate). Does not start it - call
## add_bot() for each seat, then start_countdown().
func setup_match(p_team_size: int, p_bundles: int) -> void:
	team_size = clampi(p_team_size, MIN_TEAM_SIZE, MAX_TEAM_SIZE)
	bundles_per_bedroom = clampi(p_bundles, MIN_BUNDLES, MAX_BUNDLES)

	bundle_pos = {
		"bedroomB": WorldGeometry.bundle_positions("bedroomB", bundles_per_bedroom),
		"bedroomA": WorldGeometry.bundle_positions("bedroomA", bundles_per_bedroom),
	}
	# A team can end up banking every bundle in the match (its enemy's N plus
	# its own N stolen back), so the score stack needs 2N distinct slots.
	score_slots = {
		"B": WorldGeometry.score_slot_positions("B", bundles_per_bedroom * 2),
		"A": WorldGeometry.score_slot_positions("A", bundles_per_bedroom * 2),
	}

	phase = "waiting"
	win_score = win_score_for_bundles(bundles_per_bedroom)
	round_timer = ROUND_TIME
	countdown = PRE_ROUND_COUNTDOWN
	score_a = 0
	score_b = 0
	round_number = 1
	wins_a = 0
	wins_b = 0
	round_winner = ""
	match_winner = ""
	players.clear()
	cash_bundles.clear()
	slots.clear()
	stolen_from.clear()
	bot_ids.clear()
	bot_minds.clear()
	now_ms = 0.0

func _first_free_slot(team: String) -> int:
	var taken := {}
	for sid in slots:
		var s: Dictionary = slots[sid]
		if s["team"] == team:
			taken[s["slot"]] = true
	var slot := 0
	while taken.has(slot):
		slot += 1
	return mini(slot, WorldGeometry.SPAWN_POINTS[team].size() - 1)

## Adds a synthetic bot player to `team` and returns its id.
func add_bot(team: String) -> String:
	var slot := _first_free_slot(team)
	var id := "bot-%s-%d" % [team, slot]
	slots[id] = {"team": team, "slot": slot}
	bot_ids.append(id)

	var spawn: Vector2 = WorldGeometry.SPAWN_POINTS[team][slot]
	var bot := PlayerState.new()
	bot.id = id
	bot.display_name = "Bot %s%d" % [team, slot + 1]
	bot.team = team
	bot.is_bot = true
	bot.x = spawn.x
	bot.y = spawn.y
	players[id] = bot
	return id

# ---- round / match flow ----

func start_countdown() -> void:
	_reset_round_state()
	phase = "countdown"
	countdown = PRE_ROUND_COUNTDOWN

func _reset_round_state() -> void:
	round_winner = ""
	stolen_from.clear()

	cash_bundles.clear()
	_init_cash_bundles()
	_derive_scores()

	for sid in players:
		var player: PlayerState = players[sid]
		player.is_carrying_cash = false
		player.is_jailed = false
		player.jail_timer = 0
		player.vx = 0
		player.vy = 0
		if slots.has(sid):
			var slot: Dictionary = slots[sid]
			var spawn: Vector2 = WorldGeometry.SPAWN_POINTS[slot["team"]][slot["slot"]]
			player.x = spawn.x
			player.y = spawn.y

func _init_cash_bundles() -> void:
	var list_b: Array = bundle_pos["bedroomB"]
	for i in range(list_b.size()):
		var pos: Vector2 = list_b[i]
		var bundle := CashBundleState.new()
		bundle.id = "b%d" % (i + 1)
		bundle.x = pos.x
		bundle.y = pos.y
		bundle.location = "bedroomB"
		bundle.is_scored = false
		cash_bundles[bundle.id] = bundle
	var list_a: Array = bundle_pos["bedroomA"]
	for i in range(list_a.size()):
		var pos: Vector2 = list_a[i]
		var bundle := CashBundleState.new()
		bundle.id = "a%d" % (i + 1)
		bundle.x = pos.x
		bundle.y = pos.y
		bundle.location = "bedroomA"
		bundle.is_scored = false
		cash_bundles[bundle.id] = bundle

## 1Hz tick: countdown/round-timer/jail-timer advancement and phase transitions.
func tick() -> void:
	if phase == "countdown":
		countdown -= 1
		if countdown <= 0:
			phase = "playing"
			round_timer = ROUND_TIME
	elif phase == "playing":
		round_timer -= 1

		for pid in players:
			var player: PlayerState = players[pid]
			if player.is_jailed:
				player.jail_timer -= 1
				if player.jail_timer <= 0:
					player.jail_timer = 0
					player.is_jailed = false

		if round_timer <= 0:
			round_timer = 0
			_finish_round_by_timeout()
	elif phase == "roundEnd":
		countdown -= 1
		if countdown <= 0:
			if match_winner != "":
				phase = "matchEnd"
			else:
				if round_winner != "":
					round_number += 1
				start_countdown()

func _check_win() -> void:
	if phase != "playing":
		return
	if score_a >= win_score:
		_finalize_round("A")
	elif score_b >= win_score:
		_finalize_round("B")

func _finalize_round(winner: String) -> void:
	round_winner = winner
	if winner == "A":
		wins_a += 1
	else:
		wins_b += 1

	phase = "roundEnd"
	countdown = ROUND_END_PAUSE

	if wins_a >= WINS_NEEDED or wins_b >= WINS_NEEDED:
		match_winner = "A" if wins_a > wins_b else "B"

func _finish_round_by_timeout() -> void:
	if phase != "playing":
		return
	if score_a == score_b:
		round_winner = ""
		phase = "roundEnd"
		countdown = ROUND_END_PAUSE
	else:
		_finalize_round("A" if score_a > score_b else "B")

# ---- cash bundle bookkeeping ----

func _find_carried_bundle(player_id: String) -> CashBundleState:
	for bid in cash_bundles:
		var b: CashBundleState = cash_bundles[bid]
		if b.location == "carried:%s" % player_id:
			return b
	return null

## Score is DERIVED from bundle state: a team's score is the number of
## bundles currently sitting in ITS master bedroom (unstolen originals) plus
## everything it has banked. Deriving (never incrementing) makes score drift
## impossible.
func _derive_scores() -> void:
	var a := 0
	var b := 0
	for bid in cash_bundles:
		var bundle: CashBundleState = cash_bundles[bid]
		if bundle.location == "scored:A" or bundle.location == "bedroomA":
			a += 1
		elif bundle.location == "scored:B" or bundle.location == "bedroomB":
			b += 1
	score_a = a
	score_b = b

## Sends a carried bundle home. If it was stolen from a scored pile and the
## carrier never completed the deposit, restore it to the team that had
## earned it; otherwise it returns to its original bedroom as a fresh target.
func _return_carried_bundle(bundle: CashBundleState) -> void:
	if stolen_from.has(bundle.id):
		var restored_team: String = stolen_from[bundle.id]
		var pos := _free_score_slot(restored_team)
		bundle.location = "scored:%s" % restored_team
		bundle.is_scored = true
		bundle.x = pos.x
		bundle.y = pos.y
	else:
		var pos := _origin_position(bundle.id)
		bundle.location = _origin_bedroom(bundle.id)
		bundle.is_scored = false
		bundle.x = pos.x
		bundle.y = pos.y
	stolen_from.erase(bundle.id)

## First score-stack slot not already occupied by one of `team`'s scored
## bundles, so no two piles can ever land on the same position.
func _free_score_slot(team: String) -> Vector2:
	var slot_list: Array = score_slots[team]
	var occupied := {}
	for bid in cash_bundles:
		var b: CashBundleState = cash_bundles[bid]
		if b.location == "scored:%s" % team:
			occupied["%s,%s" % [b.x, b.y]] = true
	for pos in slot_list:
		if not occupied.has("%s,%s" % [pos.x, pos.y]):
			return pos
	return slot_list[slot_list.size() - 1]

# ---- action handlers ----
# Same validation a human input message would get - bots call these too.

func handle_move(session_id: String, mx: float, my: float, mvx: float, mvy: float) -> void:
	var player: PlayerState = players.get(session_id)
	if player == null or phase != "playing" or player.is_jailed:
		return
	player.x = clampf(mx, 0, WorldGeometry.WORLD_WIDTH)
	player.y = clampf(my, 0, WorldGeometry.WORLD_HEIGHT)
	player.vx = mvx
	player.vy = mvy

func handle_pickup(session_id: String, bundle_id: String) -> void:
	var player: PlayerState = players.get(session_id)
	if player == null or phase != "playing" or player.is_jailed or player.is_carrying_cash:
		return
	var bundle: CashBundleState = cash_bundles.get(bundle_id)
	if bundle == null:
		return

	var enemy_bedroom := "bedroomA" if player.team == "B" else "bedroomB"
	if bundle.location != enemy_bedroom:
		return
	if not WorldGeometry.is_enemy_bedroom(player.team, player.x, player.y):
		return
	if _distance(player, bundle) > PICKUP_RANGE:
		return

	bundle.location = "carried:%s" % player.id
	bundle.is_scored = false
	stolen_from.erase(bundle.id)
	player.is_carrying_cash = true
	_derive_scores() # the victim's bedroom count drops the moment it's grabbed

func handle_steal_scored(session_id: String, bundle_id: String) -> void:
	var player: PlayerState = players.get(session_id)
	if player == null or phase != "playing" or player.is_jailed or player.is_carrying_cash:
		return
	var bundle: CashBundleState = cash_bundles.get(bundle_id)
	if bundle == null:
		return

	var enemy_team := "A" if player.team == "B" else "B"
	if bundle.location != "scored:%s" % enemy_team:
		return
	if not WorldGeometry.is_enemy_bedroom(player.team, player.x, player.y):
		return
	if _distance(player, bundle) > PICKUP_RANGE:
		return

	bundle.location = "carried:%s" % player.id
	bundle.is_scored = false
	stolen_from[bundle.id] = enemy_team # remember to restore if the thief is caught
	player.is_carrying_cash = true
	_derive_scores()

func handle_deposit(session_id: String, bundle_id: String) -> void:
	var player: PlayerState = players.get(session_id)
	if player == null or phase != "playing" or not player.is_carrying_cash:
		return
	var bundle: CashBundleState = cash_bundles.get(bundle_id)
	if bundle == null or bundle.location != "carried:%s" % player.id:
		return
	if not WorldGeometry.is_own_home(player.team, player.x, player.y):
		return

	var team := player.team
	var pos := _free_score_slot(team)
	bundle.location = "scored:%s" % team
	bundle.is_scored = true
	bundle.x = pos.x
	bundle.y = pos.y
	stolen_from.erase(bundle.id) # deposit completed - no longer restorable
	player.is_carrying_cash = false

	_derive_scores()
	_check_win()

func handle_lock(session_id: String, target_id: String) -> void:
	var player: PlayerState = players.get(session_id)
	var target: PlayerState = players.get(target_id)
	if player == null or target == null or phase != "playing":
		return
	if player.team == target.team:
		return
	if player.is_jailed or target.is_jailed:
		return

	var my_zone := WorldGeometry.get_zone_at(player.x, player.y)
	var target_zone := WorldGeometry.get_zone_at(target.x, target.y)
	if my_zone != target_zone:
		return
	if not WorldGeometry.is_own_home(player.team, player.x, player.y):
		return
	if _distance(player, target) > LOCK_RESCUE_RANGE:
		return

	if target.is_carrying_cash:
		var bundle := _find_carried_bundle(target.id)
		if bundle != null:
			_return_carried_bundle(bundle)
		target.is_carrying_cash = false

	target.is_jailed = true
	target.jail_timer = JAIL_TIME
	var jail_zone := WorldGeometry.jail_basement_for_team(target.team)
	var jail_pos: Vector2 = WorldGeometry.JAIL_POSITIONS[jail_zone]
	target.x = jail_pos.x
	target.y = jail_pos.y
	target.vx = 0
	target.vy = 0

	_derive_scores()
	_check_win()

func handle_rescue(session_id: String, target_id: String) -> void:
	var player: PlayerState = players.get(session_id)
	var target: PlayerState = players.get(target_id)
	if player == null or target == null or phase != "playing":
		return
	if player.is_jailed: # a jailed player can't rescue anyone
		return
	if player.team != target.team:
		return
	if not target.is_jailed:
		return

	var required_zone := WorldGeometry.jail_basement_for_team(player.team)
	if WorldGeometry.get_zone_at(player.x, player.y) != required_zone:
		return
	if _distance(player, target) > LOCK_RESCUE_RANGE:
		return

	target.is_jailed = false
	target.jail_timer = 0

# ---- AI bots ----

func bot_tick(dt: float) -> void:
	if phase != "playing" or bot_ids.is_empty():
		return
	for id in bot_ids:
		_step_bot(id, dt)

func _bot_mind(id: String) -> BotMind:
	if not bot_minds.has(id):
		var m := BotMind.new()
		m.zeal = 0.2 + randf() * 0.8
		bot_minds[id] = m
	return bot_minds[id]

## Decide/move decoupling: movement runs every bot_tick(dt) toward the
## committed target, but the full utility re-score only runs every
## BOT_DECIDE_MS (or immediately when the current task resolves).
func _step_bot(id: String, dt: float) -> void:
	var bot: PlayerState = players.get(id)
	if bot == null:
		return
	var mind := _bot_mind(id)
	if bot.is_jailed:
		bot.vx = 0
		bot.vy = 0
		mind.task = "" # re-decide fresh on release
		return

	var team := bot.team
	var now := now_ms

	_validate_bot_task(bot, mind, team, now)
	if mind.task == "" or now >= mind.next_decide_at:
		_decide_bot_task(bot, id, mind, team, now)
	_execute_bot_task(bot, id, mind, team, now, dt)

## Does the committed task still make sense between re-scores? Clears it on
## resolution so the bot re-decides immediately instead of executing on a
## dead target until the next decide tick.
func _validate_bot_task(bot: PlayerState, mind: BotMind, team: String, now: float) -> void:
	match mind.task:
		"rescue":
			var t: PlayerState = players.get(mind.target_id)
			if t == null or not t.is_jailed or t.team != team or bot.is_carrying_cash:
				mind.task = ""
		"defend":
			var t: PlayerState = players.get(mind.target_id)
			if t == null or t.is_jailed or bot.is_carrying_cash:
				mind.task = ""
			elif WorldGeometry.is_own_home(team, t.x, t.y):
				mind.last_seen_home_at = now
			elif now - mind.last_seen_home_at > BOT_DEFEND_GRACE_MS:
				mind.task = ""
		"deposit":
			if not bot.is_carrying_cash:
				mind.task = ""
		"raid":
			var b: CashBundleState = cash_bundles.get(mind.target_id)
			if bot.is_carrying_cash or b == null or b.location != _enemy_bedroom_of(team):
				mind.task = ""
		"patrol":
			pass # filler - always droppable, re-rolled in execute
	if mind.task == "":
		mind.target_id = ""
		mind.via = ""

func _noise() -> float:
	return (randf() * 2.0 - 1.0) * BOT_CHOICE_NOISE

func _enemy_bedroom_of(team: String) -> String:
	return "bedroomA" if team == "B" else "bedroomB"

## How threatened `point` is for `team`'s bots: each living enemy inside
## BOT_VISION_RADIUS contributes linearly with proximity (0..1 each).
func _threat_at(team: String, point: Vector2) -> float:
	var threat := 0.0
	for pid in players:
		var p: PlayerState = players[pid]
		if p.team == team or p.is_jailed:
			continue
		var d := _pos(p).distance_to(point)
		if d < BOT_VISION_RADIUS:
			threat += 1.0 - d / BOT_VISION_RADIUS
	return threat

## Real route length through the waypoint graph (not straight-line). INF =
## unreachable for this team (its own sealed gates).
func _bot_path_cost(bot: PlayerState, team: String, target_node: String, target_point: Vector2) -> float:
	var start_node := WorldGeometry.nearest_bot_node(bot.x, bot.y)
	if start_node == target_node:
		return _pos(bot).distance_to(target_point)
	var path := WorldGeometry.find_bot_path(team, start_node, target_node)
	if path.size() < 2:
		return INF
	var cost := _pos(bot).distance_to(WorldGeometry.BOT_WAYPOINTS[path[0]])
	for i in range(1, path.size()):
		var wp_prev: Vector2 = WorldGeometry.BOT_WAYPOINTS[path[i - 1]]
		var wp_next: Vector2 = WorldGeometry.BOT_WAYPOINTS[path[i]]
		cost += wp_prev.distance_to(wp_next)
	var wp_last: Vector2 = WorldGeometry.BOT_WAYPOINTS[path[path.size() - 1]]
	cost += wp_last.distance_to(target_point)
	return cost

## Cost AND path-aware threat for a route from the bot to `target_point_obj`,
## optionally detouring through `via` first. via == "" means the direct
## route. Returns null if unreachable.
func _route_plan(bot: PlayerState, team: String, via: String, target_node: String, target_point_obj):
	var target_point := _pos(target_point_obj)
	var start := WorldGeometry.nearest_bot_node(bot.x, bot.y)
	var nodes: Array[String] = []
	if via != "" and via != target_node and via != start:
		var p1 := WorldGeometry.find_bot_path(team, start, via)
		if p1.size() < 2 and start != via:
			return null
		var p2 := WorldGeometry.find_bot_path(team, via, target_node)
		if p2.size() < 2 and via != target_node:
			return null
		nodes.append_array(p1)
		nodes.append_array(p2.slice(1))
	else:
		var p := WorldGeometry.find_bot_path(team, start, target_node)
		if p.size() < 2 and start != target_node:
			return null
		nodes.append_array(p)

	var cost := _pos(bot).distance_to(WorldGeometry.BOT_WAYPOINTS[nodes[0]])
	var threat := _threat_at(team, target_point)
	for i in range(nodes.size()):
		if i > 0:
			var wp_prev: Vector2 = WorldGeometry.BOT_WAYPOINTS[nodes[i - 1]]
			var wp_cur: Vector2 = WorldGeometry.BOT_WAYPOINTS[nodes[i]]
			cost += wp_prev.distance_to(wp_cur)
		threat = maxf(threat, _threat_at(team, WorldGeometry.BOT_WAYPOINTS[nodes[i]]))
	var wp_last: Vector2 = WorldGeometry.BOT_WAYPOINTS[nodes[nodes.size() - 1]]
	cost += wp_last.distance_to(target_point)
	return {"cost": cost, "threat": threat}

func _some_bot_tasked(team: String, task: String, target_id: String, except_id: String) -> bool:
	for bid in bot_ids:
		if bid == except_id:
			continue
		var p: PlayerState = players.get(bid)
		if p == null or p.team != team or p.is_jailed:
			continue
		var m := _bot_mind(bid)
		if m.task == task and m.target_id == target_id:
			return true
	return false

## Where to route a defender: chase directly in the living room and in the
## OWN BACKYARD. Only the own bedroom stays a guard-the-exits case, since
## this team can't enter it at all - it has TWO exits (interior stairs and
## the yard door), so the first defender covers the living-side stairs and
## any pile-on defender covers the yard-side door from inside the yard.
func _defend_approach(team: String, intruder: PlayerState, self_id: String) -> Dictionary:
	var s := WorldGeometry.WORLD_SCALE
	var living := "livingB" if team == "B" else "livingA"
	var yard := "backyardB" if team == "B" else "backyardA"
	var zone := WorldGeometry.get_zone_at(intruder.x, intruder.y)
	if zone == "bedroomB" or zone == "bedroomA":
		if _some_bot_tasked(team, "defend", intruder.id, self_id):
			var aim := Vector2(110 * s, 100 * s) if team == "B" else Vector2(1490 * s, 100 * s)
			return {"node": yard, "aim": aim} # in the yard, at the bedroom's yard door
		var aim2 := Vector2(340 * s, 290 * s) if team == "B" else Vector2(1260 * s, 290 * s)
		return {"node": living, "aim": aim2} # just past the stair corridor's living end
	if zone == "backyardB" or zone == "backyardA":
		return {"node": yard, "aim": _pos(intruder)} # chase them down in our own yard
	return {"node": living, "aim": _pos(intruder)}

## The core: score every plausible candidate action and commit to the best.
func _decide_bot_task(bot: PlayerState, id: String, mind: BotMind, team: String, now: float) -> void:
	mind.next_decide_at = now + BOT_DECIDE_MS + randf() * BOT_DECIDE_JITTER_MS

	var options: Array[Dictionary] = []

	# The enemy house has two ways in: the FRONT route (living room to the
	# interior stair doors) and the YARD route (the yard door, around the
	# outside, in by the backyard doors - sealed only for the owners).
	var enemy_yard := "backyardA" if team == "B" else "backyardB"
	var routes: Array[String] = ["", enemy_yard] # "" = direct/front route

	if bot.is_carrying_cash:
		# Dropping cash mid-map to do anything else is always worse - deposit
		# is the only candidate while carrying.
		var home_node := "livingB" if team == "B" else "livingA"
		var cost := _bot_path_cost(bot, team, home_node, WorldGeometry.BOT_WAYPOINTS[home_node])
		options.append({"task": "deposit", "target_id": "", "via": "", "score": BOT_VALUE_DEPOSIT - BOT_COST_WEIGHT * cost})
	else:
		# Rescue: each jailed teammate, scored on both routes.
		var jail_zone := WorldGeometry.jail_basement_for_team(team)
		for pid in players:
			if pid == id:
				continue
			var p: PlayerState = players[pid]
			if p.team != team or not p.is_jailed:
				continue
			var coord := BOT_COORD_PENALTY * 2.0 if _some_bot_tasked(team, "rescue", pid, id) else 0.0
			for via in routes:
				var plan = _route_plan(bot, team, via, jail_zone, p)
				if plan == null:
					continue
				options.append({
					"task": "rescue", "target_id": pid, "via": via,
					"score": BOT_VALUE_RESCUE - BOT_COST_WEIGHT * plan["cost"] - BOT_RISK_WEIGHT * plan["threat"] - coord + _noise(),
				})

		# Defend: one candidate per intruder in home turf.
		for pid in players:
			if pid == id:
				continue
			var p: PlayerState = players[pid]
			if p.team == team or p.is_jailed:
				continue
			if not WorldGeometry.is_own_home(team, p.x, p.y):
				continue
			var approach := _defend_approach(team, p, id)
			var cost := _bot_path_cost(bot, team, approach["node"], approach["aim"])
			if not is_finite(cost):
				continue
			var value := BOT_VALUE_DEFEND * (0.8 + 0.4 * mind.zeal)
			var coord := BOT_COORD_PENALTY * (1.0 - mind.zeal) if _some_bot_tasked(team, "defend", pid, id) else 0.0
			options.append({
				"task": "defend", "target_id": pid, "via": "",
				"score": value - BOT_COST_WEIGHT * cost - coord + _noise(),
			})

		# Steal: each unscored bundle, scored on both routes.
		var bedroom := _enemy_bedroom_of(team)
		for bid in cash_bundles:
			var b: CashBundleState = cash_bundles[bid]
			if b.location != bedroom:
				continue
			var coord := BOT_COORD_PENALTY if _some_bot_tasked(team, "raid", b.id, id) else 0.0
			for via in routes:
				var plan = _route_plan(bot, team, via, bedroom, b)
				if plan == null:
					continue
				options.append({
					"task": "raid", "target_id": b.id, "via": via,
					"score": BOT_VALUE_BUNDLE - BOT_COST_WEIGHT * plan["cost"] - BOT_RISK_WEIGHT * plan["threat"] - coord + _noise(),
				})

		# Patrol: the floor under everything.
		options.append({"task": "patrol", "target_id": "", "via": "", "score": BOT_VALUE_PATROL + _noise()})

	var best = null
	for o in options:
		# Commitment: the currently-held choice gets a flat bonus, so a
		# marginal score difference doesn't flip the plan on every re-score.
		var score = o["score"] + (BOT_COMMIT_BONUS if (o["task"] == mind.task and o["target_id"] == mind.target_id) else 0.0)
		if best == null or score > best["score"]:
			best = o.duplicate()
			best["score"] = score
	if best == null:
		return
	if best["task"] != mind.task or best["target_id"] != mind.target_id:
		mind.task = best["task"]
		mind.target_id = best["target_id"]
		mind.via = best["via"]
		if best["task"] == "defend":
			mind.last_seen_home_at = now
		if best["task"] != "patrol":
			mind.patrol_node = ""

func _execute_bot_task(bot: PlayerState, id: String, mind: BotMind, team: String, now: float, dt: float) -> void:
	# Yard-route detour: head to the route waypoint first; once there, the
	# ordinary graph routing continues to the real target.
	if mind.via != "" and (mind.task == "rescue" or mind.task == "raid"):
		var via_point: Vector2 = WorldGeometry.BOT_WAYPOINTS[mind.via]
		if _pos(bot).distance_to(via_point) > BOT_VIA_ARRIVE:
			_bot_move_toward(bot, team, mind.via, via_point, dt)
			return
		mind.via = ""

	match mind.task:
		"rescue":
			var target: PlayerState = players[mind.target_id]
			var jail_zone := WorldGeometry.jail_basement_for_team(team)
			_bot_move_toward(bot, team, jail_zone, _pos(target), dt)
			if WorldGeometry.get_zone_at(bot.x, bot.y) == jail_zone and _distance(bot, target) <= LOCK_RESCUE_RANGE:
				handle_rescue(id, target.id)
		"defend":
			var target: PlayerState = players[mind.target_id]
			var approach := _defend_approach(team, target, id)
			_bot_move_toward(bot, team, approach["node"], approach["aim"], dt)
			if WorldGeometry.is_own_home(team, bot.x, bot.y) and _distance(bot, target) <= LOCK_RESCUE_RANGE:
				handle_lock(id, target.id)
		"deposit":
			var home_node := "livingB" if team == "B" else "livingA"
			var bundle := _find_carried_bundle(id)
			_bot_move_toward(bot, team, home_node, WorldGeometry.BOT_WAYPOINTS[home_node], dt)
			if bundle != null and WorldGeometry.is_own_home(team, bot.x, bot.y):
				handle_deposit(id, bundle.id)
		"raid":
			var bundle: CashBundleState = cash_bundles[mind.target_id]
			var bedroom_node := _enemy_bedroom_of(team)
			_bot_move_toward(bot, team, bedroom_node, _pos(bundle), dt)
			if WorldGeometry.is_enemy_bedroom(team, bot.x, bot.y) and _distance(bot, bundle) <= PICKUP_RANGE:
				handle_pickup(id, bundle.id)
		"patrol":
			if mind.patrol_node == "" or now > mind.patrol_until or _pos(bot).distance_to(WorldGeometry.BOT_WAYPOINTS[mind.patrol_node]) < BOT_PATROL_ARRIVE:
				var patrol_options: Array = PATROL_NODES.filter(func(n): return n != mind.patrol_node)
				mind.patrol_node = patrol_options[randi() % patrol_options.size()]
				mind.patrol_until = now + BOT_PATROL_MIN_MS + randf() * BOT_PATROL_VAR_MS
			_bot_move_toward(bot, team, mind.patrol_node, WorldGeometry.BOT_WAYPOINTS[mind.patrol_node], dt)
		_:
			bot.vx = 0
			bot.vy = 0

## Steers `bot` one tick toward `final_target`, routing through the waypoint
## graph until it's in the same node/room as the target, then beelining the
## rest of the way. Movement is applied in sub-steps with a circle-vs-AABB
## resolve after each, so bots slide along walls instead of clipping them.
func _bot_move_toward(bot: PlayerState, team: String, target_node: String, final_target: Vector2, dt: float) -> void:
	var current_node := WorldGeometry.nearest_bot_node(bot.x, bot.y)
	var speed := BOT_CARRY_SPEED if bot.is_carrying_cash else BOT_SPEED

	var aim: Vector2
	if current_node == target_node:
		aim = final_target
	else:
		var path := WorldGeometry.find_bot_path(team, current_node, target_node)
		var next: String = path[1] if path.size() > 1 else target_node
		aim = WorldGeometry.BOT_WAYPOINTS[next]

	var delta := aim - _pos(bot)
	var dist := delta.length()
	if dist < 1.0:
		bot.vx = 0
		bot.vy = 0
		return
	var step := minf(dist, speed * dt)
	var n := delta / dist
	_move_bot_with_collision(bot, team, n.x * step, n.y * step)
	bot.vx = n.x * speed
	bot.vy = n.y * speed

## Move-and-slide, axis-separated, in sub-steps (stops a fast tick from
## tunnelling a thin wall). Each axis is attempted on its own and reverted if
## it would put the bot inside a wall, so a bot pressing diagonally into the
## wall beside a doorway slides along the wall into the gap.
func _move_bot_with_collision(bot: PlayerState, team: String, dx: float, dy: float) -> void:
	var total := Vector2(dx, dy).length()
	var steps := maxi(1, ceili(total / BOT_SUBSTEP))
	var sx := dx / steps
	var sy := dy / steps
	for i in range(steps):
		var ox := bot.x
		bot.x = clampf(bot.x + sx, 0, WorldGeometry.WORLD_WIDTH)
		if _bot_hits_wall(bot, team):
			bot.x = ox
		var oy := bot.y
		bot.y = clampf(bot.y + sy, 0, WorldGeometry.WORLD_HEIGHT)
		if _bot_hits_wall(bot, team):
			bot.y = oy

## True if the bot's body circle overlaps any WALL or its OWN sealed door -
## the enemy's sealed doors are open to this team, so they are not colliders.
func _bot_hits_wall(bot: PlayerState, team: String) -> bool:
	var hits_rect := func(r: Dictionary) -> bool:
		var cx: float = clampf(bot.x, r["x1"], r["x2"])
		var cy: float = clampf(bot.y, r["y1"], r["y2"])
		var ddx := bot.x - cx
		var ddy := bot.y - cy
		return ddx * ddx + ddy * ddy < BOT_RADIUS * BOT_RADIUS
	for r in WorldGeometry.WALLS:
		if hits_rect.call(r):
			return true
	for d in WorldGeometry.SEALED_DOORS:
		if d["team"] == team and hits_rect.call(d):
			return true
	return false
