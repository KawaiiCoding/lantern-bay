# Lantern Bay — Game Design Document (MVP)

Studio rule: no emojis anywhere (UI, data, code strings). Tone: warm, a little dry, for adults (25-40), men and women alike. Never childish, never punishing. Money is **yen** (green paper notes, shown as "¥1,200"), never "coins". All content numbers live in `scripts/core/data.gd`; this document explains why they are what they are.

## 1. Pitch
Mocha, a fluffy Shiba Inu in his early thirties, burnt out from city life, moves to **Lantern Bay**, a tiny island town whose lanterns have gone dark. The island belongs to its cats, and the cats are not sure about the new dog. No quests shouting at you: you fish, earn the trust of the island's cats one patient sit at a time, comb the shore, get to know six neighbours with their own unfinished stories, and the bay slowly lights back up. A small 3D world you can hold in one hand, in the soft toy style of Tsuki's Odyssey. Sessions of 3-20 minutes. Play forever.

The comedy is light and constant: a dog trying very hard to be calm around cats. Cats side-eye him, Pip apologises for them, Mocha's tail gives him away when a big fish bites.

## 2. Pillars
1. **Calm with a pulse.** Relaxing, but every minute has a small "ooh" (a big shadow in the water, a rare cat, a gold shell, a neighbour finally telling you something true).
2. **Notice to win.** Knowledge is the power-up. The world runs on rules (time, weather, tide, cat schedules, neighbour routines); players who observe get rare things. That is the "I hacked it" feeling. Rules are hinted in dialogue and bottle notes, never in tutorials.
3. **Collect things with personality.** Every cat has a name and a schedule, every fish has a size record and a trophy size, every neighbour has a story, every rare thing feels earned.
4. **Always something tomorrow.** Daily requests, Pip's daily special, shore respawn, two low tides, weather, a line of dialogue you have not heard yet. Nothing decays, nothing is lost by skipping a day.
5. **Relationships pay off everywhere.** Each neighbour's perks improve a different activity, so every friendship changes how you play.

## 3. Controls (portrait phone, also keyboard for dev)
- **Move:** drag anywhere on the left 60% of the screen = virtual joystick (WASD / arrows on desktop). Small push = sneak walk (quiet, Mocha lowers his ears), full push = trot.
- **Action button** (bottom right, big round): shows the context verb of the nearest thing: Pet, Sit, Fish, Pick up, Talk, Give, Shop, Sleep. (E / Space)
- **Ride button** (above action): hop on / off the moped (R). Riding = 2.2x speed, but loud: shy cats within 4 m bolt.
- **Notebook button** (top right): Today, Cats, Fish, Shore, People, Requests, Bag. (Tab)
- Camera: fixed 3/4 follow camera, soft lag, never needs touching.

