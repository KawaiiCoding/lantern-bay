extends Node
## Data (autoload): all content tables. Pure data, no logic. Numbers follow docs/GDD.md (section 6 is the economy).
## Money is YEN everywhere (green paper money). Field names "price"/"reward" are yen amounts. Never say "coins" in UI.
## Every field marked (optional) may be missing on some entries: read it with .get(key, default) and treat a missing
## field as "no special rule". New constants below the original ones are additive; old keys keep their meaning.
##
## Fishing spot ids used in FISH.spots -> Island spot where the fishing interactable stands (see FISH_SPOTS).
## Time slots (GameState.time_slot): morning 05-11, afternoon 11-17, evening 17-21, night 21-05.

# =====================================================================================================
# FISH
# size in cm [min, max]; rarity 1 common .. 4 legendary; weather [] = any; slots [] = any. price = base yen.
# (optional) weight: overrides RARITY_WEIGHT[rarity] for this species in the bite roll.
# (optional) needs_lantern: lantern id that must be lit. (optional) needs_perk: "person:perk" that must be unlocked.
# (optional) low_tide: true = only while GameState.low_tide(). (optional) junk: true = not a fish (no requests, no gold).
# hint: Notebook line shown under the silhouette of a species not caught yet.
const FISH := {
	"sardine":   {"name": "Sardine",       "spots": ["pier", "beach"], "slots": [], "weather": [], "size": [8, 22],   "rarity": 1, "price": 120, "body": "a9c4d6", "fin": "6f8fa8",
		"hint": "Everywhere, always. The bay's background noise."},
	"mackerel":  {"name": "Mackerel",      "spots": ["pier"], "slots": ["morning", "afternoon"], "weather": [], "size": [20, 45], "rarity": 1, "price": 200, "body": "7fb0a8", "fin": "3f6f78",
		"hint": "Runs past the pier end in daylight. A certain cat has opinions about it."},
	"sea_bream": {"name": "Sea Bream",     "spots": ["pier", "rocks"], "slots": ["morning", "evening"], "weather": [], "size": [25, 55], "rarity": 2, "price": 450, "body": "f2a9a0", "fin": "d97a70",
		"hint": "Pink and punctual. Mornings and evenings only."},
	"flounder":  {"name": "Flounder",      "spots": ["beach", "flats"], "slots": [], "weather": [], "size": [18, 50], "rarity": 1, "price": 240, "body": "c9b08a", "fin": "9a7f5c",
		"hint": "Lies flat in the beach sand and thinks you cannot see it."},
	"blowfish":  {"name": "Puffer",        "spots": ["pier"], "slots": ["afternoon"], "weather": ["sunny"], "size": [10, 30], "rarity": 2, "price": 550, "body": "f6e2a0", "fin": "d9b860",
		"hint": "Sunbathes off the pier on bright afternoons."},
	"squid":     {"name": "Little Squid",  "spots": ["pier"], "slots": ["night"], "weather": [], "size": [12, 35], "rarity": 2, "price": 480, "body": "f6dce6", "fin": "e0a8c0",
		"hint": "Comes up to the pier lights after dark."},
	"eel":       {"name": "Moray Eel",     "spots": ["rocks"], "slots": ["evening", "night"], "weather": [], "size": [50, 120], "rarity": 2, "price": 700, "body": "8f9a5c", "fin": "5f6a3c",
		"hint": "Lives in the rocks. Comes out when the light goes."},
	"tuna":      {"name": "Bluefin Tuna",  "spots": ["rocks"], "slots": ["morning"], "weather": [], "size": [80, 220], "rarity": 3, "price": 3000, "body": "4f6fa0", "fin": "2f4f78",
		"hint": "Cold water off the rocks, mornings. Bring patience and a good rod."},
	"seahorse":  {"name": "Seahorse",      "spots": ["beach"], "slots": ["afternoon"], "weather": ["sunny", "cloudy"], "size": [5, 18], "rarity": 2, "price": 850, "body": "f4c070", "fin": "d99a40",
		"hint": "Drifts in the shallows on calm afternoons. Hates rain."},
	"crab":      {"name": "Shore Crab",    "spots": ["beach", "rocks"], "slots": [], "weather": [], "size": [6, 20], "rarity": 1, "price": 150, "body": "e8746a", "fin": "c4504a",
		"hint": "Technically not a fish. Do not tell it."},
	"octopus":   {"name": "Octopus",       "spots": ["rocks"], "slots": ["night"], "weather": [], "size": [30, 90], "rarity": 3, "price": 2000, "body": "d98aa8", "fin": "b0607f",
		"hint": "A night shape between the rocks. Very clever, slightly smug."},
	"salmon":    {"name": "Salmon",        "spots": ["pier"], "slots": ["evening"], "weather": ["rain", "cloudy"], "size": [45, 90], "rarity": 2, "price": 900, "body": "f2a07a", "fin": "c97050",
		"hint": "Passes the pier on grey evenings. Moss's favourite."},
	"angelfish": {"name": "Angelfish",     "spots": ["rocks"], "slots": ["afternoon"], "weather": ["sunny"], "size": [10, 25], "rarity": 3, "price": 1500, "body": "fff1a0", "fin": "7fc0e0",
		"hint": "Only on sunny afternoons at the rocks. Looks expensive. Is."},
	"lanternfish": {"name": "Lantern Fish", "spots": ["pier"], "slots": ["night"], "weather": [], "size": [8, 20], "rarity": 3, "price": 2200, "body": "bfe6ff", "fin": "fff1b8", "needs_lantern": "harbour", "weight": 14,
		"hint": "They say these rise to the pier when the harbour burns bright."},
	"ghost_koi": {"name": "Ghost Koi",     "spots": ["rocks"], "slots": [], "weather": ["fog"], "size": [40, 80], "rarity": 4, "price": 5000, "body": "f4f6fb", "fin": "c9d6f0", "weight": 10,
		"hint": "Something pale at the rocks, on days you cannot see the horizon."},
	"old_boot":  {"name": "Old Boot",      "spots": ["pier", "beach", "rocks", "flats"], "slots": [], "weather": [], "size": [26, 30], "rarity": 1, "price": 10, "body": "7a5a4c", "fin": "5a3f34", "junk": true,
		"hint": "Worth almost nothing. To almost everyone."},
	# Added: a common for the rocks so every slot there has a real fish, a rain fish for the beach, a perk-gated ray.
	"rockfish":  {"name": "Rockfish",      "spots": ["rocks"], "slots": [], "weather": [], "size": [20, 45], "rarity": 1, "price": 220, "body": "b0705a", "fin": "7a4a3a",
		"hint": "Lives at the rocks all day. Grumpy face, good company."},
	"sea_bass":  {"name": "Sea Bass",      "spots": ["beach", "flats"], "slots": [], "weather": ["rain"], "size": [40, 100], "rarity": 2, "price": 800, "body": "9aa4ae", "fin": "5f6a76",
		"hint": "Only pushes up the beach when it rains. Big ones get greedy in bad weather."},
	"ray":       {"name": "Spotted Ray",   "spots": ["flats"], "slots": [], "weather": [], "size": [60, 140], "rarity": 3, "price": 2400, "body": "c8b49a", "fin": "8a7560", "low_tide": true, "needs_perk": "moss:secret_spot",
		"hint": "Moss mentioned a sandbar. Low tide only."},
}
const GOLD_CHANCE := 0.01
const GOLD_PRICE_MULT := 5

