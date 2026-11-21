extends Node
## Data (autoload): all content tables. Pure data, no logic. Numbers follow docs/GDD.md.
## Spots: "pier", "beach", "rocks" (rocks needs lantern "harbour"). Slots: morning/afternoon/evening/night.

## Fish. size in cm [min, max]; rarity 1 common .. 4 legendary; weather [] = any; slots [] = any.
const FISH := {
	"sardine":   {"name": "Sardine",       "spots": ["pier", "beach"], "slots": [], "weather": [], "size": [8, 22],   "rarity": 1, "price": 15, "body": "a9c4d6", "fin": "6f8fa8"},
	"mackerel":  {"name": "Mackerel",      "spots": ["pier"], "slots": ["morning", "afternoon"], "weather": [], "size": [20, 45], "rarity": 1, "price": 25, "body": "7fb0a8", "fin": "3f6f78"},
	"sea_bream": {"name": "Sea Bream",     "spots": ["pier", "rocks"], "slots": ["morning", "evening"], "weather": [], "size": [25, 55], "rarity": 2, "price": 55, "body": "f2a9a0", "fin": "d97a70"},
	"flounder":  {"name": "Flounder",      "spots": ["beach"], "slots": [], "weather": [], "size": [18, 50], "rarity": 1, "price": 30, "body": "c9b08a", "fin": "9a7f5c"},
	"blowfish":  {"name": "Puffer",        "spots": ["pier"], "slots": ["afternoon"], "weather": ["sunny"], "size": [10, 30], "rarity": 2, "price": 70, "body": "f6e2a0", "fin": "d9b860"},
	"squid":     {"name": "Little Squid",  "spots": ["pier"], "slots": ["night"], "weather": [], "size": [12, 35], "rarity": 2, "price": 60, "body": "f6dce6", "fin": "e0a8c0"},
	"eel":       {"name": "Moray Eel",     "spots": ["rocks"], "slots": ["evening", "night"], "weather": [], "size": [50, 120], "rarity": 2, "price": 90, "body": "8f9a5c", "fin": "5f6a3c"},
	"tuna":      {"name": "Bluefin Tuna",  "spots": ["rocks"], "slots": ["morning"], "weather": [], "size": [80, 220], "rarity": 3, "price": 320, "body": "4f6fa0", "fin": "2f4f78"},
	"seahorse":  {"name": "Seahorse",      "spots": ["beach"], "slots": ["afternoon"], "weather": ["sunny", "cloudy"], "size": [5, 18], "rarity": 2, "price": 110, "body": "f4c070", "fin": "d99a40"},
	"crab":      {"name": "Shore Crab",    "spots": ["beach", "rocks"], "slots": [], "weather": [], "size": [6, 20], "rarity": 1, "price": 18, "body": "e8746a", "fin": "c4504a"},
	"octopus":   {"name": "Octopus",       "spots": ["rocks"], "slots": ["night"], "weather": [], "size": [30, 90], "rarity": 3, "price": 240, "body": "d98aa8", "fin": "b0607f"},
	"salmon":    {"name": "Salmon",        "spots": ["pier"], "slots": ["evening"], "weather": ["rain", "cloudy"], "size": [45, 90], "rarity": 2, "price": 120, "body": "f2a07a", "fin": "c97050"},
	"angelfish": {"name": "Angelfish",     "spots": ["rocks"], "slots": ["afternoon"], "weather": ["sunny"], "size": [10, 25], "rarity": 3, "price": 180, "body": "fff1a0", "fin": "7fc0e0"},
	"lanternfish": {"name": "Lantern Fish", "spots": ["pier"], "slots": ["night"], "weather": [], "size": [8, 20], "rarity": 3, "price": 260, "body": "bfe6ff", "fin": "fff1b8", "needs_lantern": "harbour"},
	"ghost_koi": {"name": "Ghost Koi",     "spots": ["rocks"], "slots": [], "weather": ["fog"], "size": [40, 80], "rarity": 4, "price": 900, "body": "f4f6fb", "fin": "c9d6f0"},
	"old_boot":  {"name": "Old Boot",      "spots": ["pier", "beach", "rocks"], "slots": [], "weather": [], "size": [26, 30], "rarity": 1, "price": 1, "body": "7a5a4c", "fin": "5a3f34", "junk": true},
}
const GOLD_CHANCE := 0.01
const GOLD_PRICE_MULT := 5