## 4. Time, weather, tide
- One island day = **12 real minutes** (06:00 to 24:00 plays; 00:00-06:00 plays at 3x outside). Action **Sleep** at home after 21:00 skips to 06:00. Time pauses while the Notebook, a shop or a dialogue is open.
- Slots: morning 05-11 (4 real min), afternoon 11-17 (4 min), evening 17-21 (2.7 min), night 21-05.
- Weather per day (seeded by day index): Sunny 45%, Cloudy 25%, Rain 22%, Fog 8% (`Data.WEATHER_ODDS`). Day 1 is always sunny. No fog before day 4. If 14 days pass without fog, the next day is fog (Wen's level 10 perk makes it 7). Fog days are events; the long-tail cat and fish depend on them, so their gap must be bounded.
- Forecast: on the evening before a fog day a low mist bank sits on the horizon from 18:00 (SkyCycle). With Wen's level 2 perk the Notebook shows tomorrow's weather.
- Tide: low tide 06:00-09:00 and 18:00-21:00. Each low tide reveals the **tide flats** and spawns a fresh set of flats items; leftovers wash away when the tide returns.

## 5. Activities

### 5.1 Fishing (skill + collection)
- Fishing spots (`Data.FISH_SPOTS`): pier end (`pier`), beach (`beach`), lighthouse rocks (`rocks`, needs the Harbour lantern), and the tide flats sandbar (`flats`, low tide only, needs Moss's level 8 perk). Action "Fish" at a spot.
- **Cast:** tap Action. A bobber lands.
- **Wait:** 2-8 s. A fish shadow circles in; **shadow size = real size** of the rolled fish. Tapping Action now reels in for free and recasts (`RECAST_FREE`): this is how record hunters skip small fish.
- **Nibbles:** 0-3 small dips ("plip"). Tapping on a nibble = fish flees ("Too eager.").
- **Bite:** bobber dives hard, big splash + haptic, Mocha's ears go up. Tap within the bite window: Rod 1 0.7 s, rare fish (rarity 3+) 0.2 s less, plus Moss's perks. Miss = "It got away."
- **Reel:** tension meter. Hold Action to reel (progress up, tension up). The fish **surges** at random (tension spikes); release to let tension fall. Tension at 100% = line snaps. 4-9 s, longer and surgier for bigger fish.
- **Catch card:** big 3D fish turntable, name, size in cm, rarity, "New record!" if bigger than best, "Trophy!" if size is in the top 10% of the species range, "Gold!" for gold.
- **Roll:** eligible species = matches spot, slot, weather, lantern, perk and tide. Weight = `RARITY_WEIGHT` (60/28/10/4) or the species' own `weight`; junk 8. Rod 3 and Moss's level 10 perk multiply rare (3+) weights. Moss's forecast fish gets x2 that day.
- **Size:** `min + (max-min) * pow(randf, 1.8)` (skews small, so big ones matter). In rain the curve is 1.2 and big species (max >= 45 cm) are 1.5x more likely. Sell price scales 0.7x-1.3x with size.
- 18 species + the Old Boot. 1% **Gold** of any species (x5 price).
- Coverage rule (checked): every spot has a catchable non-junk species at every slot and weather. Pier: sardine always. Beach: sardine, flounder, crab always. Rocks: rockfish and crab always. Flats: flounder always.
- Fishing buddy: Pepper comes to sit beside you when you fish at the pier (counts as that day's Sit with her).

### 5.2 Cats (befriend, the heart of the collection)
- 10 named cats, each with: look, personality (Shy, Bold, Lazy, Curious, Grumpy), haunts by time slot and weather, favourite (a fish or a shop treat), a signature Friend gift, and one **secret**.
- Cats and the dog: a new dog is suspicious. Unknown cats show a "?" over their heads and watch Mocha. That is the fiction for the patient trust mechanic; it should feel funny, never sad.
- Availability: 6 cats from day 1 (Biscuit, Tofu, Pancake, Mochi, Pepper, Saffron). Harbour lantern adds Disco (nights) and Fog (fog days). Hill lantern adds Marmalade and Admiral (Moss's cat).
- Trust 0-5 hearts, saved. At most **3 hearts per cat per day** (`CAT_DAILY_HEART_CAP`).
  - Approach: riding within 4 m or trotting within 2 m makes Shy/Grumpy cats run 6 m away; they walk back after 20 s. Sneak walk is always fine.
  - **Sit** (Action when near): Mocha sits. Every 6 s a nearby cat may step closer. First sit of the day with that cat: +1 heart.
  - **Pet** (Action within 1.5 m): +1 heart once per day per cat. Shy cats need 1 heart first.
  - **Treat:** if the bag holds its favourite, Action offers it: +2 hearts (once per day), works even on a shy cat at 0 hearts. Wrong treat: it sniffs and walks off, the item is kept, and a hint line is learned ("Tofu sniffs the sardine. Not a fish person, apparently.").
  - Result: Friend in 3 days without the right treat, 2 days with it. Fog needs two fog days (and a Ghost Koi), so it is a weeks-long goal by design.
- 5 hearts = **Friend** (+3 sparks): Notebook page fills in, and each morning each Friend has a 35% chance (max 2 per morning) to leave its signature gift, or a small folded yen note, on the porch.
- Notebook reveals facts as you observe them (haunts, favourite, secret). Unknown cats show a silhouette and a rumour. Maple's perks reveal haunts (level 2) and secret hints (level 10).

### 5.3 Shore combing (relaxing collection)
- Each morning 14 beach items spawn; each low tide 6 flats items spawn (12 with Fern's level 5 perk).
- Beach: white shell, pink scallop, green / blue / amber sea glass, driftwood, message bottle. Flats: sand dollar, razor shell, moon shell, star stone.
- Shells (white, pink, sand dollar, moon) roll **gold** at 2% (4% with Cotton's level 5 perk). A gold shell sells for ¥1,200 and satisfies Pip's gold request.
- **Message bottles** (about one every 3 days) each hold ¥800 and the next of 12 notes from Ines, the old lantern keeper. The notes carry her story and quietly hint at most secrets.
- Shore page in Notebook: count found per type, gold count, firsts highlighted.

### 5.4 Town: Pip's shop and the Request Board
- **Pip's General Store** (Action at the counter, any hour; at night you ring the bell): sell fish / shore / flowers, buy cat treats (Tuna Bites ¥200, Catnip ¥350, Cream ¥500), rods (Sturdy Rod ¥4,000; Lighthouse Rod ¥15,000 after the Lighthouse lamp), and cosmetics (scarves ¥1,500-1,800, caps ¥3,000, moped paints ¥6,500-12,000). Items with `hidden` are gifts from Cotton and never listed.
- **Pip's daily special:** one species already caught sells at x2 today (x2.5 with Pip level 3). Shown on the board. This rotates what is worth fishing for each day.
- **Request Board** by the shop: 3 requests, refilled each morning from `REQUEST_TEMPLATES`. Each has a `who` (a neighbour) and pays yen + 1 spark + 60 friendship with that neighbour.
  - Fish species requests only ask for species you have already caught (or a common one on day 1), rarity 2 at most. Achievable, never a dead end.
  - Size requests use small targets (25-40 cm) until the Harbour lantern, larger after. The fish is handed over on catch; junk never counts.
  - Shore requests ask for items from the template's list; items already in your bag count right away (that small instant win is intended).
  - Pip's gold request: at most one at a time, rare.
  - A request untouched for 3 mornings is replaced with a kind line ("Maple found one elsewhere. No hard feelings."). The board can never be clogged.
- **Night stall** on the hill (21:00-24:00, after the Hill lantern): buys rare fish, star stones, moon shells and gold items at x1.5.

### 5.5 Lanterns (long-term progression)
- Sparks come from: first catch of a species (+1), first find of a shore item (+1), first trophy of a species (+1), first gold of a species (+1), cat Friend (+3), request (+1, +2 for gold), neighbour reaching level 5 (+2) and level 10 (+3). New records still celebrate, but pay no spark (that would flood day 1).
- MVP lanterns (in order):
  1. **Harbour Lantern** (12 sparks, ~day 2): opens the lighthouse rocks and their fish, Lantern Fish at the pier at night, Disco and Fog.
  2. **Hill Lantern** (25 sparks, ~day 5): opens the hill path, Marmalade, Admiral, the night stall.
  3. **Lighthouse Lamp** (40 sparks, ~day 12): the beam turns again (Disco is visibly delighted), Lighthouse Rod and Harbour Night paint arrive at Pip's, Wen has a moment.
- Wen's map names five lanterns; the last two are Post-MVP. Sparks keep accruing after lamp 3 and are shown as "saved for the dark ones" so the update pays off instantly.
- Lighting a lantern: short camera moment, warm light spreads across the water, toast line, every neighbour has one new line about it.

### 5.6 Townsfolk (neighbours with stories and perks)
Six adults, three women and three men, each with a routine, tastes, a story told in four bands of dialogue, two story events and perks. Data: `Data.PEOPLE`, `PEOPLE_LEVELS`, `PEOPLE_POINTS`.

| Id | Who | Where (morning / afternoon / evening / night) | Story | Perks (level) |
|---|---|---|---|---|
| pip | Pip, raccoon, shopkeeper | counter all day / shop | Came back from the city for his grandmother's shop; has an offer to leave | 5/10/15% discount (2/5/8), special x2.5 (3), gold +20% (6), sell +5% (10) |
| maple | Maple, fox, painter | beach / plaza / pier / plaza | Ex-illustrator who will not paint faces | cat haunts in Notebook (2), cat portraits (5), cats startle at 60% range (7), secret hints (10) |
| cotton | Cotton, sheep, knitter | board / plaza / shop / plaza | Ex-banker; wants to open a tiny wool shop | free scarf (2), gold shells x2 (5), free scarf (7), bottles x2 (9), free beanie (10) |
| fern | Fern, frog, gardener | beach / board / plaza / board | Brother went north and stopped writing; a 40-year-old seed | daily Sea Pink (2), flats finds x2 (5), free catnip every 3 days (7), weekly Moonflower (10) |
| moss | Captain Moss, walrus, retired fisherman | pier end / beach / pier / pier | Widower, stopped fishing at dawn; Admiral's owner | bite window +0.05 (2), daily rare fish forecast x2 (5), bite window +0.1 (7), flats sandbar spot + Spotted Ray (8), rare fish +25% (10) |
| wen | Wen, heron, lighthouse keeper | shop / shop / lighthouse / lighthouse | Came to automate the lamp, never left; turned down an observatory | weather forecast (2), +1 spark per request (5), tide chart (7), fog at least weekly (10) |

- **Points** (once per day each): talk +20, give a loved item +80, liked +40, neutral +10, disliked -20; finishing their request +60 (any number per day). Flowers count as liked unless listed. A gift is offered via the Action button ("Give Moon Shell?") with the bag item picker.
- **Levels:** 30, 80, 150, 240, 350, 480, 640, 830, 1050, 1300 points. Talk alone reaches level 3 in a week; a player who gives liked gifts and does their requests reaches level 5 in about 1-2 weeks and level 10 in 4-6 weeks. Six neighbours make this a multi-week loop that runs in parallel with everything else.
- **Lines:** each daily talk shows an unseen line from the current band (0-2, 3-5, 6-8, 9-10). Lines slowly reveal the story; later bands reference what the player has done (lanterns, records) in general terms.
- **Events** at levels 4 and 8 play once on the next talk, some with a gift. They are the payoff moments and must use the dialogue panel, not a toast.
- **Perks** are announced in a dedicated card ("Moss fixed your grip. Bite window +0.05 s.") and listed on the person's People page, so the player always knows what a friendship did. They stack sensibly: same perk id upgrades (highest value wins).
- Neighbours never dislike Mocha and points never drop below 0. A disliked gift gets a dry, kind line ("Fern looks at the sea pink. 'I grew this.'").
- Hidden tastes are learned: the People page shows "Loves: ???" until you give it once.

## 6. Economy (target pacing, yen)
- Start: ¥500 and one Tuna Bites (Pip's welcome gift, which is Pancake's favourite: a guaranteed first +2 hearts).
- Fish: commons ¥120-240, uncommon ¥450-900, rare ¥1,500-3,000 (Ghost Koi ¥5,000). Shore: ¥25-110 common, amber glass ¥250, moon shell ¥400, star stone ¥1,500, gold shell ¥1,200, bottle ¥800 inside.
- Fishing cycle is about 20-25 s per fish, so pure grinding at the pier earns roughly ¥400-500 a minute early. That is allowed (adults choose their pace) but the daily special, requests and sparks reward variety more than grinding.
- **First session (10 min):** ~3 fish (~¥500), 8 shore items (~¥400), first hearts with 2-3 cats (Pancake gets the welcome treat), 1 request (~¥500), talks with Pip and 1-2 neighbours, about 9 of the 12 sparks for the Harbour Lantern. Ends with a clear next goal shown in the Notebook "Today" line.
- **Day 2-3:** Harbour Lantern lit (day 2), first cat Friend, Sturdy Rod ¥4,000 (day 2-3 at ~¥1,800-2,500 a day).
- **Day 5:** Hill Lantern (25 sparks). First neighbour at level 4 event. First cosmetic.
- **Day 10-14:** Lighthouse Lamp (40 sparks), most day-1 cats are Friends, several neighbours at level 5-6, Lighthouse Rod saved for (¥15,000).
- **Weeks 3-8 (long tail):** Fog and Ghost Koi, Marmalade, trophies for every species, the Spotted Ray via Moss, all 12 bottle notes, neighbours to level 10, gold of every species (genuinely months; that is the forever shelf).

## 7. "I noticed it" secrets (designed, never explained; hinted in lines and bottles)
1. Carrying a Mackerel makes Biscuit follow you; he leads you to the beach and digs up a flats-table item (once per day).
2. Rain pulls big fish in: Sea Bass only appear at the beach in rain, and size records happen in rain.
3. Low tide happens twice. The evening tide spawns a fresh set of flats items most players miss.
4. Lantern Fish rise at the pier at night only once the Harbour lantern is lit.
5. Marmalade only accepts catnip after you have petted three other cats that day.
6. Fog days: the Ghost Koi at the rocks and Fog the cat by the lighthouse. Mist on the horizon the evening before tells you it is coming.
7. Shadow reading: the shadow is the real size. Reeling in early on a small shadow costs nothing.
8. Sit beside Tofu in the afternoon and you both nap: the clock jumps 2 hours (once a day). Useful to reach evening fish.
9. Pepper supervises anyone fishing at the pier, which counts as sitting with her.
10. Saffron sleeps on your porch only when it is sunny.
11. Fern loves the Old Boot (a planter). The junk item is a treasure to one person.
12. Moss's forecast is real: the fish he names bites twice as often that day.

## 8. Feel & juice
Every action: a sound, a squash-stretch on the thing touched, a small particle burst. Camera eases. Mocha's tail wags on good things and droops briefly on misses. Toasts are short, dry and kind ("Pip says that is a suspiciously large fish."). Never a fail screen.

## 9. Save
Autosave to user://save.json every 30 s and after any catch / befriend / purchase / friendship / lantern / request. Load on start. Includes day, minute, yen, bag, records (best cm, trophy, gold per species), cat trust + facts known, shore counts, requests (with day posted), lanterns, rod level, cosmetics, people (points, seen lines, perks, events), bottle note index, flags.

## 10. The forever loop (why it does not get boring)
- **Every session (3-20 min):** check the board and Pip's special, talk to whoever is nearby (one new line each), pick up the morning shore, fish whatever is worth fishing right now. Something new is always within 2 minutes of walking.
- **Every day differs** by weather (4 kinds), the special fish, three new requests, cat placement by slot and weather, Moss's forecast, and two tides.
- **Every week:** a neighbour event, a new perk, a cat becomes a Friend, a lantern.
- **Every month:** fog days, trophies, bottle notes, the last neighbour stories.
- **Forever:** size records and gold variants of 18 species, cat gift collection, cosmetics. No timers that punish absence.
- Walkthrough checks (stress-tested):
  - **Minute 1:** Mocha wakes on the porch, sunny day 1. A note from Pip and one Tuna Bites in the bag. The "Today" line says "Catch a fish at the end of the pier." Biscuit is on the pier, Pancake at the shop: two cats on the first path, one of them pettable immediately.
  - **First 10 minutes:** fish 3 (sardine, mackerel, maybe flounder), pet Biscuit, treat Pancake, sit near Mochi, pick up the beach, meet Pip, Cotton (board) and Moss (pier end), finish a Fern or Cotton shore request with items already picked up. 9-ish sparks. Next goal is visible: 3 sparks to the Harbour Lantern.
  - **Day 3:** rocks open, Disco at night, Sturdy Rod, first Friend cat, a neighbour at level 3 with a new perk. Goal: Hill Lantern.
  - **Day 10:** all three lanterns close, 5-6 Friend cats, first neighbour events, Moss's forecast changes where you fish each morning. Goal: Lighthouse Lamp, the Ray, Marmalade.
  - **Day 30:** Fog cat, trophies, gold hunt, level 9-10 neighbour endings, last bottle notes. Goal: completion shelves and the Post-MVP lanterns.
- Fixed in this pass: hidden cove that did not exist (Biscuit now leads to the beach), Pepper's drop mechanic that did not exist, Marmalade's impossible "every other cat" rule, flats that paid ~¥5,000 per tide, record sparks that lit both lanterns on day 1, fish requests for uncatchable species, size requests impossible before the rocks, a gold request that could block a slot forever, "Fridays" without a calendar, rocks afternoon with no real fish, an uncapped 4-hearts-a-day cat rule, and an unbounded fog drought.

## 11. Moment-to-moment fun checklist (QA verifies each, on a fresh save and on a day-10 save)
1. Within 30 s of starting, the player knows one goal (Today line) and sees at least one cat and one neighbour.
2. Within 2 minutes of walking from any spot, there is something to do: a cat, a shore item, a fishing spot, or a neighbour with an unread line.
3. Every action gives sound + squash + particles within one frame. No silent buttons.
4. Fishing: the shadow size visibly matches the caught size; nibble and bite are clearly different (dip vs dive + splash + haptic); reeling in early never punishes.
5. A tension snap and a miss both show a short kind line and no penalty beyond the lost fish.
6. Every catch card shows size; records, trophies and gold each get a distinct, bigger celebration.
7. Every spot x slot x weather has a non-junk fish (Pier, Beach, Rocks, Flats-with-perk). Verify all 4 x 4 x 4 combinations.
8. Cats: sneaking never scares; riding near a shy cat always does; a scared cat returns within 20 s. A cat never gains more than 3 hearts a day.
9. Wrong treat gives a hint line and keeps the item. Right treat on a shy 0-heart cat works.
10. Each cat secret, haunt and needs_lantern is reachable: verify Biscuit dig, Tofu nap skip, Pepper buddy, Saffron porch on sunny, Mochi at the shop in rain, Disco at the lighthouse at night after Harbour, Marmalade with 3 prior pets, Fog on a fog day.
11. Requests: no impossible request ever appears (species never caught, rocks fish before Harbour, size above the species max). Expired requests are replaced kindly. Gold request never appears twice.
12. Talking to each neighbour once per day gives +20 and a line not seen before (until the band runs out). A second talk the same day gives a short "already chatted" line, no points.
13. Gifts: loved / liked / neutral / disliked each have distinct reactions; one gift per person per day; points never go below 0.
14. Every perk unlock shows a card with exactly what changed, and the effect is measurable (discount on price tags, bite window, flats count, Notebook pages).
15. Level 4 and 8 events play once, in the dialogue panel, with their reward in the bag.
16. Lantern lighting: camera moment plays, light spreads, unlocked area / shop items / cats appear immediately (no reload).
17. Economy targets on a fresh save, playing normally: Harbour lantern day 2, Sturdy Rod day 2-3, Hill lantern by day 5. Flag if any is hit on day 1.
18. Nothing is lost by not playing for a week: requests still there or kindly replaced, no decay, no hearts lost.
19. Text: no emojis, no "coins" (yen only, "¥1,200" format), no text overflow at 540 px, every line reads as adult and kind.
20. Mocha is a Shiba Inu everywhere (model, lines, Notebook). Cats being wary of the dog reads as funny, never sad.
21. No softlocks: every panel closes, fishing can be cancelled at any stage, sleeping and napping always return control.

## 12. Post-MVP (bigger ideas, not in the first build)
- Lanterns 4 and 5 from Wen's map (the hidden cove behind the lighthouse, the old orchard), each with new fish, a cat and a neighbour.
- Home decor: hang Maple's cat portraits, trophy fish mounts, Moss's name board; a yen sink for late game.
- An aquarium / fish tank at home for record fish.
- Festivals on a 7-day calendar: Lantern Night (all Friend cats in the plaza), Fishing Derby (record against neighbours' best), Fern's open garden.
- Seasons (4 x 28 days) rotating fish and shore tables.
- Fern's brother visits; Cotton's shop gets a second shelf; Maple's plaza show. Level 10 epilogue scenes.
- Bait and lures (shop) that bias rarity or size.
- Photo mode with a frame, for sharing.
- Neighbour birthdays, letters in the mailbox.

## 13. Architecture (contracts for the team)
- Autoloads: `GameState` (state + signals + save), `Data` (content tables), `InputBridge` (move vector + action signals from touch and keyboard).
- `Toys` (class_name, static): soft toy mesh builders, materials with ink outline, characters (shiba, cat, fish, townsfolk), props.
- `Island` (world/island.gd): builds terrain with collisions and exposes named spots: `Island.spot(name) -> Vector3`. Spot names: home, porch, plaza, shop, shop_counter, board, pier, pier_end, beach, rocks, lighthouse, hill, flats, lantern_harbour, lantern_hill, spawn. Gating per `Data.SPOT_LANTERN`.
- `SkyCycle` (world/sky_cycle.gd): time-of-day sun, sky, lanterns light, fog-eve mist bank.
- `Player` (player/player.gd): CharacterBody3D, camera rig, moped mount, interaction finder.
- Interactables: any Node3D in group `"interactable"` implementing `get_prompt(player) -> String` (empty = not available), `interact(player) -> void`, and var `interact_radius: float`.
- Systems (systems/*.gd, Node children of Main): `Cats`, `Fishing`, `Shore`, `Town` (shop + board), `Lanterns`, `People`.
- UI (ui/*.gd): `Hud` CanvasLayer (top bar, joystick, buttons, toasts), `Notebook`, `ShopPanel`, `FishingUI`, `CatchCard`, dialogue panel. Style constants in ui/style.gd.
- Data notes for coders: every field documented as optional in data.gd must be read with `.get(key, default)`; a missing field means "no special rule". Constants `WEATHER_ODDS`, `STARTING_YEN`, `STARTING_BAG` are design numbers for GameState.
