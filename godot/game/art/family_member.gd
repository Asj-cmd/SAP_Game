class_name FamilyMember
extends Resource
## One member of the family as it is DRAWN (STYLE.md §2.2; PLAN P2-1): which
## baked body, how tall, and its own "slightly off" nudge. Both families are the
## same family (D2/D3), so a member is chosen by roster slot, never by team,
## except where the theme's kid swap (D3 d, P2-4) says otherwise.
##
## Presentation only: the simulation body is the same 180-tall body for every
## member, and nothing here is read by a rule.

## "dad", "mom", "elder_girl", "elder_boy", "younger_girl", "younger_boy".
@export var id: StringName = &""
## The baked figure (`autobuild/figure_bake.mjs`). Empty or missing falls back to
## the theme's `figure_model`, then the old per-team model, then the capsule.
@export var model: String = ""
## Drawn height in units, feet to crown, after the bone nudges (STYLE §2.2).
## Never above the theme's `figure_height` (the 180 sim body).
@export var height: float = 180.0
## This member's own nudge, multiplied onto the theme's shared
## `figure_bone_scales` bone by bone. A bone's scale carries to everything below
## it; its bone axis is +Y, so (1, s, 1) lengthens or shortens a limb.
@export var bone_scales: Dictionary[StringName, Vector3] = {}