## Fishing tuning (GDD 5.1).
const FISH_SPOTS := {"pier": "pier_end", "beach": "beach", "rocks": "rocks", "flats": "flats"}   # fish spot id -> Island spot
## "flats" fishing exists only at low tide AND with perk moss:secret_spot; without it the flats are shore-combing only.
const SPOT_LANTERN := {"rocks": "harbour", "lighthouse": "harbour", "hill": "hill"}               # Island spot -> lantern needed
const RARITY_NAMES := {1: "Common", 2: "Uncommon", 3: "Rare", 4: "Legendary"}
const RARITY_WEIGHT := {1: 60, 2: 28, 3: 10, 4: 4}   # bite roll weight per eligible species (junk uses JUNK_WEIGHT)
const JUNK_WEIGHT := 8
const FISH_WAIT := [2.0, 8.0]          # seconds before a shadow commits
const FISH_NIBBLES := [0, 3]           # fake-out dips before the real bite
const BITE_WINDOW_RARE_PENALTY := 0.2  # rarity >= 3: window = rod bite_window - this (+ perks)
const REEL_SECONDS := [4.0, 9.0]       # scales with size fraction
const SIZE_CURVE := 1.8                # size = min + (max-min) * pow(randf(), curve); >1 skews small, so records stay rare
const SIZE_CURVE_RAIN := 1.2           # rain: bigger fish everywhere
const RAIN_BIG_MIN_CM := 45            # rain: species whose max size >= this get weight x RAIN_BIG_WEIGHT_MULT
const RAIN_BIG_WEIGHT_MULT := 1.5
const TROPHY_FRACTION := 0.9           # size >= min + 0.9*(max-min) is a Trophy (first one per species: SPARK.trophy)
const PRICE_SIZE_MULT := [0.7, 1.3]    # sell price = price * lerp(a, b, size fraction)
const RECAST_FREE := true              # tapping Action while the shadow approaches reels in with no penalty

# =====================================================================================================
# CATS
# haunts: slot -> Island spot (weather "rain" overrides with rain_spot when set). Missing slot = not out.
# shy: needs trust from sitting before pets work. scares: riding/full-speed near it makes it run.
# (optional) needs_lantern: hidden until that lantern is lit. (optional) weather_only: only out in these weathers.
# (optional) sun_spot: spot used instead of the haunt when sunny. (optional) gift: bag id this cat leaves as a Friend.
# (optional) secret_spot: where the Mackerel follow leads (cat digs up one flats-table item, once per day).
# (optional) treat_needs_pets: other cats petted today before the treat is accepted.
# (optional) nap_skip_hours: sitting next to it in the afternoon skips the clock this much (once per day).
# (optional) fishing_buddy: comes and sits by you while you fish at the pier (counts as that day's Sit).
const CATS := {
	"biscuit":    {"name": "Mayor Biscuit", "main": "f6dcb4", "patch": "e39a62", "personality": "Bold",
		"haunts": {"morning": "pier", "afternoon": "shop", "evening": "pier", "night": "plaza"},
		"favourite": "fish:mackerel", "secret": "Follows anyone carrying a Mackerel, and leads them somewhere worth digging.", "shy": false, "scares": false,
		"secret_spot": "beach", "gift": "shore:glass_green",
		"rumour": "A very official-looking cat inspects the pier every morning."},
	"tofu":       {"name": "Tofu", "main": "f7f3ee", "patch": "", "personality": "Lazy",
		"haunts": {"morning": "home", "afternoon": "plaza", "evening": "plaza", "night": "home"},
		"favourite": "treat:cream", "secret": "Sit beside her in the afternoon sun and you will both nap. The clock jumps ahead.", "shy": false, "scares": false,
		"nap_skip_hours": 2, "gift": "shore:shell_white",
		"rumour": "Something white and round sleeps in the plaza all afternoon."},
	"disco":      {"name": "Disco", "main": "3a3550", "patch": "2a2540", "personality": "Curious",
		"haunts": {"evening": "lighthouse", "night": "lighthouse"}, "needs_lantern": "harbour",
		"favourite": "fish:squid", "secret": "Only out after dark. Waits on the lighthouse steps for a beam that is not there yet.", "shy": true, "scares": true,
		"gift": "shore:glass_blue",
		"rumour": "Two green eyes by the lighthouse, only at night."},
	"pancake":    {"name": "Pancake", "main": "f2d3a6", "patch": "c9884d", "personality": "Bold",
		"haunts": {"morning": "shop", "afternoon": "shop", "evening": "beach"},
		"favourite": "treat:tuna_bites", "secret": "Waits by the shop door when Pip opens. Walks the beach at dusk.", "shy": false, "scares": false,
		"gift": "fish:sardine",
		"rumour": "The shop has a doorman. He is a cat."},
	"marmalade":  {"name": "Marmalade", "main": "f2a35c", "patch": "d97a3a", "personality": "Grumpy",
		"haunts": {"morning": "hill", "afternoon": "hill", "evening": "hill"}, "needs_lantern": "hill",
		"favourite": "treat:catnip", "secret": "Only accepts a treat once you have petted three other cats today.", "shy": true, "scares": true,
		"treat_needs_pets": 3, "gift": "shore:star_stone",
		"rumour": "An orange cat on the hill glares at everyone. Professionally."},
	"mochi":      {"name": "Mochi", "main": "fbe3ea", "patch": "", "personality": "Shy",
		"haunts": {"morning": "beach", "afternoon": "beach"}, "rain_spot": "shop",
		"favourite": "fish:sardine", "secret": "Hides under the shop awning when it rains.", "shy": true, "scares": true,
		"gift": "shore:shell_pink",
		"rumour": "A pink cat watches the waves. It runs from engines."},
	"pepper":     {"name": "Pepper", "main": "6e6a72", "patch": "4a4650", "personality": "Curious",
		"haunts": {"morning": "plaza", "afternoon": "pier", "evening": "shop", "night": "plaza"},
		"favourite": "fish:crab", "secret": "Comes and sits beside anyone fishing at the pier. Supervises.", "shy": false, "scares": false,
		"fishing_buddy": true, "gift": "shore:driftwood",
		"rumour": "A grey cat seems very interested in your fishing technique."},
	"saffron":    {"name": "Saffron", "main": "f6e2a0", "patch": "e0b860", "personality": "Lazy",
		"haunts": {"afternoon": "home", "evening": "home"}, "sun_spot": "porch",
		"favourite": "treat:cream", "secret": "Sleeps on your porch if it is sunny.", "shy": false, "scares": false,
		"gift": "shore:glass_amber",
		"rumour": "Someone yellow keeps borrowing your porch."},
	"ghost":      {"name": "Fog", "main": "dfe4ee", "patch": "c4cbdc", "personality": "Shy",
		"haunts": {"morning": "lighthouse", "afternoon": "lighthouse", "evening": "lighthouse", "night": "lighthouse"}, "needs_lantern": "harbour",
		"weather_only": ["fog"], "favourite": "fish:ghost_koi", "secret": "Appears only on foggy days.", "shy": true, "scares": true,
		"gift": "shore:moon_shell",
		"rumour": "On foggy days, a pale cat by the lighthouse. Or is it?"},
	"captain":    {"name": "Admiral", "main": "8f7a6a", "patch": "f7f3ee", "personality": "Bold",
		"haunts": {"morning": "hill", "evening": "pier", "night": "pier"}, "needs_lantern": "hill",
		"favourite": "fish:tuna", "secret": "Moss's cat, though he would deny it. Naps on the hill, meets the evening boat at the pier. Eats only tuna.", "shy": false, "scares": false,
		"gift": "fish:mackerel",
		"rumour": "An old sea cat comes ashore when the hill lantern burns."},
}
const CAT_MAX_HEARTS := 5
const CAT_DAILY_HEART_CAP := 3         # sit +1, pet +1, favourite treat +2, but never more than this per cat per day
const CAT_SCARE_RIDE_RADIUS := 4.0
const CAT_SCARE_RUN_RADIUS := 2.0
const CAT_FLEE_DIST := 6.0
const CAT_RETURN_SECONDS := 20.0       # a scared cat walks back to its haunt after this
const CAT_SIT_TICK := 6.0              # while sitting, each tick a nearby cat (<= 5 m) may step closer
const CAT_GIFT_CHANCE := 0.35          # per Friend cat, each morning
const CAT_GIFTS_PER_MORNING := 2       # max gifts on the porch per morning
const CAT_GIFT_YEN := [150, 400]       # 25% of gifts are a folded yen note instead of the cat's item

