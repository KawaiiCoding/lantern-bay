# Lantern Bay — Game Design Document (MVP)

Studio rule: no emojis anywhere (UI, data, code strings). Tone: warm, a little dry, for adults (25-40), men and women alike. Never childish, never punishing.

## 1. Pitch
Mocha, a bear in his early thirties, burnt out from city life, moves to **Lantern Bay**, a tiny island town whose lanterns have gone dark. No quests shouting at you: you fish, befriend the island's cats, comb the shore, help neighbours, and the bay slowly lights back up. A small 3D world you can hold in one hand, in the soft toy style of Tsuki's Odyssey. Sessions of 3-20 minutes. Play forever.

## 2. Pillars
1. **Calm with a pulse.** Relaxing, but every minute has a small "ooh" (a big shadow in the water, a rare cat, a gold shell).
2. **Notice to win.** Knowledge is the power-up. The world runs on rules (time, weather, tide, cat schedules); players who observe get rare things. That is the "I hacked it" feeling.
3. **Collect things with personality.** Every cat has a name and a schedule, every fish has a size record, every rare thing feels earned.
4. **Always something tomorrow.** Daily requests, daily shore respawn, weather, records to beat. Nothing decays, nothing is lost by skipping a day.

## 3. Controls (portrait phone, also keyboard for dev)
- **Move:** drag anywhere on the left 60% of the screen = virtual joystick (WASD / arrows on desktop). Small push = sneak walk (quiet), full push = walk.
- **Action button** (bottom right, big round): shows the context verb of the nearest thing: Pet, Sit, Fish, Pick up, Talk, Shop. (E / Space)
- **Ride button** (above action): hop on / off the moped (R). Riding = 2.2x speed, but loud: cats within 4 m get nervous.
- **Notebook button** (top right): Cats, Fish, Shore, Requests, Bag. (Tab)
- Camera: fixed 3/4 follow camera, soft lag, never needs touching.

## 4. Time, weather, tide
- One island day = **12 real minutes** (06:00 to 24:00 plays, 00:00-06:00 fast-forwards at home or plays at 3x outside). Clock shown top bar.
- Weather per day (seeded by day index): Sunny 50%, Cloudy 25%, Rain 20%, Fog 5%. Shown in top bar.
- Tide: low tide 06:00-09:00 and 18:00-21:00. Low tide reveals the **tide flats** (extra shore items, a rare shell table).
- Time pauses while the Notebook or a shop is open.

## 5. Activities

### 5.1 Fishing (skill + collection)
- Fishing spots: pier end, rocks by the lighthouse, beach. Action "Fish" at a spot.
- **Cast:** tap Action. A bobber lands.
- **Wait:** 2-8 s. A fish shadow (size hints at size) circles in. It **nibbles** 0-3 times (bobber dips small, sound "plip"). Tapping on a nibble = fish flees ("Too eager.").
- **Bite:** bobber dives hard, big splash + haptic. Tap within **0.7 s** (rare fish: 0.5 s). Miss = "It got away."
- **Reel:** tension meter. Hold Action to reel (progress up, tension up). The fish **surges** at random (tension spikes); release to let tension fall. Tension at 100% = line snaps. Progress 100% = caught. 4-9 s total. Bigger fish surge more.
- **Catch card:** big 3D fish turntable, name, size in cm, "New record!" if bigger than best. Rarity stars.
- Fish table: 16 species in MVP. Each: spots, hours, weather, size range, rarity, sell price. Size rolls on a curve; record tracking per species makes it infinite. 1% **Gold** variant of any species (shiny), sells x5.
- Rain: big fish +50% weight. Night: some species only.

