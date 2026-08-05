# Design direction

Why this game is shaped the way it is. `ARCHITECTURE.md` says how it is built;
this says what it is trying to be, and which questions are already settled.

Read it before proposing gameplay changes. Most of what looks like an obvious
improvement here has already been argued once.

---

## 1. What it is

A chaotic multiplayer party game for Steam. Two families raid each other's
houses for cash. 2v2 to 4v4, best of three, online with friends.

The measure of success is **whether friends keep coming back to it**, and the
distribution mechanism is short clips people send each other. Everything below
serves that.

## 2. Why the first version was boring

Worth understanding, because the failure is easy to rebuild.

Both teams raided simultaneously in opposite directions, so the traffic pattern
was two parallel footraces that never intersected. Encounters were coincidences
of routing rather than something the design forced.

There was also **exactly one decision** — which way to run — and it had a right
answer, so it stopped being a decision. And defending was a punishment: standing
in your own bedroom waiting is the worst job in the game, so nobody did it, so
the encounters never happened.

Better visuals fix none of that. A prettier corridor nobody is contesting is
still nobody contesting a corridor.

**The recurring lesson:** every time this game has felt dead, the cause was
players not meeting, or meeting somewhere nothing could happen. Check that
before anything else.

## 3. Principles

**Uniform rules, never curated lists.** If a behaviour could be a general
predicate or a hand-placed list, it must be the predicate. "Anything above this
height is climbable" produces routes nobody designed; twelve placed ladders
produce twelve routes and a game solved in a week. Each special case looks
reasonable alone, which is exactly why this has to be written down.

**Ambiguity is verbs × space.** A rich map with five verbs is not ambiguous. The
strategy space is the product of where you can be and what you can do, so a small
set of general verbs multiplies against every room. Prefer a new general verb
over a new special place.

**A uniform rule needs a uniform visual language.** If some waist-high things are
climbable and others are not, nobody trusts the rule and nobody experiments. The
threshold set in `WORLD_AUTHORING.md` §12 is binding on the art, not just the
collision.

**Failure should be funnier than success.** Losing has to be entertaining or
there are no clips.

**Never put the safest place on the busiest route.** The one that has already
bitten: the neutral strip between the houses was both the crossroads and the
only place capture was illegal, so every encounter happened where nothing could
come of it. Whenever a rule says *nothing can happen here*, check whether that
place is also on everyone's shortest path.

## 4. Settled decisions

Do not reopen these without new evidence.

| Decision | Value | Why |
|---|---|---|
| Safe room | Variant B — 5 s shelter on entry | Chosen to build against; A stays one `.tres` edit away |
| Jail sentence | 18 s, +6 s per repeat in a round | 60 s was near-elimination in a 2-minute round; rescue is the real release |
| Carry speed | No penalty (multiplier 1.0) | Field kept so it can be dialled without code |
| Bots | Opt-in, symmetric fill, never displace a human | A bot must never be why someone cannot get in |
| Bot behaviour | All weights in `BotProfileDef` | Difficulty is content |
| Houses | Mirrored | Asymmetric is later content, not worth the balance cost now |
| Camera | Third person, mouse-look, spring arm | Hiding and peeking need look-independent-of-movement |
| Routes into a room | Hard floor 2, aspiration 3 | One approach means a defender stands still and the round stops |

## 5. Verbs

Built: move, grab, drop, seize, free.

Planned, in rough priority. All must be general — none may be gated by location.

- **Throw.** The highest-value verb not yet built. Creates teamwork with no
  coordination system (chuck the cash over the fence), creates risk, and is the
  most clippable thing on the list. It also replaces any need for bespoke
  cash-moving contraptions — a dumbwaiter was cut for exactly this reason.
- **Crouch.** Slower, quieter, fits low gaps, harder to spot. One verb, four
  consequences.
- **Vault / climb.** Any ledge under the threshold. Not placed ladders.
- **Slide.** Fast, loud, low. Combines with crouch gaps and with knocking people
  over.
- **Drop from height.** One-way, instant. The escape valve that makes committing
  to an upstairs vault survivable.

Design constraint for any ability system: **low precision, high consequence.**
Nothing that rewards aim. Party games break when they reward mechanical skill.

## 6. Loot

Currently uniform cash bundles. The intended direction is loot with physical
character — a television that needs two people and blocks the carrier's view, a
piggy bank that is quick but jingles, a bundle that is the balanced option.

That gives push-your-luck decisions, forced coordination, and the single most
clippable image available: two players posting a television out of an upstairs
window.

Cash already drops where the carrier was caught, not back in its room. That is
deliberate — it turns a footrace into a scramble.

## 7. Distribution

The features that actually spread a game of this kind, in order of value:

1. **Proximity voice chat.** In a hide-and-seek game set in a house this is not a
   feature, it is the experience. Hearing footsteps overhead while a friend
   whisper-panics next to you *is* the game. It also integrates with any noise
   model: your real voice makes you findable.
2. **Player-supplied faces.** A friend's actual face on a ragdolling body is
   inherently shareable. Cheap because appearance never reaches the simulation —
   keep such assets peer-shared within a lobby rather than uploaded, which keeps
   a shipping title clear of content moderation it need not incur.
3. **Clip export.** A deterministic simulation means a match is a seed plus an
   input log — kilobytes. Highlight export is therefore a rendering problem, not
   a simulation one. Protect that property deliberately.
4. **Ragdoll collisions.** Party-game chaos comes from losing control of your
   body.

## 8. Open questions

- Does capture need lag compensation? Deliberately not built; waiting on a real
  two-machine playtest to say whether it is needed.
- Is the encounter rate right? Sentences and round length imply a healthy band of
  roughly 4–8 captures per round for four players. Currently well below that.
- Does the stair bay work as fighting ground, and do one-way light wells read as
  commitment or as a trap? Neither has been played.
- Should defenders get a preparation phase (traps, locks, alarms) so that
  defending is expressive rather than waiting? Unexplored, and the standing
  answer to "defending is boring".
