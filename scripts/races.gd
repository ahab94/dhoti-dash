extends RefCounted
## The races, as data. Each race is one of Chacha Jee's errands.
##
## Keys:
##   name, errand      title and the briefing shown before the start
##   win_line          shown when Chacha finishes in the top three
##   difficulty        0..1, scales rival speed, aggression and skill
##   rivals            ids from rider.gd ROSTER, in grid order
##   aunty             true: a rishta aunty on a scooty chases Chacha
##   seed              fixes the scattered hazards and scenery
##   road              [[segments, curve, hill], ...]; one segment is 200 units.
##                     curve: negative bends left, about ±2 gentle, ±5 sharp.
##                     hill: height change over the section (± 1500 is big)
##   scatter           {kind: how many}, dropped at seeded random spots
##   events            [[kind, segment, x], ...] placed by hand
##   boards            roadside billboard texts, in order
##
## Hazard kinds live in hazard.gd. "ball" also puts cricket kids on the verge.

const RACES := [
	{
		"name": "Dahi Before Dark",
		"errand": "The dairy shuts at six. Chachi wants dahi.\nFailure is not an option. Neither is a taxi.",
		"win_line": "Dahi secured. Chachi is... almost impressed.",
		"difficulty": 0.0,
		"rivals": ["bablu", "pappu", "chintu"],
		"aunty": false,
		"seed": 11,
		"road": [[120, 0, 0], [140, 2, 0], [100, 0, 400], [160, -3, -400], [120, 0, 0],
			[160, 3, 0], [120, 0, 600], [140, -2, -600], [140, 0, 0]],
		"scatter": {"pothole": 12, "puddle": 5, "cow": 3, "hens": 2, "bricks": 2, "chai": 3},
		"events": [["jalebi", 600, 0.0]],
		"boards": ["PEHLWAN TENT HOUSE: Weddings, Parties, Cricket",
			"HAKEEM JEE: Cure for everything except Monday",
			"TAILOR: Ready by Tuesday*  (*some Tuesday)",
			"SLOW DOWN: Buffalo has right of way"],
	},
	{
		"name": "The Bank Lunch Break",
		"errand": "The pension window closes for lunch at one.\nLunch lasts until three. Sometimes until Thursday.",
		"win_line": "Pension collected! The clerk looked up from his paratha.",
		"difficulty": 0.05,
		"rivals": ["pappu", "bablu", "chintu", "bunty"],
		"aunty": false,
		"seed": 22,
		"road": [[100, 0, 0], [160, -3, 0], [120, 0, 800], [100, 2, 0], [160, 0, -800],
			[140, 4, 0], [120, 0, 0], [160, -2, 500], [140, 0, -500], [100, 0, 0]],
		"scatter": {"pothole": 12, "puddle": 5, "buffalo": 3, "cow": 3, "goats": 1, "bullock": 2, "dog": 2, "breaker": 3, "chai": 3, "jalebi": 2, "ganna": 1},
		"events": [],
		"boards": ["BANK: Lunch 1 to 3. Also 11 to 1.",
			"LEARN ENGLISH IN 7 DAYS (or 7 years)",
			"PEHLWAN GYM: Members since 1971",
			"NO PARKING  (parking here)"],
	},
	{
		"name": "Mohalla Cricket Final",
		"errand": "The street final starts at four. Chacha is the umpire.\nNobody starts without the umpire. They will try.",
		"win_line": "Umpire arrives! Finger raised. Everyone is OUT.",
		"difficulty": 0.25,
		"rivals": ["pappu", "bablu", "chintu", "bunty", "guddu"],
		"aunty": false,
		"seed": 33,
		"road": [[100, 0, 0], [140, 3, 0], [140, 0, 600], [140, -4, 0], [100, 0, -600],
			[160, 2, 0], [140, 0, 0], [140, -3, 700], [140, 0, -700], [100, 0, 0]],
		"scatter": {"pothole": 12, "puddle": 4, "buffalo": 2, "cow": 2, "dog": 2, "hens": 2, "thela": 1, "donkey": 1, "chai": 3, "jalebi": 2, "lauki": 1, "ganna": 1},
		"events": [["ball", 260, 0.0], ["ball", 300, 0.3], ["ball", 700, 0.6], ["ball", 740, 0.1],
			["ball", 1100, 0.5], ["ball", 1140, 0.8]],
		"boards": ["BALL IN HOUSE = OUT. Glass broken = DOUBLE OUT",
			"CHAMPION BATS: Tape included",
			"MOBILE REPAIR: We fix everything except your heart",
			"UMPIRE DECISION IS FINAL (unless he is a relative)"],
	},
	{
		"name": "Rishta Aunty Season",
		"errand": "Chacha's grandson needs his lunch tiffin.\nWarning: a rishta aunty has been spotted. She has photos.",
		"win_line": "Tiffin delivered. Aunty's photos remain unseen. Victory.",
		"difficulty": 0.45,
		"rivals": ["pappu", "chintu", "bunty", "guddu", "bablu"],
		"aunty": true,
		"seed": 44,
		"road": [[100, 0, 0], [160, -3, 0], [120, 2, 900], [140, 0, -900], [160, 4, 0],
			[120, 0, 0], [160, -4, 400], [120, 0, -400], [160, 2, 0], [100, 0, 0]],
		"scatter": {"pothole": 14, "puddle": 5, "buffalo": 3, "cow": 2, "goats": 1, "dog": 2, "tractor": 1, "rickshaw": 3, "breaker": 3, "chai": 4, "jalebi": 2, "ganna": 1, "lauki": 1},
		"events": [],
		"boards": ["RISHTA BUREAU: Doctors and Engineers ONLY",
			"BEAUTY PARLOUR: Miracles from 9 to 5",
			"AUNTY CROSSING: Do not make eye contact",
			"TUITION CENTRE: 110% guaranteed"],
	},
	{
		"name": "The Baraat Is Coming",
		"errand": "Chacha is late for his nephew's wedding.\nThe baraat took the same road. With a band. And a horse.",
		"win_line": "Made it! Just in time for the food. The only part that matters.",
		"difficulty": 0.45,
		"rivals": ["pappu", "chintu", "bunty", "guddu", "tinku"],
		"aunty": false,
		"seed": 55,
		"road": [[100, 0, 0], [140, 3, 0], [160, 0, 700], [140, -4, -700], [120, 0, 0],
			[160, 4, 0], [140, 0, 800], [120, -2, -800], [160, 3, 0], [140, 0, 0], [100, 0, 0]],
		"scatter": {"pothole": 12, "puddle": 4, "buffalo": 3, "cow": 3, "goats": 2, "bullock": 2, "dog": 3, "rickshaw": 2, "breaker": 3, "chai": 5, "jalebi": 2, "ganna": 1, "lauki": 1},
		"events": [["baraat", 420, 0.0], ["baraat", 900, 0.5], ["baraat", 1320, 0.25]],
		"boards": ["PEHLWAN TENT HOUSE: Now with extra loud speakers",
			"BAND MASTER: We play ONE song. Very well.",
			"CATERING: Biryani for 500 (serves 50 uncles)",
			"DANCING UNCLES AHEAD: Reduce speed"],
	},
	{
		"name": "Last Date For The Bill",
		"errand": "Today is the last date for the electricity bill.\nThe queue is two kilometres long. So is Master Jee's grudge.",
		"win_line": "Bill paid! The fan may now spin. Master Jee demands a rematch.",
		"difficulty": 0.85,
		"rivals": ["master", "tinku", "guddu", "bunty", "chintu", "pappu"],
		"aunty": true,
		"seed": 66,
		"road": [[100, 0, 0], [140, -4, 0], [140, 0, 900], [120, 4, -400], [140, 0, -500],
			[160, -3, 0], [140, 3, 600], [120, 0, -600], [160, -4, 0], [140, 0, 0], [120, 2, 0], [100, 0, 0]],
		"scatter": {"pothole": 14, "puddle": 4, "buffalo": 4, "cow": 4, "goats": 2, "dog": 4, "tractor": 2, "bullock": 1, "thela": 1, "hens": 2, "bricks": 2, "rickshaw": 2, "breaker": 4, "chai": 3, "jalebi": 1, "ganna": 2, "lauki": 1},
		"events": [["ball", 500, 0.2], ["ball", 540, 0.7], ["baraat", 1000, 0.6]],
		"boards": ["BILL OFFICE: Window 3 of 1 is open",
			"WIRE EXPERT: All wires are one wire",
			"GENERATORS: Louder than your neighbour's",
			"LAST DATE IS TODAY. It was also yesterday."],
	},
]


static func count() -> int:
	return RACES.size()


static func get_race(i: int) -> Dictionary:
	return RACES[i]