# =====================================================================================================
# SHORE. where: "beach" (each morning) or "flats" (each low tide window). price in yen.
# (optional) can_gold: may roll gold (SHORE_GOLD_CHANCE); a gold shell sells for GOLD_SHELL_PRICE.
const SHORE := {
	"shell_white": {"name": "White Shell", "where": "beach", "weight": 30, "price": 25, "color": "fbf3e6", "can_gold": true},
	"shell_pink":  {"name": "Pink Scallop", "where": "beach", "weight": 18, "price": 50, "color": "f6b8c4", "can_gold": true},
	"glass_green": {"name": "Green Sea Glass", "where": "beach", "weight": 12, "price": 80, "color": "9fd8b0"},
	"glass_blue":  {"name": "Blue Sea Glass", "where": "beach", "weight": 8, "price": 110, "color": "9cc8ef"},
	"driftwood":   {"name": "Driftwood", "where": "beach", "weight": 14, "price": 30, "color": "c9a882"},
	"star_stone":  {"name": "Star Stone", "where": "flats", "weight": 1, "price": 1500, "color": "ffe08a"},
	"moon_shell":  {"name": "Moon Shell", "where": "flats", "weight": 8, "price": 400, "color": "e8e4ff", "can_gold": true},
	"bottle":      {"name": "Message Bottle", "where": "beach", "weight": 2, "price": 0, "color": "bfe3ee", "bottle": true},
	"glass_amber": {"name": "Amber Sea Glass", "where": "beach", "weight": 3, "price": 250, "color": "f0b860"},
	"sand_dollar": {"name": "Sand Dollar", "where": "flats", "weight": 30, "price": 60, "color": "f2e6cf", "can_gold": true},
	"razor_shell": {"name": "Razor Shell", "where": "flats", "weight": 22, "price": 40, "color": "d8cbb8"},
}
const SHORE_BEACH_DAILY := 14
const SHORE_FLATS_DAILY := 6           # per low tide window (06:00 and 18:00); leftovers wash away when the tide returns
const SHORE_GOLD_CHANCE := 0.02
const GOLD_SHELL_PRICE := 1200
const BOTTLE_YEN := 800                # folded inside every message bottle
## Message bottle notes, in order (first bottle = note 0). After the last, bottles hold yen and a random old note.
## Written by Ines, the old lantern keeper (Pip's grandmother). Several are hints for secrets.
const BOTTLE_NOTES := [
	"To whoever finds this: the bay is kinder than it looks. So are most of the people. Ines.",
	"Mackerel make Biscuit loyal. Follow him and he will dig you something worth finding. He did it for me, years ago.",
	"The tide goes out twice a day. Most people only walk the flats in the morning. The evening one is just as generous.",
	"Rain is the best day to fish. The big ones get greedy when the sky is busy.",
	"A small shadow is a small fish. Reel in and cast again. There is no shame in waiting for better.",
	"Light the harbour first. The little lantern fish need it. Then the hill. Then my lamp, last.",
	"Pip, if this reaches you: I know you will come back. Leave the shelves where they are. I like them there.",
	"Sit with the lazy cat in the afternoon sun. You will nap. It is allowed. It is encouraged.",
	"Marmalade takes a treat only after you have greeted three other cats. She has standards. So should you.",
	"If the sea goes pale and quiet, go to the rocks. Something old swims there in the fog.",
	"Moss: June is fine where she is. Go out at dawn again. She would want the boat used.",
	"If you have read all of these, you have been very patient, or the sea is very bored. Either way: stay. Ines.",
]

# =====================================================================================================
# PIP'S SHOP. price in yen. (optional) needs_lantern: hidden until lit. (optional) hidden: true = never listed in the
# shop (gift-only cosmetics from townsfolk perks; kept in SHOP so the player can render slot/colour).
const SHOP := {
	"treat:tuna_bites": {"name": "Tuna Bites", "price": 200, "kind": "treat"},
	"treat:catnip":     {"name": "Catnip Sprig", "price": 350, "kind": "treat"},
	"treat:cream":      {"name": "Cream Cup", "price": 500, "kind": "treat"},
	"rod:2":            {"name": "Sturdy Rod", "price": 4000, "kind": "rod", "level": 2, "desc": "Longer bite window, calmer fish."},
	"rod:3":            {"name": "Lighthouse Rod", "price": 15000, "kind": "rod", "level": 3, "desc": "Rare fish bite more often.", "needs_lantern": "lighthouse"},
	"cos:scarf_mint":   {"name": "Mint Scarf", "price": 1500, "kind": "cosmetic", "slot": "scarf", "color": "6fc2b6"},
	"cos:scarf_berry":  {"name": "Berry Scarf", "price": 1500, "kind": "cosmetic", "slot": "scarf", "color": "c4506a"},
	"cos:cap":          {"name": "Fisher's Cap", "price": 3000, "kind": "cosmetic", "slot": "hat", "color": "f2c14e"},
	"cos:paint_peach":  {"name": "Peach Moped Paint", "price": 8000, "kind": "cosmetic", "slot": "paint", "color": "f6b89a"},
	"cos:scarf_navy":   {"name": "Navy Scarf", "price": 1800, "kind": "cosmetic", "slot": "scarf", "color": "2f3f5f"},
	"cos:cap_olive":    {"name": "Olive Cap", "price": 3000, "kind": "cosmetic", "slot": "hat", "color": "7a8450"},
	"cos:paint_sage":   {"name": "Sage Moped Paint", "price": 6500, "kind": "cosmetic", "slot": "paint", "color": "a8c0a0"},
	"cos:paint_night":  {"name": "Harbour Night Paint", "price": 12000, "kind": "cosmetic", "slot": "paint", "color": "2a3550", "needs_lantern": "lighthouse"},
	"cos:scarf_oat":    {"name": "Oatmeal Scarf", "price": 2500, "kind": "cosmetic", "slot": "scarf", "color": "e6dcc8", "hidden": true},
	"cos:scarf_harbour": {"name": "Harbour Stripe Scarf", "price": 2500, "kind": "cosmetic", "slot": "scarf", "color": "4a6a8a", "hidden": true},
	"cos:cap_knit":     {"name": "Knitted Beanie", "price": 2500, "kind": "cosmetic", "slot": "hat", "color": "c9884d", "hidden": true},
}
const ROD := {
	1: {"bite_window": 0.7, "surge": 1.0, "rare_bonus": 0.0},
	2: {"bite_window": 0.85, "surge": 0.8, "rare_bonus": 0.0},
	3: {"bite_window": 0.9, "surge": 0.75, "rare_bonus": 0.5},   # rare_bonus: rarity >= 3 weights x (1 + bonus)
}
const DAILY_SPECIAL_MULT := 2.0        # Pip pays double for one species per day (day_rng pick among species already caught; shown on the board)
const NIGHT_MARKET_MULT := 1.5         # hill stall, 21:00-24:00, after the hill lantern: rarity >= 3 fish, star stone, moon shell, gold items