## Cats. haunts: slot -> spot name in Island (weather "rain" overrides with rain_spot when set).
## shy: needs trust from sitting before pets work. scares: riding/full-speed near it makes it run.
const CATS := {
	"biscuit":    {"name": "Mayor Biscuit", "main": "f6dcb4", "patch": "e39a62", "personality": "Bold",
		"haunts": {"morning": "pier", "afternoon": "shop", "evening": "pier", "night": "plaza"},
		"favourite": "fish:mackerel", "secret": "Follows anyone carrying a Mackerel.", "shy": false, "scares": false,
		"rumour": "A very official-looking cat inspects the pier every morning."},
	"tofu":       {"name": "Tofu", "main": "f7f3ee", "patch": "", "personality": "Lazy",
		"haunts": {"morning": "home", "afternoon": "plaza", "evening": "plaza", "night": "home"},
		"favourite": "treat:cream", "secret": "Naps on warm stones after noon.", "shy": false, "scares": false,
		"rumour": "Something white and round sleeps in the plaza all afternoon."},
	"disco":      {"name": "Disco", "main": "3a3550", "patch": "2a2540", "personality": "Curious",
		"haunts": {"evening": "lighthouse", "night": "lighthouse"},
		"favourite": "fish:squid", "secret": "Only out after dark. Loves the lighthouse beam.", "shy": true, "scares": true,
		"rumour": "Two green eyes by the lighthouse, only at night."},
	"pancake":    {"name": "Pancake", "main": "f2d3a6", "patch": "c9884d", "personality": "Bold",
		"haunts": {"morning": "shop", "afternoon": "shop", "evening": "beach"},
		"favourite": "treat:tuna_bites", "secret": "Waits by the shop door when Pip opens.", "shy": false, "scares": false,
		"rumour": "The shop has a doorman. He is a cat."},
	"marmalade":  {"name": "Marmalade", "main": "f2a35c", "patch": "d97a3a", "personality": "Grumpy",
		"haunts": {"morning": "hill", "afternoon": "hill", "evening": "hill"},
		"favourite": "treat:catnip", "secret": "Only accepts a treat once you have petted every other cat today.", "shy": true, "scares": true,
		"rumour": "An orange cat on the hill glares at everyone. Professionally."},
	"mochi":      {"name": "Mochi", "main": "fbe3ea", "patch": "", "personality": "Shy",
		"haunts": {"morning": "beach", "afternoon": "beach"}, "rain_spot": "shop",
		"favourite": "fish:sardine", "secret": "Hides under the shop awning when it rains.", "shy": true, "scares": true,
		"rumour": "A pink cat watches the waves. It runs from engines."},
	"pepper":     {"name": "Pepper", "main": "6e6a72", "patch": "4a4650", "personality": "Curious",
		"haunts": {"morning": "plaza", "afternoon": "pier", "evening": "shop", "night": "plaza"},
		"favourite": "fish:crab", "secret": "Investigates anything you drop on the pier.", "shy": false, "scares": false,
		"rumour": "A grey cat seems to be following your route."},
	"saffron":    {"name": "Saffron", "main": "f6e2a0", "patch": "e0b860", "personality": "Lazy",
		"haunts": {"afternoon": "home", "evening": "home"},
		"favourite": "treat:cream", "secret": "Sleeps on your porch if it is sunny.", "shy": false, "scares": false,
		"rumour": "Someone yellow keeps borrowing your porch."},
	"ghost":      {"name": "Fog", "main": "dfe4ee", "patch": "c4cbdc", "personality": "Shy",
		"haunts": {"morning": "lighthouse", "afternoon": "lighthouse", "evening": "lighthouse", "night": "lighthouse"},
		"weather_only": ["fog"], "favourite": "fish:ghost_koi", "secret": "Appears only on foggy days.", "shy": true, "scares": true,
		"rumour": "On foggy days, a pale cat by the lighthouse. Or is it?"},
	"captain":    {"name": "Captain", "main": "8f7a6a", "patch": "f7f3ee", "personality": "Bold",
		"haunts": {"morning": "hill", "evening": "pier", "night": "pier"}, "needs_lantern": "hill",
		"favourite": "fish:tuna", "secret": "Rides the night boat in. Prefers fish bigger than himself.", "shy": false, "scares": false,
		"rumour": "An old sea cat comes ashore when the hill lantern burns."},
}
const CAT_MAX_HEARTS := 5

