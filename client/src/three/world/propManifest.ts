// The renderer's view of the house/garden dressing.
//
// The placements themselves live in shared/props.ts, for the same reason the
// walls live in shared/worldGeometry.ts: furniture is SOLID now, so the
// authoritative server has to path its bots around the same sofa the human
// can't walk through. One copy, re-exported here so the render code keeps
// importing from the module next to it.
export * from "../../../../shared/props";