## Extra bag items that are not fish/shore/shop (townsfolk gifts). id -> name, sell price in yen.
const ITEMS := {
	"flower:sea_pink":   {"name": "Sea Pink", "price": 150, "color": "f2a0b8"},
	"flower:moonflower": {"name": "Moonflower", "price": 900, "color": "eef0ff"},
}

# =====================================================================================================
# REQUESTS. kind: "fish_size" (any fish >= cm), "fish" (species), "shore" (count of an item), "gold" (any gold item).
# who = person id in PEOPLE (completing gives PEOPLE_POINTS.request friendship). reward = yen [min, max].
# (optional) min_cm_late: range used once the harbour lantern is lit. (optional) items: shore ids this template may ask for.
# (optional) reward_price_mult: fish requests add species price * this to the reward. (optional) max_rarity: fish pool cap.
# (optional) pool: "caught" = only species the player has caught before (fallback: rarity 1 fish open right now).
# (optional) auto_on_catch: the qualifying fish is handed over the moment it is caught (the bag cannot store sizes).
#   Junk never qualifies ("Maple appreciates the effort. It is a boot.").
# (optional) sparks: overrides SPARK.request. (optional) weight: pick weight (default 4). (optional) max_active: cap.
const REQUEST_TEMPLATES := [
	{"kind": "fish_size", "who": "maple", "text": "Maple wants to paint a fish over %d cm. From life.", "min_cm": [25, 38], "min_cm_late": [40, 70], "reward": [400, 800], "auto_on_catch": true},
	{"kind": "fish", "who": "pip", "text": "Pip needs a %s for the shop window.", "reward": [250, 500], "reward_price_mult": 1.5, "max_rarity": 2, "pool": "caught"},
	{"kind": "shore", "who": "cotton", "text": "Cotton needs %d %s for a mobile.", "count": [2, 4], "items": ["glass_green", "glass_blue", "shell_pink"], "reward": [300, 600]},
	{"kind": "shore", "who": "fern", "text": "Fern is collecting %d %s. Don't ask.", "count": [3, 5], "items": ["driftwood", "shell_white", "sand_dollar", "razor_shell"], "reward": [350, 700]},
	{"kind": "gold", "who": "pip", "text": "Pip will pay a fortune for anything gold.", "reward": [2000, 2000], "sparks": 2, "weight": 1, "max_active": 1},
	{"kind": "fish", "who": "moss", "text": "Moss is cooking for the street and has promised a %s. Optimistically.", "reward": [300, 550], "reward_price_mult": 1.5, "max_rarity": 2, "pool": "caught"},
	{"kind": "fish_size", "who": "moss", "text": "Moss bet Wen you could land something over %d cm. Do not let him down.", "min_cm": [28, 40], "min_cm_late": [50, 90], "reward": [450, 900], "auto_on_catch": true},
	{"kind": "shore", "who": "wen", "text": "Wen wants %d %s for the lighthouse windowsill.", "count": [1, 2], "items": ["glass_amber", "glass_blue", "moon_shell"], "reward": [500, 900]},
	{"kind": "shore", "who": "maple", "text": "Maple has run out of a colour. She needs %d %s to look at.", "count": [2, 3], "items": ["glass_green", "glass_amber", "shell_pink"], "reward": [350, 650]},
]
const REQUESTS_PER_DAY := 3
const REQUEST_EXPIRE_DAYS := 3         # an untouched request is gently replaced after this many mornings ("Maple found one elsewhere.")

# =====================================================================================================
# LANTERNS. cost in sparks. (optional) after: must be lit first. (optional) unlock_shop: shop ids that appear.
const LANTERNS := {
	"harbour": {"name": "Harbour Lantern", "cost": 12, "spot": "lantern_harbour", "unlocks": "The lighthouse rocks are open for fishing. Lantern fish gather at the pier at night. Someone has started sitting on the lighthouse steps."},
	"hill":    {"name": "Hill Lantern", "cost": 25, "spot": "lantern_hill", "after": "harbour", "unlocks": "The hill path is open. A night stall on the hill buys rare finds. Someone old comes ashore."},
	"lighthouse": {"name": "Lighthouse Lamp", "cost": 40, "spot": "lighthouse", "after": "hill", "unlock_shop": ["rod:3", "cos:paint_night"], "unlocks": "The lamp turns again. Pip has ordered in a better rod, and Wen is pretending not to cry."},
}
## Sparks earned per event. "record" is 0 on purpose: every new best still shows "New record!", but only the first
## Trophy-size catch of a species pays a spark ("trophy"), so early re-catches cannot flood the lanterns.
const SPARK := {"new_fish": 1, "new_cat_fact": 0, "cat_friend": 3, "request": 1, "record": 0, "new_shore": 1,
	"trophy": 1, "gold": 1, "person_level5": 2, "person_level10": 3}

## Weather (GameState owns the roll; these are the design numbers). Day 1 is always sunny; never fog before day 4;
## fog is forced if the last fog day was WEATHER_FOG_MAX_GAP days ago (Wen's fog_bell perk value replaces the gap).
const WEATHER_ODDS := {"sunny": 0.45, "cloudy": 0.25, "rain": 0.22, "fog": 0.08}
const WEATHER_FOG_MAX_GAP := 14
const WEATHER_FOG_MIN_DAY := 4

## Start of a fresh save (GameState owns the values; these are the design numbers).
const STARTING_YEN := 500
const STARTING_BAG := {"treat:tuna_bites": 1}   # Pip's welcome gift: try it on Pancake, the shop cat
## First-days goal list (Notebook "Today" line shows the first unfinished one, then the next lantern's progress).
const STARTER_GOALS := [
	{"id": "catch_fish", "text": "Catch a fish at the end of the pier."},
	{"id": "talk_pip", "text": "Say hello to Pip at the shop."},
	{"id": "pet_cat", "text": "Make friends with a cat. Walk slowly."},
	{"id": "sell", "text": "Sell something to Pip."},
	{"id": "request", "text": "Finish a request from the board."},
	{"id": "lantern_harbour", "text": "Light the Harbour Lantern."},
]

# =====================================================================================================
# TOWNSFOLK. See GDD 5.6.
# routine: slot -> Island spot. loves/likes/dislikes: bag item ids (anything else is neutral).
# lines: band -> lines ("0" = levels 0-2, "3" = 3-5, "6" = 6-8, "9" = 9-10). Daily talk shows an unseen line from the
#   current band (state.seen_lines); when all are seen, pick any line of the band.
# events: played once on the first talk after reaching the level. (optional) reward: {"item": id, "n": int}.
# perks: unlocked at level. The same perk id at several levels = an upgrade; perk_value() returns the highest unlocked
#   value. (optional) gift_cosmetic: shop id added to GameState.cosmetics when the perk unlocks.
const PEOPLE_LEVELS := [30, 80, 150, 240, 350, 480, 640, 830, 1050, 1300]   # points needed for levels 1..10
const PEOPLE_POINTS := {"talk": 20, "loved": 80, "liked": 40, "neutral": 10, "disliked": -20, "request": 60}
const PEOPLE_FLOWERS_LIKED := true     # flowers count as "liked" for anyone who does not list them as loved or disliked

