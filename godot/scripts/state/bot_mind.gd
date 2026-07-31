class_name BotMind
extends RefCounted
## Ported from server/src/rooms/GameRoom.ts BotMind. Server-side-only bot
## decision state - never part of networked/replicated state. Empty string
## stands in for TypeScript's `null`/`""` on task/via/patrol_node.

var task: String = "" # "" | "rescue" | "defend" | "deposit" | "raid" | "patrol"
var target_id: String = "" # player id (rescue/defend) or bundle id (raid)
var via: String = "" # pending route waypoint BotNodeId, "" for none
var next_decide_at: float = 0.0 # sim clock ms of the next scheduled re-score
var last_seen_home_at: float = 0.0 # defend: last tick the target was inside our home turf
var patrol_node: String = ""
var patrol_until: float = 0.0
var zeal: float = 0.5 # 0..1 fixed per bot - scales defend value & pile-on willingness
