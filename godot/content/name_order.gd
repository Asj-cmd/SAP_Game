class_name NameOrder
extends RefCounted
## The one place StringNames get put in order.
##
## `Array[StringName].sort()` does not compare by characters. It compares
## interning identity, so three names interned out of alphabetical order come
## back in neither alphabetical nor insertion order, and WHICH order depends on
## what the process happened to intern first. Two machines running the same
## build can disagree.
##
## That is not cosmetic anywhere it appears. Team order decides the sequence
## bodies are created in and therefore which entity id each actor is given; zone
## order decides which room wins where bounds overlap; the baker's order decides
## what a level file looks like on disk. All three are things two machines must
## agree on exactly.
##
## It was found twice by luck - once in zone resolution by someone who knew, and
## once in teams by chasing a desync - which is the reason it is centralised
## rather than patched a third time. tests/ordering_test.gd fails the build if a
## raw .sort() on a StringName collection reappears in sim/, content/ or the
## baker.
##
## Lives in content/ because it is the bottom layer: sim/, game/ and tools/ can
## all reach down to it (§1).

## Ordering used everywhere a StringName sequence must be stable. Compares the
## TEXT, which is the only property of a name that is the same on every machine.
static func compare(a: StringName, b: StringName) -> bool:
	return String(a) < String(b)

## A sorted copy. Never sorts in place: the caller's array is very often a
## dictionary's keys, and reordering those under the dictionary is a surprise
## nobody needs.
static func sorted_string_names(names: Array[StringName]) -> Array[StringName]:
	var ordered: Array[StringName] = names.duplicate()
	ordered.sort_custom(func(a: StringName, b: StringName) -> bool: return compare(a, b))
	return ordered
