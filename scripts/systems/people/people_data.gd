extends RefCounted
## Fallback townsfolk table used until Data.PEOPLE exists (same shape, so the design director can
## copy it over). People system reads Data.get("PEOPLE") first and only falls back to this.
##
## Shape per person:
##   name, species (bear/cat/fox/sheep/frog/walrus), main / accent / extra (hex colours), role,
##   outfit (apron/scarf/beret/cap/captain), scale, home (spot), routine {slot: spot},
##   loves / likes / dislikes (bag item ids), lines {"low": 0-3, "mid": 4-7, "high": 8-10},
##   react {love, like, neutral, dislike}, events {4: [lines], 8: [lines]},
##   perks {level: [{id, value, text}]}.
## A line starting with "Mocha: " is spoken by Mocha.

const POINTS := {"talk": 10, "love": 50, "like": 25, "neutral": 5, "dislike": 0}

const PEOPLE := {
	"pip": {
		"name": "Pip", "species": "fox", "main": "ec955a", "accent": "f2c14e", "extra": "fff3e2",
		"role": "Runs the general store", "outfit": "apron", "scale": 0.86,
		"home": "shop", "shop_hours": [7, 20],
		"routine": {"morning": "shop_counter", "afternoon": "shop_counter", "evening": "plaza", "night": "shop"},
		"loves": ["shore:star_stone", "fish:angelfish"],
		"likes": ["shore:glass_blue", "shore:shell_pink", "fish:seahorse"],
		"dislikes": ["fish:old_boot"],
		"lines": {
			"low": [
				"Welcome to Lantern Bay. Population: small. Gossip: enormous.",
				"If it fits through the door, I will buy it. If it does not, we can talk.",
				"You look like someone who used to answer emails at midnight. It wears off here.",
				"Biscuit thinks he runs this town. Do not tell him otherwise, he has a hat.",
			],
			"mid": [
				"I keep a jar for lantern oil. It is mostly buttons now, but the intention is there.",
				"Business is good on rainy days. Everyone wants a reason to stand under my awning.",
				"Maple says I talk too much. Maple says that every morning. It is our tradition.",
				"I put your name in the ledger. Under 'regulars'. Do not let it go to your head.",
			],
			"high": [
				"The lanterns used to make the whole bay look like a birthday cake. You are getting us there.",
				"I saved you the good paper bags. Do not ask what makes them good. They just are.",
				"You know, the shop used to close at six. Then you moved in.",
			],
		},
		"react": {
			"love": ["Oh. Oh, that is going in the window. Not for sale. Ever.", "You are going to make me cry on a work day."],
			"like": ["Ooh, nice. I know exactly which shelf this goes on.", "Thank you. I will pretend to be cool about it."],
			"neutral": ["That is kind. Weird, but kind.", "I will find a place for it. Somewhere."],
			"dislike": ["Is this a test? It smells like a test.", "I am going to accept this and then quietly put it outside."],
		},
		"events": {
			4: [
				"Can I show you something? Behind the counter. No, lower.",
				"This was my grandmother's lantern. First one ever lit on the island, she said.",
				"Mocha: It still has a wick.",
				"It does. I never had the nerve to light it. Felt like it should be a big occasion.",
				"Maybe when the harbour lantern is back. You will come, right?",
			],
			8: [
				"I did the books last night. We are not rich. But we are not worried, either.",
				"That has not been true for a long time. Then a burnt-out bear moved in and started selling me sardines.",
				"Mocha: I am not burnt out anymore.",
				"I know. It shows. You walk slower. In a good way.",
				"Anyway. From now on you get the friends price. Do not tell Maple, she will want it too.",
			],
		},
		"perks": {
			3: [{"id": "shop_discount", "value": 0.10, "text": "Pip gives you 10% off everything in the shop."}],
			6: [{"id": "gold_sell_bonus", "value": 0.25, "text": "Pip pays 25% more yen for anything gold."}],
			9: [{"id": "shop_discount", "value": 0.15, "text": "The friends price: 15% off everything in Pip's shop."}],
		},
	},
	"maple": {
		"name": "Maple", "species": "bear", "main": "b0673f", "accent": "d9564a", "extra": "f0d2b4",
		"role": "Fishes off the pier, every day, in any weather", "outfit": "cap", "scale": 1.0,
		"home": "pier",
		"routine": {"morning": "pier_end", "afternoon": "beach", "evening": "pier", "night": "plaza"},
		"loves": ["fish:tuna", "fish:salmon"],
		"likes": ["fish:mackerel", "fish:sea_bream", "fish:eel"],
		"dislikes": ["treat:catnip"],
		"lines": {
			"low": [
				"You are standing where the fish like to look. Move a little left.",
				"Patience is just waiting with good posture.",
				"A nibble is the fish asking a question. Do not answer too fast.",
				"Rain makes the big ones brave. Remember that.",
			],
			"mid": [
				"I have fished this pier for twenty years. The pier has fished me back, some days.",
				"Pip says I talk too little. Pip says that every morning. It is our tradition.",
				"When the line goes tight, breathe out. The fish can feel you panic.",
				"Low tide at dawn. Bring a flask. You will see.",
			],
			"high": [
				"You have good hands now. I noticed. Do not make it weird.",
				"Some days I do not even cast. I just sit. You taught me that, I think.",
				"There is a tuna out by the rocks with my name on it. Literally. I wrote it on a buoy.",
			],
		},
		"react": {
			"love": ["Look at the size of it. Look at it. I need to sit down.", "That is a real fish. You are a real fisher. Thank you."],
			"like": ["Good fish. Clean catch. Thank you.", "This is dinner. You just made dinner happen."],
			"neutral": ["Hm. Thank you.", "I will find a use for it."],
			"dislike": ["The cats will follow me home now. Thanks.", "No. But I appreciate the thought. Barely."],
		},
		"events": {
			4: [
				"Sit. Not there, there. The board that does not creak.",
				"My father taught me on this pier. He said the bay keeps a list of who is patient.",
				"Mocha: Am I on it?",
				"You are on the waiting list. That is further than most.",
				"Here. Hold the line a moment. Feel that? That is the tide breathing.",
			],
			8: [
				"I lost a big one here, years ago. Biggest I ever hooked. I let it go on purpose.",
				"Mocha: Why?",
				"It was old. It had earned the bay. Some things you just say hello to.",
				"I have not told anyone that. Pip would put it on a sign.",
				"You keep that to yourself. And keep your line slack in a surge. That one is free.",
			],
		},
		"perks": {
			2: [{"id": "bite_window_bonus", "value": 0.1, "text": "Maple's tip: you get an extra 0.1 seconds to react when a fish bites."}],
			5: [{"id": "big_fish_bonus", "value": 0.10, "text": "Maple showed you her spots: the fish you catch run about 10% bigger."}],
			9: [{"id": "rare_fish_bonus", "value": 0.10, "text": "Maple's secret bait: rare fish bite a little more often."}],
		},
	},
	"cotton": {
		"name": "Cotton", "species": "sheep", "main": "fbf5ea", "accent": "b8a0dc", "extra": "8a6e62",
		"role": "Makes wind mobiles out of whatever the sea gives back", "outfit": "scarf", "scale": 0.95,
		"home": "plaza",
		"routine": {"morning": "board", "afternoon": "plaza", "evening": "beach", "night": "plaza"},
		"loves": ["shore:glass_blue", "shore:moon_shell"],
		"likes": ["shore:glass_green", "shore:shell_pink", "shore:driftwood"],
		"dislikes": ["fish:eel"],
		"lines": {
			"low": [
				"Hello. Sorry. I was counting colours in the sky. It is a lot of blue today.",
				"The wind is louder here than in the city. But it says nicer things.",
				"I make mobiles. Shells, glass, string. They hang, they turn, they make the room feel less alone.",
				"Have you seen the green glass on the beach? It is like someone dropped a sea on the sea.",
			],
			"mid": [
				"I sold one mobile to a tourist once. I still think about where it is.",
				"Pip lets me hang my work in the shop window. Fern says it looks like a jellyfish. Fern means it well.",
				"If you find blue glass, hold it up to the sun. Just once. You will understand everything about me.",
				"I knit too. Everyone gets a scarf eventually. It is not optional.",
			],
			"high": [
				"I am making one for your porch. No peeking. Well, peek a little.",
				"I used to think I needed a big studio. Turns out I needed a small island.",
				"You hum when you comb the shore. It is very bad. Please never stop.",
			],
		},
		"react": {
			"love": ["Oh. It is perfect. It is exactly the colour I could not find.", "I am going to build a whole piece around this. Around you, sort of."],
			"like": ["This will catch the light nicely. Thank you.", "Into the jar of treasures it goes."],
			"neutral": ["Thank you. I will think about where it goes.", "It has a nice shape. Hm."],
			"dislike": ["It is looking at me. Why is it looking at me.", "That is... wet. Thank you."],
		},
		"events": {
			4: [
				"Can you hold this end? Higher. Now turn a little. Stop.",
				"There. When the wind comes from the bay, the blue piece lines up with the lighthouse.",
				"Mocha: You planned that?",
				"For three weeks. Nobody else noticed. You did.",
				"Here, a bit of string. Hang something you like on it. That is the whole craft.",
			],
			8: [
				"I finished it. Your mobile. It is on your porch.",
				"Every piece came from the shore you walk every morning. So it is sort of yours already.",
				"Mocha: It sounds like the bay when it turns.",
				"That is the idea. So you are never far from it, even indoors.",
				"Oh, and I told the tide about you. It leaves better things now. Do not ask how.",
			],
		},
		"perks": {
			3: [{"id": "shore_gold_bonus", "value": 0.02, "text": "Cotton taught you to spot the glint: gold shore items turn up 2% more often."}],
			6: [{"id": "shore_extra", "value": 2.0, "text": "Two extra shore items wash up every morning, because Cotton told the tide."}],
			9: [{"id": "request_bonus", "value": 0.20, "text": "Cotton spreads the word: requests pay 20% more yen."}],
		},
	},
	"fern": {
		"name": "Fern", "species": "frog", "main": "9fd08a", "accent": "c4506a", "extra": "f4f0c8",
		"role": "Collects things. Has a system. Will not explain the system", "outfit": "beret", "scale": 0.9,
		"home": "flats",
		"routine": {"morning": "flats", "afternoon": "beach", "evening": "flats", "night": "pier"},
		"loves": ["fish:old_boot", "shore:bottle"],
		"likes": ["shore:driftwood", "shore:shell_white", "fish:crab"],
		"dislikes": ["treat:cream"],
		"lines": {
			"low": [
				"Do not step there. That is item four hundred and twelve. It is a pebble. It matters.",
				"Low tide is when the bay shows you its pockets.",
				"I am not strange. I am thorough.",
				"Someone threw a perfectly good boot into the sea. I will be finding out who.",
			],
			"mid": [
				"My collection has a catalogue. The catalogue has a catalogue.",
				"Cotton makes things pretty. I make things organised. Together we are almost a museum.",
				"The flats at dawn smell like old pennies and new beginnings. Write that down.",
				"If you find a bottle with a note, read it twice. The second time it says something else.",
			],
			"high": [
				"I have given you a shelf. In the collection. It is labelled 'Mocha'. It is mostly empty, by design.",
				"You notice things. That is rare. Rarer than a moon shell.",
				"I was going to leave the island once. Then the tide brought in a boot. Priorities.",
			],
		},
		"react": {
			"love": ["Do you know what this is? This is item number one of a whole new category.", "You understand me. That is alarming. Thank you."],
			"like": ["Catalogued. Filed. Treasured, quietly.", "Good find. Excellent provenance."],
			"neutral": ["Interesting. I will need to think about which box.", "Accepted. Pending review."],
			"dislike": ["This is food. I do not collect food. Anymore.", "No. Absolutely no. But thank you for trying."],
		},
		"events": {
			4: [
				"Mocha. Come. Quietly. Look under the third rock.",
				"That spiral? That is a moon shell trail. They only move when nobody is watching.",
				"Mocha: We are watching.",
				"Yes, which is why it is not moving. Science is mostly waiting.",
				"I am telling you because you are allowed to know now. Low tide. Mornings and evenings.",
			],
			8: [
				"I need to show you the first item. Item number one. Nobody has seen it.",
				"It is a bottle. With a note from someone who lived here long ago.",
				"It says: 'When the lights come back, the bay will remember everyone.'",
				"Mocha: Do you think it is true?",
				"I think someone believed it enough to throw it in the sea. That is close enough for me.",
			],
		},
		"perks": {
			3: [{"id": "flats_double", "value": 1.0, "text": "Fern showed you the flats' pockets: twice as many things to find at low tide."}],
			6: [{"id": "bottle_bonus", "value": 1.0, "text": "Message bottles wash up twice as often. Fern has opinions about currents."}],
		},
	},
	"moss": {
		"name": "Captain Moss", "species": "walrus", "main": "a3897a", "accent": "3f4f78", "extra": "f6f1e6",
		"role": "Retired sea captain. Keeps the lighthouse and the weather", "outfit": "captain", "scale": 1.12,
		"home": "lighthouse",
		"routine": {"morning": "pier", "afternoon": "lighthouse", "evening": "pier_end", "night": "lighthouse"},
		"loves": ["fish:octopus", "fish:squid"],
		"likes": ["fish:sardine", "fish:flounder", "treat:tuna_bites"],
		"dislikes": ["shore:glass_green"],
		"lines": {
			"low": [
				"Ahoy. That is not a greeting, that is a warning. Mind the rope.",
				"The sea does not care about you. That is what I like about it.",
				"Red sky at night, Moss stays in. Red sky in the morning, Moss stays in. I am retired.",
				"Fog is just the sea thinking out loud.",
			],
			"mid": [
				"I sailed past forty islands. Stopped at this one because the cats seemed to expect me.",
				"Watch the gulls. If they sit on the water, rain by noon. If they sit on Pip's roof, Pip left the window open.",
				"Every lantern on this island was lit by hand once. It can be done again.",
				"Your knots are getting better. I have been watching. Captains watch.",
			],
			"high": [
				"I kept a logbook for thirty years. Lately it is mostly entries about you. Good ones.",
				"The lighthouse feels less lonely with a bear about. Do not repeat that.",
				"When the last lantern comes back, I will ring the old bell. You will hear it from anywhere.",
			],
		},
		"react": {
			"love": ["Now that is a proper sea creature. You have my respect, sailor.", "Ha. Takes me back. Thank you, truly."],
			"like": ["Good. Honest fish. Thank you.", "That will do for supper. That will do nicely."],
			"neutral": ["Hm. Aye. Thank you.", "I will put it with the other mysteries."],
			"dislike": ["Green glass is bad luck on a ship. I am not on a ship. Still.", "No. But I will not hold it against you. Much."],
		},
		"events": {
			4: [
				"Come up to the lamp room sometime. Mind the stairs, there are one hundred and nine. I counted. Twice.",
				"From up here you can see where the lanterns used to be. Five dark spots, like a map nobody reads.",
				"Mocha: We are going to light them.",
				"Aye. I believe you. That is new for me, believing people.",
				"Here: I will tell you each morning what the sea is planning. Old habit.",
			],
			8: [
				"I am going to tell you why I stopped sailing.",
				"One night the lighthouse here was dark, and I nearly lost my ship on the rocks. Biscuit's grandfather barked me in. A cat. Barked.",
				"So I stayed, to keep the light. And then the lights went out anyway.",
				"Mocha: Not for long.",
				"No. Not for long. Thank you, sailor. Truly.",
			],
		},
		"perks": {
			2: [{"id": "forecast", "value": 1.0, "text": "Every morning Captain Moss tells you which rare fish is likely to bite."}],
			6: [{"id": "rare_fish_bonus", "value": 0.05, "text": "Moss shares his charts: rare fish bite a little more often."}],
		},
	},
}