## Shore items. where: "beach" (daily) or "flats" (low tide only).
const SHORE := {
	"shell_white": {"name": "White Shell", "where": "beach", "weight": 30, "price": 3, "color": "fbf3e6"},
	"shell_pink":  {"name": "Pink Scallop", "where": "beach", "weight": 18, "price": 6, "color": "f6b8c4"},
	"glass_green": {"name": "Green Sea Glass", "where": "beach", "weight": 12, "price": 10, "color": "9fd8b0"},
	"glass_blue":  {"name": "Blue Sea Glass", "where": "beach", "weight": 8, "price": 14, "color": "9cc8ef"},
	"driftwood":   {"name": "Driftwood", "where": "beach", "weight": 14, "price": 4, "color": "c9a882"},
	"star_stone":  {"name": "Star Stone", "where": "flats", "weight": 3, "price": 200, "color": "ffe08a"},
	"moon_shell":  {"name": "Moon Shell", "where": "flats", "weight": 5, "price": 60, "color": "e8e4ff"},
	"bottle":      {"name": "Message Bottle", "where": "beach", "weight": 1, "price": 0, "color": "bfe3ee", "bottle": true},
}
const SHORE_BEACH_DAILY := 14
const SHORE_FLATS_DAILY := 6
const SHORE_GOLD_CHANCE := 0.02

## Pip's shop.
const SHOP := {
	"treat:tuna_bites": {"name": "Tuna Bites", "price": 25, "kind": "treat"},
	"treat:catnip":     {"name": "Catnip Sprig", "price": 40, "kind": "treat"},
	"treat:cream":      {"name": "Cream Cup", "price": 60, "kind": "treat"},
	"rod:2":            {"name": "Sturdy Rod", "price": 400, "kind": "rod", "level": 2, "desc": "Longer bite window, calmer fish."},
	"rod:3":            {"name": "Lighthouse Rod", "price": 1500, "kind": "rod", "level": 3, "desc": "Rare fish bite more often."},
	"cos:scarf_mint":   {"name": "Mint Scarf", "price": 150, "kind": "cosmetic", "slot": "scarf", "color": "6fc2b6"},
	"cos:scarf_berry":  {"name": "Berry Scarf", "price": 150, "kind": "cosmetic", "slot": "scarf", "color": "c4506a"},
	"cos:cap":          {"name": "Fisher's Cap", "price": 300, "kind": "cosmetic", "slot": "hat", "color": "f2c14e"},
	"cos:paint_peach":  {"name": "Peach Moped Paint", "price": 800, "kind": "cosmetic", "slot": "paint", "color": "f6b89a"},
}
const ROD := {
	1: {"bite_window": 0.7, "surge": 1.0, "rare_bonus": 0.0},
	2: {"bite_window": 0.85, "surge": 0.8, "rare_bonus": 0.0},
	3: {"bite_window": 0.9, "surge": 0.75, "rare_bonus": 0.5},
}

## Requests. kind: "fish_size" (any fish >= cm), "fish" (species), "shore" (count of an item), "gold" (any gold item).
const REQUEST_TEMPLATES := [
	{"kind": "fish_size", "who": "Maple", "text": "Maple wants any fish over %d cm.", "min_cm": [30, 60], "reward": [80, 160]},
	{"kind": "fish", "who": "Pip", "text": "Pip needs a %s for the shop window.", "reward": [60, 140]},
	{"kind": "shore", "who": "Cotton", "text": "Cotton needs %d %s for a mobile.", "count": [2, 4], "reward": [40, 90]},
	{"kind": "shore", "who": "Fern", "text": "Fern is collecting %d %s. Don't ask.", "count": [3, 5], "reward": [50, 100]},
	{"kind": "gold", "who": "Pip", "text": "Pip will pay a fortune for anything gold.", "reward": [300, 300]},
]
const REQUESTS_PER_DAY := 3

## Lanterns.
const LANTERNS := {
	"harbour": {"name": "Harbour Lantern", "cost": 10, "spot": "lantern_harbour", "unlocks": "The lighthouse rocks are open for fishing. Lantern fish gather at the pier at night."},
	"hill":    {"name": "Hill Lantern", "cost": 25, "spot": "lantern_hill", "unlocks": "The hill path is open. Night market on Fridays. Someone old comes ashore."},
}
## Sparks earned per event.
const SPARK := {"new_fish": 1, "new_cat_fact": 0, "cat_friend": 3, "request": 2, "record": 1, "new_shore": 1}