### 5.2 Cats (befriend, the heart of the collection)
- 10 named cats in MVP, each with: look (base colour, patch colour, pattern), personality (Shy, Bold, Lazy, Curious, Grumpy), haunts by time slot (morning / afternoon / evening / night) and weather, favourite treat (a fish species or a shop treat), and one **secret** (e.g. "Only comes out when it rains", "Follows anyone carrying a mackerel").
- Trust 0-5 hearts, saved.
  - Approach: riding within 4 m or full-speed walking within 2 m makes Shy/Grumpy cats run 6 m away (Bold cats don't care). Sneak walk is fine.
  - **Pet** (Action within 1.5 m): +1 heart once per day per cat (Shy cats need trust >= 1 first, earned by Sit).
  - **Sit** (Action when near but not yet pettable): Mocha sits; every 6 s nearby a cat may wander closer; first sit of the day with that cat: +1 heart.
  - **Treat:** if the bag contains its favourite, Action offers it: +2 hearts (once per day). Wrong treat: it sniffs and walks off (no penalty, a hint line).
- 5 hearts = **Friend**: Notebook page fills in, the cat sometimes visits Mocha's porch, and each morning a friend cat may leave a **gift** at the porch (shore item or coins).
- Notebook page reveals facts as you observe them (haunts, favourite, secret) so players learn by noticing. Unknown cats show a silhouette and one rumour line.

### 5.3 Shore combing (relaxing collection)
- Each morning (06:00) 14 shore items spawn on beaches; low tide adds 6 on the tide flats.
- Items: shells (common/uncommon/rare), sea glass (colours), driftwood, star stone (rare), message bottle (very rare: contains a short story note + 100 coins).
- Pick up: walk near, Action. Little pop + sparkle. Gold shell 2%.
- Shore page in Notebook: count found per type, firsts highlighted.

### 5.4 Town: Pip's shop and the Request Board
- **Pip's General Store** (Action at the counter): sell fish/shore items, buy cat treats (Tuna Bites, Catnip Sprig, Cream Cup), rod upgrades (Rod Lv2: +0.15 s bite window, gentler surges; Lv3: rare spot bonus), and cosmetics (Mocha's scarf colours, a cap, moped paint).
- **Request Board** by the shop: 3 requests per day, procedural from templates ("Maple wants any fish over 40 cm", "Cotton needs 3 sea glass", "Pip will buy a Gold anything for 300"). Reward coins + a lantern spark. New requests each morning; unfinished ones simply roll over (max 3).

### 5.5 Lanterns (long-term progression)
- 5 lanterns around the island. Each needs **Sparks** (earned by: new catalog entries, friend cats, completed requests, new records).
- MVP lanterns: 1) Harbour lantern (10 sparks) unlocks the lighthouse rocks fishing spot and its fish. 2) Hill lantern (25 sparks) unlocks the hill path, 2 more cats, and the night market stall (buys rare items at +50%).
- Lighting a lantern: short camera moment, warm light spreads, toast line.

## 6. Economy (target pacing)
- First session (10 min): ~3 fish (~60 coins), 8 shore items (~40), first heart with 2 cats, 1 request done.
- Rod Lv2 costs 400 (reachable day 2-3). Treats 25-60. Cosmetics 150-800. Lantern 1 by ~day 2, Lantern 2 by ~day 5.
- Sell prices: common fish 15-30, uncommon 40-80, rare 150-400; shells 3-10, rare shells 60, star stone 200.

## 7. "I noticed it" secrets (designed, never explained)
1. Carrying a Mackerel makes Biscuit follow you anywhere (and leads you to the hidden cove).
2. Rain pulls big fish to the beach: biggest-size records happen in rain.
3. Low tide reveals the tide flats with the rare Moon Shell.
4. Sitting still at the pier at night attracts Lantern Fish (only when the Harbour lantern is lit).
5. Grumpy cat Marmalade only accepts a treat if you have petted every other cat today.
6. Fog days: the Ghost Koi appears at the lighthouse rocks.

## 8. Feel & juice
Every action: a sound, a squash-stretch on the thing touched, a small particle burst. Camera eases. Toasts are short, dry and kind ("Pip says that is a suspiciously large fish.").

## 9. Save
Autosave to user://save.json every 30 s and after any catch/befriend/purchase. Load on start. Includes day, minute, coins, bag, records, cat trust + facts known, shore counts, requests, lanterns, rod level, cosmetics.

## 10. Architecture (contracts for the team)
- Autoloads: `GameState` (state + signals + save), `Data` (content tables), `InputBridge` (move vector + action signals from touch and keyboard).
- `Toys` (class_name, static): soft toy mesh builders, materials with ink outline, characters (bear, cat, fish), props.
- `Island` (world/island.gd): builds terrain with collisions and exposes named spots: `Island.spot(name) -> Vector3`.
- `SkyCycle` (world/sky_cycle.gd): time-of-day sun, sky, lanterns light.
- `Player` (player/player.gd): CharacterBody3D, camera rig, moped mount, interaction finder.
- Interactables: any Node3D in group `"interactable"` implementing `get_prompt(player) -> String` (empty = not available), `interact(player) -> void`, and var `interact_radius: float`.
- Systems (systems/*.gd, Node children of Main): `Cats`, `Fishing`, `Shore`, `Town` (shop + board), `Lanterns`.
- UI (ui/*.gd): `Hud` CanvasLayer (top bar, joystick, buttons, toasts), `Notebook`, `ShopPanel`, `FishingUI`, `CatchCard`. Style constants in ui/style.gd.
