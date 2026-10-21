# Architecture — long versions

The long version of every entry in `CLAUDE.md`'s *Architecture map* and *Code layout*, moved there verbatim on 2026-10-20. `CLAUDE.md` holds each entry's rule and points at its section here. **Before editing code in an area, read its file.**

| File | Sections |
|---|---|
| [`squads.md`](squads.md) | *SquadManager* · *Squad* · *The squads/ folder: SquadPlanValidator, SquadCohesion, GroupMoveSolver* |
| [`board.md`](board.md) | *game.gd* · *OverlayManager* · *The board/ folder: BoardGrid, BoardContext, rules, ZoneManager, HoverPresenter* |
| [`units-and-saves.md`](units-and-saves.md) | *The persistence seam* · *A save is a mid-battle snapshot* · *Carry-over between missions, and player save slots* · *The units/ folder* |
| [`pre-mission.md`](pre-mission.md) | *The pre-mission phase* |
| [`actions.md`](actions.md) | *Actions are a small in-code registry* · *The ring's verbs* · *Execution order* · *The actions/ folder* |
| [`targeting.md`](targeting.md) | *Reach* · *Targeting modes* |
| [`weapons-and-items.md`](weapons-and-items.md) | *Weapons are template + instance, and the attack is its own content* · *The weapons/ folder* · *The items/ folder* · *The alchemy/ folder* · *The jobs/ folder* · *The elemental/ folder and Conduction* |
| [`flow-and-missions.md`](flow-and-missions.md) | *TurnManager* · *ScenarioDirector* · *Authoring a Dialogic timeline* · *Missions — the closed loop* · *The flow/ folder* |
| [`ai.md`](ai.md) | *Archetype AI* · *The ai/ folder: the threat field and enemy ranges* |
| [`presentation.md`](presentation.md) | *Scenes/LookDev/ is load-bearing* · *ArcLightning* · *Gas* · *Weather* · *A unit wears its element state* · *A unit sprite can play frames* |
| [`dev-tools.md`](dev-tools.md) | *The dev-tools window and its pages* · *The Tiles tab* · *The Game tab* · *The dev/ folder and the content lints* |
| [`reports.md`](reports.md) | *BugReporter* · *Kind: BUG or FEEDBACK* · *BugReporter.open_card is the one funnel for a card* · *The screenshot comes from the root viewport* · *The dev-tools window is a second file* · *capture_frame() returns null in a headless run* · *Report-flow tests* |
| [`ui.md`](ui.md) | *ModalLock* · *ModalCard* · *UiLayers* · *The ui/ folder* |
| [`camera.md`](camera.md) | *The camera's vocabulary has one home* · *CameraTrace: what the camera just did* · *ShotDirector: the camera's shots are a priority table* |
| [`core.md`](core.md) | *Registries* · *The core/ folder: Glossary, Pacing, PlayerSettings, Controls* |
| [`audio.md`](audio.md) | *AudioDirector* · *MusicDirector* |
| [`net-and-telemetry.md`](net-and-telemetry.md) | *The net/ folder* · *The telemetry/ folder* |

The same long-form treatment covers the rest of `CLAUDE.md`: [`../workflow.md`](../workflow.md) (the collaboration contract, the GitHub workflow, branches and versions, content and docs discipline) and [`../sharp-edges.md`](../sharp-edges.md). Pure history lives in [`../build-log.md`](../build-log.md).
