# Start here

**CLAUDE-AUTHORED, unreviewed.** A one-page way into this folder, written after the twelfth board.
Everything below is my read of my own work; none of it has been seen in the windowed game.

## The twelve boards

| Board | Size | Win | In one line | How sure I am |
|---|---|---|---|---|
| [The Lime Kiln](TheLimeKiln.md) | 14 x 12 | Rout | slake quicklime into steam, then shock the soaked | good; five layouts to get there |
| [Chaff](Chaff.md) | 22 x 13 | Extract, 12 rounds | burning heaps and smoke against a hunting squad | fair; won on the last round |
| [Meltwater](Meltwater.md) | 22 x 16 | Capture | ice over deep water is the road and the trap | good |
| [The Glass Walk](TheGlassWalk.md) | 13 x 7 | Rout, 10 rounds | a vein and fused sand as stepping stones for a Zap | good; smallest board |
| [Cinder Row](CinderRow.md) | 24 x 16 | Extract with an escort, 14 rounds | hold or hurry three fires with time marks | fair; tight clock |
| [The Salt Stair](TheSaltStair.md) | 14 x 17 | Capture | a shove into a hole is a death, yours or theirs | good |
| [The Lodes](TheLodes.md) | 30 x 18 | Capture three | every keeper is nothing off his vein | fair; sixteen rounds, some of it waiting |
| [Stormgate](Stormgate.md) | 20 x 16 | Rout, hold a gate | rain makes every body a conductor | **swingy**; lost three times before the win |
| [The Drowned Orchard](TheDrownedOrchard.md) | 20 x 13 | Rout, 24 rounds | the weather is drawn; read the sky, then pack | **weak last third**; the final-build win cost three of five |
| [The Saps](TheSaps.md) | 14 x 14 | Capture then Extract, 14 rounds | trenches decide how many can reach you | good, on one run |
| [The Long Dark](TheLongDark.md) | 38 x 24 | Extract, 26 rounds | two roads, two set pieces on each | fair; long walks |
| [The Marshal's Charge](TheMarshalsCharge.md) | 18 x 12 | Rout, an allied VIP must live | an escort you cannot steer | fair, on one run |

**If you play three,** play The Saps (shortest way to see what corridors do), Meltwater (the ice
does everything the note says) and The Marshal's Charge (five rounds, and you will know at once
whether an AI escort is fun). **If you play one to find out what is wrong,** play Stormgate.

## What I would look at as bugs

The full list, with how to see each again, is in [bugs.md](bugs.md). The ones I think are real:

1. **B2: a Rushdown squad stretched round a one-tile gap never advances.** It sat for three turns.
2. **B3: a Heal on a downed unit leaves a body that never bleeds out** and blocks its tile until
   killed again.
3. **B1: a unit that starts a mission standing in shallow water is never Wet**; one that walks
   through the same water is.
4. **S31: Overwatch fires at a downed body**, and at whatever already stands in the lane the
   moment it is set.
5. **S20: an AI caster's shock hits its own squad and can down the caster.** One mission ended
   that way.
6. **S2 and S25, together: a posted squad stands in fire until it dies, unless a player unit comes
   in reach, and then all of it walks through the fire.**

## What kept coming back on the wish list

[wishlist.md](wishlist.md) has about fifty entries. Five ideas account for most of them:

- **A wall.** Raised earth, in eight of the twelve notes. Each of those names the tiles. The Fire Wall
  rune is not a substitute: the AI walks through fire (bugs.md, S32).
- **Something that dries or douses.** Rain, shallows and steam make everyone a conductor and
  nothing undoes it.
- **Weather that touches the ground.** Rain does not damp a fire; snow does not freeze a shallow.
- **A word to an ally, and a watch that can be told what to wait for.**
- **A way to carry the wounded.** Three boards ended with rounds of walking at two tiles a turn.

## What I got wrong, so you can discount for it

- **I had units downed or killed by attacks I did not preview,** on at least four boards. The previews
  were right every time. Where a note says a fight was costly, check whether the cost was the
  board or me.
- **Every board was played by someone who knew its answer.** The "blunt" baseline is the game's own
  AI on the player's side, which is a floor and not a first-time player.
- **Rounds of nothing.** The Lodes, The Drowned Orchard and The Long Dark each have a stretch where
  the right play is to end the turn. I flagged it in each note and did not fix it.
- **I never saw any of it.** Looks, camera, readability of a rock corridor or a 38-tile board:
  unknown.
