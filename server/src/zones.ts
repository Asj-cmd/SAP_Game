// The server's view of the world geometry. The geometry itself is defined ONCE
// in shared/worldGeometry.ts and re-exported here, so the authoritative server
// and the renderer can never disagree about where a wall is - they read the same
// numbers instead of two hand-synced copies (which drifted and caused real bugs).
//
// Keep this a pure re-export: server-specific logic belongs in rooms/GameRoom.ts.
export * from "../../shared/worldGeometry";
