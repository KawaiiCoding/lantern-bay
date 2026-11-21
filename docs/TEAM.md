# Team contracts (read before coding)

Godot 4.7, GDScript (typed where easy), everything built in code (no hand-made .tscn besides main.tscn). Portrait 540x960. Read docs/GDD.md first.

## Hard rules
- **No emojis anywhere.** Plain text only in UI and data.
- **Only edit files you own** (listed in your task). If you need something from another file, use the contracts below; if a contract is missing, add a tiny, safe fallback in your own file and mention it in your report.
- Art: use `Toys` (scripts/art/toys.gd, static) for meshes/materials so everything shares the soft toy + ink-outline look. Add new builders in your own files (static funcs are fine there). Only the World owner edits toys.gd.
- Check your work: `godot --headless --path /Users/hm/Desktop/files/dev/lantern-bay --quit-after 120 2>&1 | grep -E "ERROR|SCRIPT ERROR|Parse Error"` must show nothing from your files.
- See it: `godot --path /Users/hm/Desktop/files/dev/lantern-bay -- shot=/tmp/lb_<you>.png wait=3` saves a screenshot and quits (opens a window briefly). Add `fresh=1` to start from a clean save. Look at the PNG and iterate until it looks good.
- Systems may self-test by adding temporary code paths behind a user arg (e.g. `-- test=fishing`), read in your own file from `OS.get_cmdline_user_args()`; keep them, they help QA.

## Autoloads (scripts/core, owned by lead)
- `GameState`: day, minute, clock_text(), time_slot(), weather(), low_tide(), day_rng(salt), coins/add_coins/spend, bag/add_item/has_item/remove_item, fish_log, cats/cat_state(id)/learn_cat_fact, shore_log, requests, lanterns, sparks/add_sparks(n, why), rod_level, cosmetics, flags, say(text) -> toast, set_paused(bool), save_game(). Signals: time_changed, new_day, coins_changed, bag_changed, catalog_changed, sparks_changed, toast, paused_changed.
- `Data`: FISH, CATS, SHORE, SHOP, ROD, REQUEST_TEMPLATES, LANTERNS, SPARK, constants.
- `InputBridge`: move (Vector2), touch_move (HUD writes), action_held, press()/release(), signals action_pressed/action_released/ride_pressed/notebook_pressed.

## Main (scripts/main.gd)
Instantiates parts in order: sky, island, player, cats, fishing, shore, town, lanterns, hud. Then calls `setup(main)` on each. `main.island`, `main.player`, `main.hud`, `main.sky`, `main.systems["cats"]`, `main.spot(name)`.

## Island (scripts/world/island.gd, Node3D)
- `spot(name: String) -> Vector3` ground positions. Names: home, porch, plaza, shop, shop_counter, board, pier, pier_end, beach, rocks, lighthouse, hill, flats, lantern_harbour, lantern_hill, spawn.
- `ground_y(x: float, z: float) -> float`
- `random_beach_point(rng) -> Vector3`, `random_flats_point(rng) -> Vector3`
- `is_walkable(p: Vector3) -> bool`
- Builds terrain with StaticBody3D collisions (player is a CharacterBody3D, layer 1). Hill area blocked by a gate until `GameState.lanterns.has("hill")`; rocks blocked until "harbour" (call `island.refresh_unlocks()` after a lantern lights).

## SkyCycle (scripts/world/sky_cycle.gd)
Owns WorldEnvironment + sun. Updates light/sky colours from GameState time and weather (rain/fog visuals). `sky.is_night() -> bool`.

