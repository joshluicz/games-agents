--!strict
-- The chrome emoji dictionary (UI direction §2 "The emoji rules", rule 5; Joshua, memory-20261117-007: "not to
-- remove the emojis, but to use them correctly"). ONE IDEA, ONE EMOJI; ONE EMOJI, ONE IDEA: every emoji the chrome
-- uses is named here once, and no emoji appears twice. Panels read `Icons.Unit.Cash`, never a typed "💰"
-- (tests/uirules `TypedEmoji`). A LIBRARY with no requires and no Roblox APIs: Lune specs load it as it is
-- (tests/EmojiRules.spec).
--
-- The five roles (the doc's table). Emoji are the game's art, so they are NOUNS. They are never punctuation.
--   Art     the thing itself (an item, a case, a tool, a station, an ability, a room). It comes from
--           shared/Data/* (`Icon`), never from here and never typed into a UI string. Alone in a Kit.artTile
--   Door    the icon of a place: on its HUD rail plate and on its tab only, with its word under it
--   Unit    what a number counts, glued in front of its number: Icons.unit("Cash", "300") = "💰 300"
--   State   🔒 locked · ✅ done · 💤 resting · ⏳ waiting: a small badge on the corner of the art tile
--           (Kit.setState), or alone in place of a button's label. Never in front of a sentence
--   Party   🎉 and friends: Celebrate, a reward toast, the Day Report. Nowhere else
-- Mark is the two drawn glyphs the chrome needs that are not nouns: the close ✖ and "again" 🔁.
--
--   Icons.Door.Shop ...        Shop · Nurses · Book · Gifts · Goals · Mail · Badges · Top · Settings · Branches ·
--                              Agency · Market · Lift · Odds
--   Icons.Unit.Cash ...        Cash · Stars · Level (the hospital level) · Tree (tree points) · Cards
--   Icons.State.Locked ...     Locked · Done · Resting · Waiting
--   Icons.Status.Day ...       Day · Night · Golden (the HUD's status lines: one icon each)
--   Icons.Party.Yay ...        Yay · Sparkle
--   Icons.Mark.Close ...       Close · Again
--   Icons.RETIRED              the collision losers: emoji -> the entry that won. Typing one in a UI file is a
--                              TypedEmoji fault too (🏙️ -> Unit.Level, 📔 📕 -> Door.Book, 📭 💌 -> Door.Mail,
--                              🔄 -> Mark.Again)
--   Icons.unit(kind, amount)   "💰 300": the Unit glued to its number (kind is a key of Icons.Unit; amount is
--                              already formatted text or a number). An unknown kind gives the amount alone
--   Icons.level(level, name?)  "🏥 Lv 1" · "🏥 Lv 1 Clinic": THE level badge text (the HUD, the Shop gates)
--   Icons.needs(level)         "Needs 🏥 Lv 3": THE gate note (one wording everywhere)
--   Icons.list()               every chrome emoji as { { Role, Name, Emoji } } (for the specs)
--   Icons.clusters(text)       the emoji in a string, one entry per drawn emoji (a ZWJ family such as 👩‍⚕️ is one)
--   Icons.count(text)          how many emoji a string draws
--   Icons.words(text)          the string without its emoji, spaces tidied: "👩‍⚕️ Team" -> "Team" (Kit.panel and
--                              Modal use it so a title is words only, whatever a caller passes)
--
-- THE COLLISION WINNERS (doc §7.3; Claude's proposals as written there, memory-20261117-007): the hospital level
-- is 🏥 only · Book is 📖 only · Mail is 📬 only · again is 🔁 only · 🏢 is Branches only (the Agency gets its own
-- door, 💼) · ⭐ is Stars only (MAX is the word "MAX"; a mini-game target is a drawn mark).
-- Every emoji here is one Roblox can draw (tests/Emoji.spec's no-glyph list; EmojiRules.spec checks it).

local Icons = {}

Icons.Door = table.freeze({
	Shop = "🛒",
	Nurses = "👩‍⚕️",
	Book = "📖",
	Gifts = "🎁",
	Goals = "🎯",
	Mail = "📬",
	Badges = "🏅",
	Top = "🏆",
	Settings = "⚙️",
	Branches = "🏢",
	Agency = "💼",
	Market = "🏷️",
	Lift = "↕️",
	Odds = "🎲",
})

Icons.Unit = table.freeze({
	Cash = "💰",
	Stars = "⭐",
	Level = "🏥",
	Tree = "🌳",
	Cards = "🃏",
})

Icons.State = table.freeze({
	Locked = "🔒",
	Done = "✅",
	Resting = "💤",
	Waiting = "⏳",
})

Icons.Status = table.freeze({
	Day = "☀️",
	Night = "🌙",
	Golden = "🌟",
})

Icons.Party = table.freeze({
	Yay = "🎉",
	Sparkle = "✨",
})

Icons.Mark = table.freeze({
	Close = "✖",
	Again = "🔁",
})

-- The roles in reading order (Icons.list walks them).
Icons.ROLES = table.freeze({ "Door", "Unit", "State", "Status", "Party", "Mark" })

-- The collision losers and who won (a path into this table).
Icons.RETIRED = table.freeze({
	["🏙️"] = "Unit.Level",
	["📔"] = "Door.Book",
	["📕"] = "Door.Book",
	["📭"] = "Door.Mail",
	["💌"] = "Door.Mail",
	["🔄"] = "Mark.Again",
})

function Icons.unit(kind: string, amount: string | number): string
	local icon = (Icons.Unit :: any)[kind]
	if type(icon) ~= "string" then
		return tostring(amount)
	end
	return icon .. " " .. tostring(amount)
end

function Icons.level(level: number, name: string?): string
	local text = Icons.Unit.Level .. " Lv " .. tostring(level)
	if type(name) == "string" and name ~= "" then
		text ..= " " .. name
	end
	return text
end

function Icons.needs(level: number): string
	return "Needs " .. Icons.level(level)
end

function Icons.list(): { { Role: string, Name: string, Emoji: string } }
	local out = {}
	for _, role in Icons.ROLES do
		local names = {}
		for name in (Icons :: any)[role] do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in names do
			table.insert(out, { Role = role, Name = name, Emoji = (Icons :: any)[role][name] })
		end
	end
	return out
end

-- Reading emoji out of UTF-8 text. An emoji is one "cluster": a base code point plus what rides on it (the FE0F
-- picture selector, a skin tone, a keycap, and anything joined by a zero-width joiner).
local ZWJ, PICTURE, KEYCAP = 0x200D, 0xFE0F, 0x20E3

local function inRange(cp: number, lo: number, hi: number): boolean
	return cp >= lo and cp <= hi
end

-- Always drawn as a picture.
local function isPicture(cp: number): boolean
	return inRange(cp, 0x1F000, 0x1FAFF) -- the emoji planes
		or inRange(cp, 0x2600, 0x27BF) -- symbols and dingbats (☀ ⚙ ✅ ✨ ✖)
		or inRange(cp, 0x2B00, 0x2BFF) -- ⭐ ⬆
		or inRange(cp, 0x2300, 0x23FF) -- ⏳ ⏭ ⏱
end

-- Text symbols that turn into a picture only with FE0F after them (↕️ ▶️ ‼️ ℹ️).
local function isPictureWithSelector(cp: number): boolean
	return inRange(cp, 0x2190, 0x21FF)
		or inRange(cp, 0x25A0, 0x25FF)
		or inRange(cp, 0x2000, 0x206F)
		or inRange(cp, 0x2100, 0x214F)
		or inRange(cp, 0x2900, 0x297F)
		or inRange(cp, 0x3000, 0x303F)
		or inRange(cp, 0x3290, 0x329F)
		or cp == 0xA9
		or cp == 0xAE
end

local function rides(cp: number): boolean
	return cp == PICTURE or cp == KEYCAP or inRange(cp, 0x1F3FB, 0x1F3FF) or inRange(cp, 0xE0020, 0xE007F)
end

type Span = { From: number, To: number } -- byte positions of one emoji in the text

local function spans(text: string): { Span }
	local out: { Span } = {}
	if type(text) ~= "string" or utf8.len(text) == nil then
		return out
	end
	local points: { { At: number, Cp: number } } = {}
	for at, cp in utf8.codes(text) do
		table.insert(points, { At = at, Cp = cp })
	end
	local function endOf(index: number): number
		local following = points[index + 1]
		return if following then following.At - 1 else #text
	end
	local index = 1
	while index <= #points do
		local point = points[index]
		local following = points[index + 1]
		local starts = isPicture(point.Cp) and not inRange(point.Cp, 0x1F3FB, 0x1F3FF)
		if not starts and isPictureWithSelector(point.Cp) and following and following.Cp == PICTURE then
			starts = true
		end
		if not starts then
			index += 1
			continue
		end
		local last = index
		while points[last + 1] do
			local cp = points[last + 1].Cp
			if rides(cp) then
				last += 1
			elseif cp == ZWJ and points[last + 2] then
				last += 2
			else
				break
			end
		end
		table.insert(out, { From = point.At, To = endOf(last) })
		index = last + 1
	end
	return out
end

function Icons.clusters(text: string): { string }
	local out = {}
	for _, span in spans(text) do
		table.insert(out, string.sub(text, span.From, span.To))
	end
	return out
end

function Icons.count(text: string): number
	return #spans(text)
end

function Icons.words(text: string): string
	if type(text) ~= "string" then
		return ""
	end
	local found = spans(text)
	if #found == 0 then
		return text
	end
	local parts = {}
	local from = 1
	for _, span in found do
		table.insert(parts, string.sub(text, from, span.From - 1))
		from = span.To + 1
	end
	table.insert(parts, string.sub(text, from))
	local words = table.concat(parts, " ")
	words = string.gsub(words, "%s+", " ")
	words = string.gsub(words, "^%s+", "")
	words = string.gsub(words, "%s+$", "")
	return words
end

return table.freeze(Icons)
