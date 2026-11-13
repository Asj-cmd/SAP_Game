class_name MatchStatus
extends RefCounted
## The two lines a player cannot play without, until the real HUD (P5-2).
##
## The debug HUD is off by default, which left a player with no clock, no score
## and no word that a round or the match had ended: the bodies froze, reset and
## carried on, and the only way to find out who won was F1. These read the
## confirmed world and are presentation only.

## One line, top of the screen: round, clock, each team's cash and rounds, and
## what is true about your own body.
static func line(world: SimWorld, level: GreyBoxLevel, mine: SimEntity) -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append("ROUND %d  %s" % [world.round_number, _clock(world)])
	var teams: PackedStringArray = PackedStringArray()
	for team: TeamDef in level.teams:
		teams.append("%s%s %d (rounds %d)" % [
			"> " if mine != null and mine.team == team.id else "",
			team.display_name, world.score_for(team.id), world.round_wins_for(team.id),
		])
	parts.append("   ".join(teams))
	parts.append("cash to win %d" % world.mode.score_to_win())
	if mine != null:
		if mine.is_captured:
			parts.append("JAILED %.0fs" % SimWorld.ticks_to_seconds(mine.capture_ticks_remaining))
		elif mine.is_carrying():
			parts.append("CARRYING CASH")
	return "     ".join(parts)

## The big centred message between rounds, or empty while play is on.
static func headline(world: SimWorld, level: GreyBoxLevel, can_rematch: bool) -> String:
	match world.match_phase:
		SimWorld.MatchPhase.COUNTDOWN:
			return "ROUND %d\n%.0f" % [world.round_number,
				ceilf(SimWorld.ticks_to_seconds(world.phase_ticks_remaining))]
		SimWorld.MatchPhase.ROUND_END:
			if world.round_winner == &"":
				return "ROUND %d DRAWN - replayed" % world.round_number
			return "%s WINS ROUND %d" % [_name(level, world.round_winner), world.round_number]
		SimWorld.MatchPhase.MATCH_END:
			var way_on: String = "[Enter] play again    [F10] menu" if can_rematch \
				else "waiting for the host    [F10] menu"
			return "%s WINS THE MATCH  %s\n%s" % [
				_name(level, world.match_winner), _rounds(world, level), way_on]
	return ""

static func _clock(world: SimWorld) -> String:
	if world.match_phase != SimWorld.MatchPhase.PLAYING:
		return "--:--"
	var seconds: int = ceili(SimWorld.ticks_to_seconds(world.phase_ticks_remaining))
	return "%d:%02d" % [seconds / 60, seconds % 60]

static func _rounds(world: SimWorld, level: GreyBoxLevel) -> String:
	var wins: PackedStringArray = PackedStringArray()
	for team: TeamDef in level.teams:
		wins.append(str(world.round_wins_for(team.id)))
	return "-".join(wins)

static func _name(level: GreyBoxLevel, team_id: StringName) -> String:
	for team: TeamDef in level.teams:
		if team.id == team_id:
			return team.display_name.to_upper()
	return String(team_id).to_upper()