## Player (scripts/player/player.gd, CharacterBody3D)
- Builds Mocha (Toys.bear) + moped, a follow Camera3D (fixed 3/4 angle, soft lag, tilt-shift DOF).
- Properties: `riding: bool`, `sitting: bool`, `busy: bool` (movement locked, e.g. fishing).
- `speed_ratio() -> float` 0..1 of max walk speed (riding returns 1.0 + `riding` flag), `noise_level() -> float` (0 quiet sneak, 0.5 walk, 1.0 full run, 1.5 riding).
- `set_busy(b: bool)`, `sit(on: bool)`, `face(target: Vector3)`.
- `carrying(item_id: String) -> bool` (GameState.has_item shortcut).
- Interaction: each frame finds the nearest node in group "interactable" within its `interact_radius` whose `get_prompt(player)` is not "", and calls `main.hud.set_action(prompt)` (or "" for none). On InputBridge.action_pressed (when not busy) calls `interact(player)` on it. Ride: InputBridge.ride_pressed toggles riding (not while busy/sitting).
- Signal `moved_far` not needed; systems read player.global_position.

## Interactable contract
Any Node3D in group "interactable" with `var interact_radius: float`, `func get_prompt(player) -> String` ("" = unavailable) and `func interact(player) -> void`. Optional `var interact_priority: int` (higher wins ties).

## Hud (scripts/ui/hud.gd, CanvasLayer layer 10)
- Top bar (place name, clock, weather word, coins), toasts (from GameState.toast), virtual joystick (writes InputBridge.touch_move; left 60% of screen), big Action button showing the current prompt (hidden when ""), Ride button, Notebook button.
- `set_action(text: String)`, `set_place(text: String)`, `set_controls_visible(b: bool)`.
- `open_panel(c: Control)` shows a modal panel centered with dim backdrop and pauses time; `close_panel()`.
- `Style` helpers in scripts/ui/style.gd (class_name Style): colours, `panel_box()`, `button()`, `label()`. Other UIs (fishing, shop) should use Style.
- Notebook (scripts/ui/notebook.gd): tabs Cats, Fish, Shore, Requests, Bag reading GameState + Data.

## Systems
- Cats (scripts/systems/cats.gd): spawns cat nodes (interactable) per schedule; trust rules per GDD 5.2.
- Fishing (scripts/systems/fishing.gd + scripts/ui/fishing_ui.gd): fishing spot interactables + minigame + catch card.
- Shore (scripts/systems/shore.gd), Town (scripts/systems/town.gd + scripts/ui/shop_panel.gd), Lanterns (scripts/systems/lanterns.gd).

## Townsfolk (added)
- State: `GameState.person_state(id)`, `person_level(id)` (0..10), `add_friendship(id, points, why)`, `has_perk(id, perk)`, signal `people_changed`.
- Content: `Data.PEOPLE` (design director) and `Data.PEOPLE_LEVELS` (points thresholds). Each person: name, species/look, role, home spot, routine by time slot, likes/loves/dislikes (bag item ids), perks by level, request themes, dialogue lines.
- System: scripts/systems/people.gd (People team). Exposes on main.systems["people"]: `talk(id)`, `give(id, item_id)`, `perk_value(perk: String, default)` (e.g. shop discount), `person_at(spot)`.
- Town: Pip is a person (id "pip"); the shop applies `people.perk_value("shop_discount", 0.0)`. Requests carry `who` = person id; completing one calls `GameState.add_friendship(who, points)`.
- Notebook gets a "People" tab (UI team).

## Quality bar (owner, binding)
- **No bugs, working mechanics.** Guard every lookup (`.get()` with defaults, `is_instance_valid`, null checks on main.island/player/hud/systems). Never assume another part exists. No softlocks: every modal/panel must be closable, `player.set_busy(true)` must always be paired with `set_busy(false)` on every exit path (cancel, finish, error, scene change).
- **Saving is automatic.** Never ask the player to save. After any meaningful change (catch, pickup, purchase, friendship, lantern, request) call `GameState.save_soon()`. Only store plain data (Dictionary/Array/String/int/float/bool) in GameState so JSON round-trips; ints come back as floats from JSON, so cast with int().
- **UI must feel nice.** Touch targets at least 88 px tall, clear pressed/disabled states, squish on press, consistent Style, no text overflow at 540 px width, every button gives sound-free visual feedback within one frame.
- **Self-test.** Keep your `-- test=<name>` path and make sure it exercises the full loop (start, success, failure, cancel) without errors in the log.