const PEOPLE := {
	"pip": {"name": "Pip", "species": "raccoon", "main": "8a8f99", "accent": "2f3a4a", "role": "Runs the general store",
		"about": "Mid-thirties. Came back from the city to keep his late grandmother's shop open. Dry, kind, counts everything.",
		"home": "shop", "routine": {"morning": "shop_counter", "afternoon": "shop_counter", "evening": "shop_counter", "night": "shop"},
		"loves": ["shore:star_stone", "fish:tuna"], "likes": ["fish:mackerel", "shore:glass_blue", "flower:sea_pink"], "dislikes": ["fish:old_boot"],
		"perks": [
			{"level": 2, "id": "shop_discount", "value": 0.05, "text": "Pip knocks 5% off everything. 'Friends rate. Do not tell Maple.'"},
			{"level": 3, "id": "special_bonus", "value": 0.5, "text": "Pip pays x2.5 instead of x2 for today's special fish."},
			{"level": 5, "id": "shop_discount", "value": 0.10, "text": "Shop discount is now 10%."},
			{"level": 6, "id": "gold_bonus", "value": 0.2, "text": "Pip buys anything gold for 20% more."},
			{"level": 8, "id": "shop_discount", "value": 0.15, "text": "Shop discount is now 15%."},
			{"level": 10, "id": "sell_bonus", "value": 0.05, "text": "Pip pays 5% more for everything you sell."},
		],
		"events": [
			{"level": 4, "title": "The Ledger", "lines": [
				"Pip lifts a heavy book from under the counter.",
				"\"Grandma's ledger. Forty years of sardines in her handwriting. I just keep adding to it.\"",
				"Inside the cover, in faded ink: Light them one at a time. Nobody here does anything all at once.",
				"\"She meant the lanterns. Or me. Probably both.\""]},
			{"level": 8, "title": "Closing Early", "reward": {"item": "shore:star_stone", "n": 1}, "lines": [
				"Pip flips the sign to CLOSED and sits on the shop step beside you.",
				"\"I had a job offer. The city. Good money. I left the letter on the counter until it went yellow.\"",
				"\"You are the first person I have told. Moss guessed. Moss always guesses.\"",
				"He hands you a star stone. \"She found this one. It should be out in the world.\""]},
		],
		"lines": {
			"0": ["Welcome to Pip's. It is the only shop, so technically also the best one.",
				"Sell me fish, buy treats for cats who will not thank you. That is the economy here.",
				"The board outside is for requests. People here would rather pin a note than ask in person.",
				"Bigger fish, better price. I have a tape measure and no shame.",
				"My grandmother ran this shop for forty years. I have run it for two. She was better at small talk.",
				"The lanterns went dark the winter she died. Nobody here likes to say that out loud.",
				"Pancake is not my cat. Pancake is the shop's cat. I just feed him and apologise to customers.",
				"Every day I pay double for one kind of fish. It says which on the board. Read the board.",
				"You look like someone who used to answer emails at midnight. It wears off. Give it a month."],
			"3": ["I moved to the city at nineteen. Spreadsheets, a nice coat, a terrible flat. I was very good at being tired.",
				"Grandma Ines wrote letters to the sea. Bottles. I thought it was a joke until one washed back in.",
				"Maple owes me for three canvases. I will never ask. She knows I will never ask. It is a whole system.",
				"Moss has bought the same tin of tea every week for eleven years. I have stopped stocking any other kind.",
				"When the harbour lantern came on, I closed the shop for ten minutes. First time in two years.",
				"Cotton keeps knitting me hats. I have nine. I wear them on rotation so nobody feels left out.",
				"I can tell what day it is by what Fern buys. Mondays are compost. Every day is compost.",
				"Gold things are rare. That is the point of them. I pay accordingly.",
				"Wen comes in at three in the morning for biscuits. We do not discuss why either of us is awake."],
			"6": ["She left me the shop and a note: 'Do not sell it to anyone who does not fish.' Very specific woman.",
				"Some nights I count the lit lanterns from the step. It is a small number. It is going up.",
				"I used to think staying here meant giving up. Now I think leaving was the easy part.",
				"If you ever find her last bottle, bring it to me first. I will pretend to be calm.",
				"I put your record fish on the wall chart. Do not get a big head. The wall is small.",
				"The city keeps sending emails. I have started replying with pictures of the sea.",
				"I tried to raise the price of cream once. Cotton looked at me. I lowered it.",
				"You are good for this place. I say that as someone who is bad at saying things."],
			"9": ["I wrote back to the city. I said no. It took one line. I had been drafting it for a year.",
				"You are on the shop's 'Friends of Pip' list. It is a real list. It has five names. You are fourth.",
				"Grandma would have liked you. She liked anyone who came back to the pier when it was raining.",
				"I am thinking of painting the shop. Maple says green. Maple says green about everything.",
				"When the last lantern is lit, I am closing early and buying everyone a drink. Hold me to it.",
				"Thank you. For the fish, mostly. Also the rest of it.",
				"I have started whistling while I sweep. Pancake hates it. I think that means I am happy.",
				"Stay as long as you like. The bay has a way of turning 'a while' into 'home'."],
		}},

	"maple": {"name": "Maple", "species": "fox", "main": "e3874a", "accent": "fbf3e6", "role": "Painter",
		"about": "Early thirties. Ex-commercial illustrator who came for two weeks four years ago. Paints only the sea. Afraid of faces.",
		"home": "plaza", "routine": {"morning": "beach", "afternoon": "plaza", "evening": "pier", "night": "plaza"},
		"loves": ["shore:glass_amber", "flower:moonflower"], "likes": ["shore:glass_green", "shore:shell_pink", "fish:seahorse", "fish:squid", "flower:sea_pink"], "dislikes": ["fish:eel"],
		"perks": [
			{"level": 2, "id": "reveal_haunts", "value": 1.0, "text": "Maple sketches where cats hang out. The Notebook now shows the haunts of every cat you have met."},
			{"level": 5, "id": "cat_portraits", "value": 1.0, "text": "Maple paints each cat you befriend. Their Notebook page gets her portrait."},
			{"level": 7, "id": "cat_calm", "value": 0.6, "text": "Maple taught you to move like a painter. Cats only startle from 60% as far away."},
			{"level": 10, "id": "secret_hints", "value": 1.0, "text": "Maple's sketchbook: each cat page shows a one-line hint about its secret."},
		],
		"events": [
			{"level": 4, "title": "Upside Down", "lines": [
				"Maple stares at her painting on Pip's wall. Then she turns it the right way up.",
				"\"It was a portrait once. My mother. I painted the sea over her.\"",
				"\"Pip hung it upside down and I let him. It was easier to look at.\"",
				"\"Do not tell him. He thinks he has an eye for art.\""]},
			{"level": 8, "title": "First Face", "lines": [
				"Maple hands you a sketchbook, open at a page. It is you, on the pier, fishing.",
				"\"Do not say anything. I have not drawn a face in six years.\"",
				"\"It is not very good. The hands are wrong. I am keeping it anyway.\"",
				"She takes it back very carefully."]},
		],
		"lines": {
			"0": ["Hold still. No, not you. The light. It does this thing around nine.",
				"I paint the sea. Only the sea. People ask why. The sea does not ask me why.",
				"If you see a cat that looks like it is posing, that is Biscuit. He wants royalties.",
				"I used to draw cereal boxes. You have eaten breakfast next to my work. You are welcome.",
				"Do not move to an island to find yourself. Move here for the light. You will find yourself by accident.",
				"Sea glass is just bottles that had a long, interesting life. Like most of us.",
				"Fern says my paintings are 'fine'. From Fern, that is a standing ovation.",
				"The cats here run on timetables. Watch for a week. You will start setting your watch by them.",
				"Mornings at the beach, afternoons in the plaza, evenings on the pier. You could find me blindfolded."],
			"3": ["I have a rule: no faces. Faces want something from you. The sea only wants to be looked at.",
				"I sold a painting to Pip. He hung it upside down. I told him it was correct.",
				"My old studio had no windows. I could paint without windows. That was the problem.",
				"Tofu sleeps in exactly the same patch of sun every afternoon. I have painted her eleven times.",
				"Cotton asked me to paint his shop sign. He does not have a shop. I am waiting.",
				"I came for two weeks. That was four years ago. The ferry still has my return ticket, somewhere.",
				"Amber sea glass is my favourite. It looks like the last minute of a summer evening.",
				"Rainy days are the best for painting. Nobody watches.",
				"You stopped walking like a tourist. I noticed the day it happened."],
			"6": ["Can I tell you something embarrassing? I am scared of painting people. They might see what I see.",
				"My mother painted portraits. Very good ones. Every one of them looked a little disappointed.",
				"I painted Moss once, from behind, on his old boat. He bought it and has never said a word about it.",
				"You notice things. Most people only look. That is rarer than a gold shell.",
				"I have started a sketchbook. Faces. Mostly cats so far. Cats do not judge. Well. Marmalade judges.",
				"Some days the paint does what I want. Most days it does what it wants. I am learning to like most days.",
				"The lanterns change the colour of the water at night. I had no name for that colour until now.",
				"I almost left last winter. Then the harbour froze a little at the edges and it was too beautiful to leave."],
			"9": ["I painted you. Do not make a face. Well, make one. I need the practice.",
				"I am doing a show. In the plaza. Pip is building the frames out of fish crates.",
				"My mother wrote. She saw a photo of the sea painting. She said it looked happy. That is a first.",
				"You taught me something. Not on purpose. You just keep showing up.",
				"If I ever paint the whole bay lit up, you are in the corner. Small, on the pier, fishing. Accurately.",
				"I bought a real easel. A heavy one. That is how you know I am staying.",
				"Come by when the light goes gold. I will save you the good stool.",
				"Faces are fine, it turns out. Yours, at least."],
		}},

	"cotton": {"name": "Cotton", "species": "sheep", "main": "f3efe6", "accent": "6c7a8c", "role": "Knitter",
		"about": "Late thirties. Twelve years at a bank, then one day he could not get out of the car. Knits. Wants a tiny wool shop.",
		"home": "plaza", "routine": {"morning": "board", "afternoon": "plaza", "evening": "shop", "night": "plaza"},
		"loves": ["treat:cream", "shore:moon_shell"], "likes": ["shore:shell_white", "shore:sand_dollar", "shore:glass_blue", "flower:sea_pink"], "dislikes": ["fish:octopus"],
		"perks": [
			{"level": 2, "id": "scarf_oat", "value": 1.0, "text": "Cotton knitted you an Oatmeal Scarf. It is in your wardrobe.", "gift_cosmetic": "cos:scarf_oat"},
			{"level": 5, "id": "shore_gold", "value": 0.02, "text": "Cotton taught you to look twice. Gold shell chance doubled (+2%)."},
			{"level": 7, "id": "scarf_harbour", "value": 1.0, "text": "Cotton knitted you a Harbour Stripe Scarf.", "gift_cosmetic": "cos:scarf_harbour"},
			{"level": 9, "id": "bottle_bonus", "value": 2.0, "text": "Cotton walks the tideline with you. Message bottles wash up twice as often."},
			{"level": 10, "id": "cap_knit", "value": 1.0, "text": "Cotton knitted you a beanie. He made one for himself too. You match. He is thrilled.", "gift_cosmetic": "cos:cap_knit"},
		],
		"events": [
			{"level": 4, "title": "The Car", "lines": [
				"Cotton is on the board bench at dawn, needles still.",
				"\"I worked at a bank for twelve years. One morning I could not get out of the car. I sat there until it got dark.\"",
				"\"My doctor said find something to do with your hands. I think she meant gardening. Fern was very offended.\"",
				"He goes back to knitting. The stitches are a little faster now."]},
			{"level": 8, "title": "One Shelf", "reward": {"item": "treat:cream", "n": 2}, "lines": [
				"Cotton walks you to the empty unit by the board and unlocks the door.",
				"\"I signed the lease. I have not told anyone. I have one shelf. I am terrified.\"",
				"\"You lit those lanterns one at a time. I am going to do the shop one shelf at a time.\"",
				"He presses two Cream Cups into your hands. \"For the cats. Or for you. I do not judge.\""]},
		],
		"lines": {
			"0": ["Oh. Hello. Sorry. I was counting stitches. I am always counting something.",
				"I used to count other people's money. Now I count stitches. The stitches are nicer to me.",
				"Sea glass makes a good mobile. It turns the light into little fish on the wall.",
				"Knitting is just very slow problem solving. That is what I tell people who ask. Nobody asks.",
				"The wind here is rude but honest. I knit for it.",
				"If I am on the board bench in the morning, I am not reading the requests. I am hiding from my to-do list.",
				"Wool stays warm even when wet. Most things do not. People included.",
				"Pip has nine of my hats. He thinks I do not notice the rotation. I made a spreadsheet.",
				"Mind the white shells. Some of them are still occupied."],
			"3": ["I want to open a wool shop. Small. Two shelves. A chair for whoever needs a chair.",
				"Moon shells are the colour of undyed merino. I would like to own all of them. That is not a healthy thought.",
				"A scarf is a hug with instructions.",
				"Wen and I play chess by post. We live four hundred metres apart. It is still very exciting.",
				"The trick with good luck is to be outside a lot. Gold shells do not wash up indoors.",
				"The cream at Pip's is far too expensive and I buy it twice a week. Self-care is not cheap.",
				"I knit a scarf for everyone who stays a year. You are on track. No pressure. Some pressure.",
				"Bottles wash up more for people who walk the tideline every day. I have no evidence. I have a feeling.",
				"You are a good listener. Most people are just waiting."],
			"6": ["I am terrified of the shop idea. The bank was miserable, but at least I knew what miserable looked like.",
				"My sister calls on Sundays. She asks when I am coming back. I keep saying 'soon' to buy time.",
				"I dyed a skein with Fern's sea pinks. It came out the colour of a sunburn. I love it.",
				"Sorry, I am talking too much. You are easy to talk to. It is suspicious.",
				"Some mornings I still wake at twenty to six for a train that does not exist here.",
				"If the shop fails, I will still have the wool. That is the deal I made with myself.",
				"Pip gave me a discount on shelf brackets. He pretended it was a pricing error.",
				"I think I came here to stop. I am staying because I started something."],
			"9": ["The shop is open on Tuesdays. Only Tuesdays. It is a very ambitious Tuesday.",
				"I told my sister I am not coming back. She said, 'Finally.' She knew before me.",
				"Your scarf is the best one I have made. Do not tell Pip. He has nine.",
				"I sat in a car last week. Just to see. It was fine. I drove to the pier and back. Small trips.",
				"Wen won the chess game. By post. It took eight months. I am delighted.",
				"Thank you for not asking why I left. Then asking, later, when I was ready.",
				"There is always tea. There is always a chair.",
				"I counted. You have visited me more than anyone. I always count."],
		}},

	"fern": {"name": "Fern", "species": "frog", "main": "8fb070", "accent": "e6d79a", "role": "Gardener",
		"about": "Early forties. Economical with words. Grows things in sand out of spite. Her brother went north on the big boats and stopped writing.",
		"home": "board", "routine": {"morning": "beach", "afternoon": "board", "evening": "plaza", "night": "board"},
		"loves": ["fish:old_boot", "shore:razor_shell"], "likes": ["shore:driftwood", "shore:sand_dollar", "fish:sardine"], "dislikes": ["fish:blowfish", "flower:sea_pink"],
		"perks": [
			{"level": 2, "id": "daily_flower", "value": 1.0, "text": "Fern leaves a Sea Pink in the basket by the board every morning. Most people like flowers."},
			{"level": 5, "id": "flats_double", "value": 2.0, "text": "Fern showed you where the flats keep their pockets. Twice as many finds at low tide."},
			{"level": 7, "id": "catnip_gift", "value": 3.0, "text": "Fern's catnip grows like a rumour. A free Catnip Sprig in her basket every 3 days."},
			{"level": 10, "id": "moonflower", "value": 7.0, "text": "The moonflower bloomed. A Moonflower in her basket every 7 days. Everyone loves it, Maple most."},
		],
		"events": [
			{"level": 4, "title": "Sea Pinks", "reward": {"item": "flower:sea_pink", "n": 3}, "lines": [
				"Fern is kneeling by the sea pinks and does not look up.",
				"\"My brother went north on the big boats. He does not write. I planted these the year he left.\"",
				"\"They are the only thing that comes back every spring without being asked.\"",
				"She cuts three and hands them to you. \"Do not make it a thing.\""]},
			{"level": 8, "title": "The Seed in the Drawer", "reward": {"item": "shore:moon_shell", "n": 1}, "lines": [
				"Fern shows you a single grey seed on her palm.",
				"\"Moonflower. Ines planted them by the lighthouse. This one was forty years in a drawer.\"",
				"\"If it blooms, it is a sign. I do not believe in signs. I will still be watching.\"",
				"\"Also I wrote my brother a letter. Do not ask. It is in a seed packet labelled 'later'.\""]},
		],
		"lines": {
			"0": ["You are standing on my thyme.",
				"I grow things. That is the whole sentence.",
				"Driftwood makes good bed edges. Bring some. Or do not. The beds will survive either way.",
				"The soil here is mostly sand and stubbornness. Like the residents.",
				"I collect things. Do not ask what for. It is for things.",
				"Seaweed is free fertiliser. The tide brings it twice a day. The only reliable delivery service on the island.",
				"Cotton tried to garden. He knitted a cosy for a cabbage. The cabbage was fine. Cotton was not.",
				"If a cat sits in my rosemary, I let it. I am not a monster. I am a gardener.",
				"Rain is good. I say that every time it rains. People find it reassuring for some reason."],
			"3": ["That old boot you keep dragging out of the sea? Bring it. Boots make excellent planters. Free drainage.",
				"I am not unfriendly. I am economical with words. Words are a water-intensive crop.",
				"Maple painted my garden. She made it look nice. It is nice. I did not need to be told.",
				"Low tide is when the flats show their pockets. Razor shells, sand dollars. Good for the beds.",
				"Moss knew my brother. They do not talk about it. They talk about weather near it.",
				"Catnip grows like a rumour. Your cats will be insufferable.",
				"Do not bring me sea pinks. I grew them. It is like giving a baker a bread roll.",
				"The evening low tide is quieter than the morning one. Fewer people. Same shells.",
				"I like you. I have said it now. Do not make it a thing."],
			"6": ["Do you have siblings? Do not answer. I can tell. You have the look of someone who was the sensible one.",
				"Moss said my brother asked about me. Two years ago. Moss forgot to mention it. Moss is a walrus.",
				"Gardening is waiting with your hands busy. I am very good at waiting. Too good.",
				"You keep bringing me razor shells. I have enough. Keep bringing them.",
				"At night I come out and listen to things growing. Do not tell Maple, she will paint it.",
				"Ines kept a garden at the lighthouse. Wen lets it grow wild. I go and argue with it on Sundays.",
				"I threw a cabbage at Moss. It was a small cabbage. He deserved a medium one.",
				"The letter is still in the seed packet. Seeds keep. So do letters. Mostly."],
			"9": ["I sent the letter. In a bottle. Wen said that is not how post works. Wen is not a romantic.",
				"He wrote back. Real post. Two pages. Mostly about weather. It was perfect.",
				"The moonflower bloomed. I will grow more. One for you. Do not give it to Maple. Give it to Maple.",
				"You are allowed on my thyme now. Selectively.",
				"My brother might visit at the end of summer. I have started weeding things that are already weeded.",
				"Thank you for being here. I do not say thank you often. Make a note.",
				"Every garden needs one person who visits and says 'oh'. You are my 'oh'.",
				"Come back tomorrow. Something will be different. Something always is."],
		}},

	"moss": {"name": "Captain Moss", "species": "walrus", "main": "8a6e5a", "accent": "d9c7a8", "role": "Retired fisherman",
		"about": "Late sixties. Fished the bay for fifty years. Widowed; stopped going out at dawn. Owns Admiral, who disagrees.",
		"home": "pier", "routine": {"morning": "pier_end", "afternoon": "beach", "evening": "pier", "night": "pier"},
		"loves": ["fish:salmon", "fish:tuna"], "likes": ["fish:mackerel", "fish:sea_bream", "fish:rockfish", "fish:sea_bass"], "dislikes": ["shore:shell_pink"],
		"perks": [
			{"level": 2, "id": "bite_window", "value": 0.05, "text": "Moss fixed your grip. Bite window +0.05 s."},
			{"level": 5, "id": "fish_forecast", "value": 2.0, "text": "Each morning Moss names one rare fish that is biting today, and where. That fish bites twice as often all day."},
			{"level": 7, "id": "bite_window", "value": 0.1, "text": "Moss taught you to feel the line. Bite window +0.1 s."},
			{"level": 8, "id": "secret_spot", "value": 1.0, "text": "Moss showed you the sandbar on the tide flats. You can fish there at low tide."},
			{"level": 10, "id": "rare_bonus", "value": 0.25, "text": "Moss gave you his tin of spots. Rare fish bite 25% more often (stacks with your rod)."},
		],
		"events": [
			{"level": 4, "title": "The Patience", "lines": [
				"Moss walks you past the lighthouse to an old boat pulled up on the stones.",
				"\"The Patience. June named her. Said I needed a boat with a name I could learn from.\"",
				"\"Too old to float, too stubborn to sink. Same as me.\"",
				"He pats the hull twice, like a horse, and walks back without another word."]},
			{"level": 8, "title": "Dawn Again", "lines": [
				"Moss is waiting at the pier at first light, two cups of tea in his hands.",
				"\"Haven't come out at dawn in nine years. Dawn was June's.\"",
				"\"There's a sandbar out on the flats when the tide's low. The rays like it. Now you know.\"",
				"\"Don't tell Wen. She'll put it on a chart.\""]},
		],
		"lines": {
			"0": ["Hm. New face. Fish face, though. Good.",
				"Don't strike when it nibbles. Wait for the dive. Patience is cheaper than bait.",
				"Big shadow, big fish. Small shadow, reel in and cast again. Nobody tells you that. I just did.",
				"That cat on the pier at night is Admiral. He is my cat. He does not know that.",
				"Rain pushes the big ones up the beach. Your record fish is out there on a wet day.",
				"Pier end, mornings. Mackerel run like gossip.",
				"I fished this bay fifty years. Know every rock by its first name.",
				"Tide goes out twice a day. Most people only notice once.",
				"Don't sell your best fish. Well. Sell it. But remember it."],
			"3": ["My boat was the Patience. Pulled up behind the lighthouse now.",
				"June, my wife, named her. She was the patient one. I just held the rod.",
				"Fog brings the pale koi to the rocks. Seen it four times in my life. Twice I forgot to cast.",
				"Ines kept the lanterns. I kept the fish. The town kept the rest. Then it all went quiet at once.",
				"Fern's brother fished with me. Good hands. Bad at staying put.",
				"Tuna come close to the rocks in the morning. They like the cold water off the point.",
				"I buy the same tea every week. Pip thinks it is loyalty. It is laziness. Same thing, at my age.",
				"Admiral eats tuna and nothing else. Expensive animal. Worth it.",
				"You hold the rod better now. Less like it owes you money."],
			"6": ["June died in the spring, nine years back. I stopped going out at dawn after.",
				"You remind me of me, before I got good at sulking.",
				"I watched that lantern come on. Stood on the pier with my hat off. Don't tell anyone.",
				"I told Fern her brother asked about her. Two years late. She threw a cabbage at me. Fair.",
				"Every morning I'll tell you what is biting. Old habit. June used to ask.",
				"When I'm gone, take the Patience's name board. Hang it somewhere with a view.",
				"Not going anywhere yet, mind. Just planning. Fishermen plan.",
				"Bigger fish surge harder. Let the line go slack when it pulls. Then take it back. Like an argument."],
			"9": ["Came out at dawn yesterday. Caught nothing. Best morning in years.",
				"The rod you've got is good. The hands are better. That's you.",
				"June would have liked you. She liked anyone who said sorry to the fish.",
				"Admiral sleeps on my porch now. On the porch. Progress.",
				"I've written down every spot I know. It's in a tin by the door. It's yours.",
				"The bay's lit up again. Thought I'd never see it. You did that, one fish at a time.",
				"Sit. Don't fish. Just sit. That's the last lesson. It's the hardest one.",
				"See you at the pier. Early. I'll bring tea."],
		}},

	"wen": {"name": "Wen", "species": "heron", "main": "b9c6d2", "accent": "3b4a5c", "role": "Lighthouse keeper",
		"about": "Forty. Came on a six-month contract to automate the lamp eight years ago and never did. Counts weather. Sleeps badly.",
		"home": "lighthouse", "routine": {"morning": "shop", "afternoon": "shop", "evening": "lighthouse", "night": "lighthouse"},
		"loves": ["shore:star_stone", "fish:lanternfish"], "likes": ["shore:moon_shell", "shore:glass_blue", "fish:squid"], "dislikes": ["fish:sardine"],
		"perks": [
			{"level": 2, "id": "weather_forecast", "value": 1.0, "text": "Wen tells you tomorrow's weather. It shows in the Notebook from 18:00."},
			{"level": 5, "id": "spark_bonus", "value": 1.0, "text": "Wen keeps the lantern log. Every finished request gives +1 extra spark."},
			{"level": 7, "id": "tide_chart", "value": 1.0, "text": "Wen drew you a tide chart. The clock shows when the next low tide starts."},
			{"level": 10, "id": "fog_bell", "value": 7.0, "text": "Wen rings the old fog bell again. A foggy day comes at least once a week."},
		],
		"events": [
			{"level": 4, "title": "Ines' List", "lines": [
				"Wen unrolls a stained map on the lighthouse table.",
				"\"Ines left this. Five lanterns, in order. Harbour, hill, the lamp, and two I cannot find.\"",
				"\"You are following her list without knowing it. That is a little eerie. I approve.\"",
				"\"I will keep looking for the other two. I have the nights for it.\""]},
			{"level": 8, "title": "The Gallery", "reward": {"item": "shore:star_stone", "n": 1}, "lines": [
				"Late at night Wen leads you up the lighthouse stairs to the gallery. The wind is cold and clean.",
				"\"I watched a comet from here last winter. Alone. I wished someone else had seen it.\"",
				"A streak of light crosses the bay and is gone.",
				"\"There. Now someone has.\" She gives you a star stone. \"Probably from that. I cannot prove it.\""]},
		],
		"lines": {
			"0": ["Ah. The person who keeps walking about at odd hours. Same.",
				"I keep the lighthouse. It does not need much keeping, dark.",
				"I count the weather. Clouds, wind, pressure. Tomorrow is always on its way. I like to know first.",
				"Mist on the water at sunset means fog by morning. Free tip. Most tips here are free. Pip's are not.",
				"I do not sleep much. The stars are very good company. They never ask how you are.",
				"Cotton and I play chess by letter. He has been thinking about one move since March.",
				"If you see a light on the hill at night, that is me with a telescope, not a ghost. Usually.",
				"The island has five lanterns. I have the map. I have had it for years. Nobody asked.",
				"I come to Pip's in the daytime for biscuits and conversation. Mostly biscuits."],
			"3": ["I came on a six-month contract to automate the lamp. That was eight years ago. The lamp is not automated.",
				"Ines taught me the old way. Wick, oil, mirror. She said machines do not know when someone is lost.",
				"I got into an observatory once. Did not go. Still not sure why. Starting to be.",
				"Blue sea glass is the colour of the sky twenty minutes after sunset. I timed it.",
				"Lantern fish rise when the harbour is lit. They know light better than we do.",
				"Disco sits on my steps every night, waiting for the beam. There is no beam. Yet.",
				"Moss tells me the weather. I tell Moss the weather. We are both usually right. We argue anyway.",
				"The fog bell has not rung since the lamp went out. I polish it on Sundays. Habit.",
				"Star stones fall out of the sky. Probably. I cannot prove it and I do not want to."],
			"6": ["My parents wanted a scientist. I am a scientist. I just live in a lighthouse. They count it as half.",
				"Sometimes I think I stayed because someone had to. Lately I think I stayed because I wanted to.",
				"Pip and I eat biscuits at three in the morning. We do not talk about it. It is the best friendship I have.",
				"If you are ever awake at night, the gallery door is open. Bring a coat.",
				"I wrote down every fog day for eight years. There is a pattern. There is also no pattern. Both are true.",
				"When the lamp turns again, I will cry. I am warning you so you can look away.",
				"I made you a tide chart. It is a napkin. It is accurate.",
				"You ask good questions. Then you go and check. That is all science is."],
			"9": ["There is a comet due next month. You are coming. It is not a question.",
				"I wrote to the observatory. I said thank you, but I have a lighthouse.",
				"You know the weather here as well as I do now. I am thrilled. And slightly threatened.",
				"Ines would have given you the keys. I am giving you the spare. Do not lose it. It is the only one.",
				"I sleep better now. Not much. Better.",
				"On foggy days I ring the bell. For you, and for whoever else is out there.",
				"Stars, tides, fog, cats. You learned all of it by looking.",
				"Goodnight, Mocha. Or good morning. With you it is hard to tell."],
		}},
}
