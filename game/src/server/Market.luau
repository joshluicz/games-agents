--!strict
-- The Player Market (same server only): listings, buys and the fee (Progression v2 build plan §B3.2/§B4/§B8; design
-- §8, memory-20261116-018/-019). Server only. OWNER: T4. The rules are Logic/Market (Lune-tested); the whole module
-- runs under mocks in tests/MarketServer.spec. No free text, no swaps, no haggling: a listing is a nurse, its level, a
-- price inside the band and the seller's DisplayName. The client asks first (a confirm before every list and buy).
--
--   Market.start()                   the kiosk (Workspace.PlayerMarket), GetMarket, ListNurse, Unlist, BuyListing,
--                                    MarketNews (debounced 0.5 s), listings removed on PlayerRemoving, and each
--                                    listing's level kept in step with the seller's save (PlayerData.Changed)
--   Market.view(): MarketView        every listing (oldest first), the fee in percent, the per-seller cap
--   Market.list(p, nurseId, price): (ok, message)      §B3.2, in that order
--   Market.unlist(p, id): (ok, message)                your own listing only
--   Market.buy(p, id, price): (ok, message)            §B3.2: every check, then the transfer, with no yield;
--                                                      Nurses.take (seller) then Nurses.give (buyer); saveNow seller
--                                                      THEN buyer
--   Market.Sold: Signal (listing, buyer)               after a sale (listing = the public Listing)
--   Market.Pure                      the pure helpers between the PURE markers (tests/MarketServer.spec)
-- Requires Nurses and PlayerData; never Agency. No module requires Market (but Admin).
--
-- Anti-dupe, anti-scam (§B3.2, build plan Review focus 1):
--   · Listings live in memory only. A listing is a LOCK (Nurses.setListed): the nurse never leaves the seller's save
--     until it is sold, and it keeps working. A crash or shutdown ends every listing with nothing to restore.
--   · BuyListing runs every check, then removes the listing from the table (so a second buyer in the same frame
--     finds nothing: "Price changed! Look again"), then Nurses.take (seller: the nurse goes, price - fee comes in, ONE
--     update), then Nurses.give (buyer: the price goes, the exact Level/XP/Copies come in, ONE update). Nothing from
--     the first check to the end of the buyer update yields, so no other call (a second buyer, the seller leaving,
--     an Agency sale) can run in between. If the buyer update fails, the seller update is undone with
--     Nurses.give(seller, entry, payout). A Nurses call that errors counts as a refusal (Nurses changes a save only
--     inside one PlayerData.update).
--   · The undo (step 12) is explicit: Nurses.give(seller, .., true) uses the token of THIS call's take only, and
--     Nurses.endUndo ends it before buy returns, so another sale landing in the same frame is never taken for one.
--   · Then PlayerData.saveNow(seller) and, only once that write landed, saveNow(buyer). PlayerData.writeAfter(seller,
--     buyer, Pure.leaveOut(nurse, price, copies), nurse) leaves the sale out of every buyer write (autosave,
--     leave-save, a rebirth's) until the seller's write has landed, so no write order, crash or failed seller save can
--     put the nurse in two saves: a crash can lose a sale, never duplicate one. A buyer who leaves first has the
--     seller's write run before its own last one (PlayerData's landSellers). leaveOut only takes back what is still
--     there: nothing once the buyer sold the nurse on to the Agency or rebirthed, and never a copy hired since.
--   · ListNurse and BuyListing answer only within Config.KioskReach studs of the kiosk's prompt part, found in the
--     built model at call time (0 = off, as shipped: see Config).
--   · The price the client sends is only ever compared with the listing's (never used), and every argument is
--     type-checked first. Every rejection changes nothing (a stale or vanished listing is only tidied away).
--   · A seller who leaves takes their listings with them (PlayerRemoving, before their leave-save writes). A seller
--     whose save stops being open or saving can't be bought from.
--   · The fee (Config.Market.Fee, 10%) is a cash sink: the seller gets price - floor(price x Fee).
--   · Admins are not excluded. Nothing about a seller is sent but their UserId (to tell "yours" apart) and
--     DisplayName.
-- Nurses sends the NurseNews ("Listed" from setListed, "Gone" from take, "Bought" from give) and the buyer's Celebrate
-- NewNurse (give, as grant does; never on the undo), so Market doesn't send them twice. Market sends MarketNews and
-- the seller's "💰 Sold 🐶! +💰270" toast.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Palette)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)
local MarketLogic = require(Shared.Logic.Market)
local NursesData = require(Shared.Data.Nurses)
local Nurses = require(script.Parent.Nurses)
local PlayerData = require(script.Parent.PlayerData)

local Market = {}

Market.Sold = Signal.new()

------------------------------------------------------------------------------------------------------------------
-- Tuning (the rules' numbers are in Config.Market)
------------------------------------------------------------------------------------------------------------------

local NEWS_SECONDS = 0.5 -- MarketNews to everyone at most this often (debounced)
local MODEL_NAME = "PlayerMarket"
local PROMPT_NAME = "Prompt"
local KIOSK_ATTRIBUTE = "Kiosk" -- on the prompt: the client opens the panel when a prompt with "Market" fires
local FALLBACK_GROUND_TOP = 0.5 -- PlotBuilder's street top above Config.Town.Origin.Y (if ClinicTown is missing)
local STALE = "Price changed! Look again"
local FAR = "🚶 Come closer!" -- further than Config.KioskReach from the kiosk
local RELIST = "🏷️ It grew! List it again" -- a copy raised a listed nurse's lowest price: the listing ended

------------------------------------------------------------------------------------------------------------------
-- Pure helpers (no Roblox services, no upvalues: tests/MarketServer.spec loads this block on its own)
------------------------------------------------------------------------------------------------------------------

-- PURE-BEGIN
local Pure = {}

Pure.MAX_ID = 2 ^ 31 -- listing ids count up from 1 and never reach this
Pure.MAX_NURSE_ID = 40 -- characters: longer is junk

-- A finite whole number.
function Pure.whole(value: any): boolean
	return type(value) == "number" and value == value and value % 1 == 0 and value > -math.huge and value < math.huge
end

-- A listing id as a client may send it: a whole number in 1..MAX_ID.
function Pure.idOk(value: any): boolean
	return Pure.whole(value) and value >= 1 and value < Pure.MAX_ID
end

-- A nurse id as a client may send it: a short non-empty string (the roster lookup comes after).
function Pure.nurseIdOk(value: any): boolean
	return type(value) == "string" and #value >= 1 and #value <= Pure.MAX_NURSE_ID
end

-- The cooldown: true when `cooldown` seconds have passed since `last` (nil = never).
function Pure.ready(last: number?, now: number, cooldown: number): boolean
	return last == nil or now - last >= cooldown
end

-- The public part of a listing record (never the Player object or anything else about anyone).
function Pure.public(record: any): any
	return {
		Id = record.Id,
		Seller = record.Seller,
		SellerName = record.SellerName,
		NurseId = record.NurseId,
		Rarity = record.Rarity,
		Level = record.Level,
		Price = record.Price,
	}
end

-- The MarketView: every listing, oldest first.
function Pure.view(listings: { [number]: any }, cfg: any): any
	local list = {}
	for _, record in listings do
		table.insert(list, Pure.public(record))
	end
	table.sort(list, function(a, b)
		return a.Id < b.Id
	end)
	local market = if type(cfg) == "table" and type(cfg.Market) == "table" then cfg.Market else {}
	local fee = if type(market.Fee) == "number" then market.Fee else 0
	local perSeller = if type(market.MaxPerSeller) == "number" then market.MaxPerSeller else 0
	return { Listings = list, FeePercent = math.floor(fee * 100 + 0.5), MaxPerSeller = perSeller }
end

-- How many listings this seller has, and how many the server has.
function Pure.count(listings: { [number]: any }, userId: number): (number, number)
	local mine, total = 0, 0
	for _, record in listings do
		total += 1
		if record.Seller == userId then
			mine += 1
		end
	end
	return mine, total
end

-- This seller's listing of this nurse, if any.
function Pure.find(listings: { [number]: any }, userId: number, nurseId: string): number?
	for id, record in listings do
		if record.Seller == userId and record.NurseId == nurseId then
			return id
		end
	end
	return nil
end

-- What PlayerData.writeAfter(seller, buyer, ..) applies to a COPY of the buyer's save while the seller's write
-- hasn't landed: the sale taken back out (the nurse goes, the price comes back), so the buyer's stored save can never
-- hold the nurse while the seller's stored save still does. It only takes back what is still there (`copies` = the
-- Copies that were bought; nil = not checked):
--   · the nurse is gone (sold to the Agency, a rebirth): nothing changes. A refund now would be cash from nowhere
--     (the Agency already paid for it, or the rebirth already reset the cash);
--   · fewer Copies than were bought: it left and a new one was hired since. Not this sale's: nothing changes;
--   · more Copies than were bought (a belt or Agency copy came since): only the bought Copies go and the price comes
--     back. The copy the buyer paid for elsewhere stays, and the bought ones are still never in two saves.
function Pure.leaveOut(nurseId: string, price: number, copies: number?): (any) -> ()
	return function(snapshot: any)
		if type(snapshot) ~= "table" or type(snapshot.Nurses) ~= "table" then
			return
		end
		local entry = snapshot.Nurses[nurseId]
		if type(entry) ~= "table" then
			return
		end
		local has = entry.Copies
		if type(copies) == "number" and type(has) == "number" and has ~= copies then
			if has < copies then
				return
			end
			entry.Copies = has - copies
		else
			snapshot.Nurses[nurseId] = nil
		end
		snapshot.Cash = (if type(snapshot.Cash) == "number" then snapshot.Cash else 0) + price
	end
end

-- Within `reach` studs: a and b are positions (anything with X, Y and Z). Junk is never near.
function Pure.near(a: any, b: any, reach: number): boolean
	local function axis(value: any): boolean
		return type(value) == "number" and value == value
	end
	local function spot(value: any): boolean
		if type(value) ~= "table" and type(value) ~= "userdata" and type(value) ~= "vector" then
			return false
		end
		return axis(value.X) and axis(value.Y) and axis(value.Z)
	end
	if not spot(a) or not spot(b) or not axis(reach) then
		return false
	end
	local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
	return dx * dx + dy * dy + dz * dz <= reach * reach
end

-- A clean copy of a save's nurse entry: what moves to the buyer (its Job resets there).
function Pure.entryCopy(entry: any): { Level: number, XP: number, Copies: number, Job: string }
	local function whole(value: any, fallback: number, low: number): number
		if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
			return fallback
		end
		return math.max(low, math.floor(value))
	end
	local e = if type(entry) == "table" then entry else {}
	return { Level = whole(e.Level, 1, 1), XP = whole(e.XP, 0, 0), Copies = whole(e.Copies, 1, 1), Job = "" }
end

function Pure.commas(n: number): string
	local digits = tostring(math.floor(math.abs(n)))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	if string.sub(grouped, 1, 1) == "," then
		grouped = string.sub(grouped, 2)
	end
	return grouped
end

-- "Pick 💰50 to 💰300" (a price outside the band; 4 words).
function Pure.bandText(min: number, max: number): string
	return "Pick 💰" .. Pure.commas(min) .. " to 💰" .. Pure.commas(max)
end

-- The seller's toast: "💰 Sold 🐶! +💰270" (4 words).
function Pure.soldText(icon: string, payout: number): string
	return "💰 Sold " .. icon .. "! +💰" .. Pure.commas(payout)
end
-- PURE-END

Market.Pure = Pure

------------------------------------------------------------------------------------------------------------------
-- State (in memory only: a listing is a lock, never a copy)
------------------------------------------------------------------------------------------------------------------

type Record = {
	Id: number,
	Seller: number, -- UserId
	SellerName: string, -- DisplayName
	NurseId: string,
	Rarity: string,
	Level: number, -- the nurse's level now (it keeps working, so it can grow while listed)
	Price: number,
	Player: Player, -- the seller (server only; never sent)
}

local listings: { [number]: Record } = {}
local lastId = 0
local lastList: { [Player]: number } = {}
local lastBuy: { [Player]: number } = {}
local newsPending = false

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function inServer(player: Player): boolean
	return player.Parent == Players
end

local function nurseOf(nurseId: string): any
	local nurse = rawget(NursesData :: any, nurseId)
	return if type(nurse) == "table" then nurse else nil
end

-- Another system's call, guarded: a bug there must not break the Market (an error counts as a refusal).
local function guarded(label: string, fn: (...any) -> ...any, ...: any): (boolean, any, any)
	local ok, a, b, c = pcall(fn, ...)
	if not ok then
		warn("[Market] " .. label .. " failed:", a)
		return false, nil, nil
	end
	return a == true, b, c
end

-- The save has this nurse now (what really happened, whatever a call answered).
local function hasNurse(player: Player, nurseId: string): boolean
	local data = PlayerData.get(player)
	return data ~= nil and type(data.Nurses) == "table" and type(data.Nurses[nurseId]) == "table"
end

local function setLock(player: Player, nurseId: string, id: number?)
	local ok, err = pcall(Nurses.setListed, player, nurseId, id)
	if not ok then
		warn("[Market] Nurses.setListed failed:", err)
	end
end

local function isLocked(player: Player, nurseId: string): boolean
	local ok, listed = pcall(Nurses.isListed, player, nurseId)
	return ok and listed == true
end

function Market.view(): Types.MarketView
	return Pure.view(listings, Config)
end

-- MarketNews to everyone, at most once per NEWS_SECONDS (many changes in a burst send one view).
local function newsSoon()
	if newsPending then
		return
	end
	newsPending = true
	task.delay(NEWS_SECONDS, function()
		newsPending = false
		local ok, err = pcall(function()
			Remotes.MarketNews:FireAllClients(Market.view())
		end)
		if not ok then
			warn("[Market] MarketNews failed:", err)
		end
	end)
end

-- A fresh view to one player now (after a refusal, so their panel shows what is really there).
local function newsTo(player: Player)
	if inServer(player) then
		pcall(function()
			Remotes.MarketNews:FireClient(player, Market.view())
		end)
	end
end

-- Ends a listing and frees its lock.
local function drop(id: number)
	local record = listings[id]
	if not record then
		return
	end
	listings[id] = nil
	setLock(record.Player, record.NurseId, nil)
	newsSoon()
end

------------------------------------------------------------------------------------------------------------------
-- List, unlist, buy
------------------------------------------------------------------------------------------------------------------

function Market.list(player: Player, nurseId: any, price: any): (boolean, string)
	if not isPlayer(player) or not Pure.nurseIdOk(nurseId) or type(price) ~= "number" then
		return false, Remotes.OOPS
	end
	local nurse = nurseOf(nurseId)
	local data = PlayerData.get(player)
	if not nurse or not data or not inServer(player) or not PlayerData.isOpen(player) then
		return false, Remotes.OOPS
	end
	-- 1. You own it, and it isn't rebirth-only (a resting nurse may be listed: that's how a full roster makes room).
	local ok, why = MarketLogic.canList(data, nurseId, 0, 0, Config, NursesData)
	if not ok then
		return false, why
	end
	-- 2. It isn't listed already.
	if Pure.find(listings, player.UserId, nurseId) ~= nil or isLocked(player, nurseId) then
		return false, "Already listed!"
	end
	-- 3. The price is a whole number inside the band for its level now, never below what the Agency pays for all its
	-- copies after the fee (Logic/Market.floor): no seller short-changed, no buy-and-sell-back profit.
	local entry = data.Nurses[nurseId]
	local min, max = MarketLogic.band(Config, nurse.Rarity, entry.Level, entry.Copies)
	if not MarketLogic.valid(price, min, max) then
		return false, Pure.bandText(min, max)
	end
	-- 4. Fewer than MaxPerSeller listings of yours, fewer than MaxListings on the server.
	local mine, total = Pure.count(listings, player.UserId)
	ok, why = MarketLogic.canList(data, nurseId, mine, total, Config, NursesData)
	if not ok then
		return false, why
	end
	-- 5. A session that isn't saving can't sell.
	if not PlayerData.canSave(player) then
		return false, "⚠️ Saving is off"
	end
	-- 6. 5 s per player.
	local now = os.clock()
	if not Pure.ready(lastList[player], now, Config.Market.ListCooldown) then
		return false, Remotes.TOO_FAST
	end
	lastList[player] = now

	lastId += 1
	local id = lastId
	listings[id] = {
		Id = id,
		Seller = player.UserId,
		SellerName = player.DisplayName,
		NurseId = nurseId,
		Rarity = nurse.Rarity,
		Level = entry.Level,
		Price = price,
		Player = player,
	}
	setLock(player, nurseId, id)
	newsSoon()
	return true, "🏷️ Listed for 💰" .. Pure.commas(price) .. "!"
end

function Market.unlist(player: Player, id: any): (boolean, string)
	if not isPlayer(player) or not Pure.idOk(id) then
		return false, Remotes.OOPS
	end
	local record = listings[id]
	if not record then
		newsTo(player)
		return false, "Not listed now!"
	end
	if record.Player ~= player then
		return false, "That's not yours!"
	end
	drop(id)
	return true, "📦 Unlisted!"
end

function Market.buy(buyer: Player, id: any, price: any): (boolean, string)
	if not isPlayer(buyer) or not Pure.idOk(id) or type(price) ~= "number" then
		return false, Remotes.OOPS
	end
	-- From here to the end of the buyer update nothing yields: no second buyer, no leave, no other sale in between.
	-- 1. The listing exists and the price the client saw is the price.
	local record = listings[id]
	if not record or price ~= record.Price then
		newsTo(buyer)
		return false, STALE
	end
	-- 2. Not your own.
	local seller = record.Player
	if seller == buyer or record.Seller == buyer.UserId then
		return false, "That's yours!"
	end
	-- 3. Both players are in this server, open and saving.
	if not inServer(buyer) or not PlayerData.isOpen(buyer) then
		return false, Remotes.OOPS
	end
	if not PlayerData.canSave(buyer) then
		return false, "⚠️ Saving is off"
	end
	if not inServer(seller) or not PlayerData.isOpen(seller) or not PlayerData.canSave(seller) then
		drop(id) -- nobody can buy it any more: tidy it away
		newsTo(buyer)
		return false, "Seller left! Look again"
	end
	-- 4. The seller still owns that nurse, and this listing is still this nurse's.
	local nurse = nurseOf(record.NurseId)
	local sellerData = PlayerData.get(seller)
	local held = if sellerData then sellerData.Nurses[record.NurseId] else nil
	if not nurse or type(held) ~= "table" or Pure.find(listings, record.Seller, record.NurseId) ~= id then
		drop(id)
		newsTo(buyer)
		return false, STALE
	end
	-- It gained copies while listed (a belt or Agency copy): the old price may now be below the Agency's sell-back.
	if record.Price < MarketLogic.floor(Config, record.Rarity, held.Copies) then
		drop(id)
		newsTo(buyer)
		return false, STALE
	end
	-- 5-7. The buyer's gates (as the belt's), no copy already, roster room, cash.
	local buyerData = PlayerData.get(buyer)
	if not buyerData then
		return false, Remotes.OOPS
	end
	local owns = type(buyerData.Nurses[record.NurseId]) == "table"
	local ok, why = MarketLogic.canBuy(buyerData, Pure.public(record), owns, Config, NursesData)
	if not ok then
		return false, why
	end
	-- 8. 2 s per buyer.
	local now = os.clock()
	if not Pure.ready(lastBuy[buyer], now, Config.Market.BuyCooldown) then
		return false, Remotes.TOO_FAST
	end
	lastBuy[buyer] = now

	-- 9. The lock: off the table first, so anyone else finds nothing.
	listings[id] = nil
	newsSoon()
	local nurseId = record.NurseId
	local entry = Pure.entryCopy(held)
	local payout = price - MarketLogic.fee(price, Config)

	-- 10. The seller: the nurse goes, the payout comes in (ONE update; it also frees the lock). The save decides
	-- what happened: a take that errored after its update still moved the nurse (and the payout), so carry on.
	local took, _, takenEntry = guarded("Nurses.take", Nurses.take, seller, nurseId, payout, "Market")
	if not took and hasNurse(seller, nurseId) then
		setLock(seller, nurseId, nil) -- the seller still has it, unlisted
		newsTo(buyer)
		return false, Remotes.OOPS
	end
	if type(takenEntry) == "table" then
		entry = Pure.entryCopy(takenEntry) -- exactly what left the seller's save
	end

	-- 11. The buyer: the price goes, the exact Level/XP/Copies come in (ONE update). Again the save decides: a give
	-- that errored after its update DID hand the nurse over, and undoing it then would make two.
	local gave = guarded("Nurses.give", Nurses.give, buyer, nurseId, entry, price)
	if not gave and not hasNurse(buyer, nurseId) then
		-- 12. Undo step 10 in one update: the nurse goes back, the payout comes back out. The undo is explicit (`true`):
		-- only this call's own take can be undone, never by a give that merely lands in the same frame.
		local back = guarded("Nurses.give (undo)", Nurses.give, seller, nurseId, entry, payout, true)
		pcall(Nurses.endUndo, seller, nurseId)
		if not back then
			warn(
				string.format(
					"[Market] Undo failed: %s (%d) keeps 💰%d and lost %s Lv %d",
					seller.Name,
					seller.UserId,
					payout,
					nurseId,
					entry.Level
				)
			)
		end
		newsTo(buyer)
		return false, Remotes.OOPS
	end
	pcall(Nurses.endUndo, seller, nurseId) -- sold: nothing can undo this take any more

	-- 13. Seller first, then the buyer, and the buyer only once the seller's write landed. writeAfter also leaves this
	-- sale out of every buyer write until the seller's write has landed (the nurse and the price), so no write order,
	-- crash or failed seller save can put the nurse in both saves.
	pcall(PlayerData.writeAfter, seller, buyer, Pure.leaveOut(nurseId, price, entry.Copies), nurseId)
	task.spawn(function()
		local ok1, sellerSaved = pcall(PlayerData.saveNow, seller)
		if ok1 and sellerSaved then
			pcall(PlayerData.saveNow, buyer)
		end
	end)
	local sold = Pure.public(record)
	sold.Level = entry.Level
	Remotes.toast(seller, Pure.soldText(nurse.Icon, payout))
	Market.Sold:Fire(sold, buyer)
	return true, "🎉 " .. nurse.Name .. " is yours!"
end

------------------------------------------------------------------------------------------------------------------
-- The kiosk (Workspace.PlayerMarket, §B4): ≤ 25 parts, no Highlight, no shadow-casting light, on the plaza's row-2
-- half at Config.Town.Origin + Config.Market.Offset, facing the street's centre line (and the spawn). Its prompt
-- only opens the panel on the client (ProximityPrompt attribute Kiosk = "Market"); the server decides everything.
-- The brother's ServerStorage.ClinicKit.PlayerMarket replaces the placeholder (pivot = the ground under its middle,
-- facing the spawn); a ProximityPrompt named Prompt in it is used, else one is added.
------------------------------------------------------------------------------------------------------------------

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function soft(p: BasePart): BasePart
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function streetTop(): number
	local town = Workspace:FindFirstChild("ClinicTown")
	local street = town and town:FindFirstChild("Street")
	if street and street:IsA("BasePart") then
		return street.Position.Y + street.Size.Y / 2
	end
	return Config.Town.Origin.Y + FALLBACK_GROUND_TOP
end

local function signLabel(parent: Instance, text: string, size: UDim2, position: UDim2, color: Color3)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Font = Palette.DisplayFont
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	Palette.outlineText(label, 3)
	label.Parent = parent
end

local function surfaceGui(parent: BasePart, name: string): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0 -- readable at night too
	gui.MaxDistance = 160
	gui.Parent = parent
	return gui
end

local function addPrompt(parent: Instance): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ActionText = "Market"
	prompt.ObjectText = "🏷️"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent
	return prompt
end

-- A paler tint (the stall's back panel).
local function paler(color: Color3): Color3
	return color:Lerp(Palette.White, 0.45)
end

-- The placeholder stall: a candy counter under a striped awning, a sign on top. 19 parts. `frame` is the ground
-- under its middle; its LookVector (local -Z) faces the street's centre line.
local function placeholderKiosk(frame: CFrame): Model
	local candy = Palette.Candy
	local white = Palette.White
	local model = Instance.new("Model")
	model.Name = MODEL_NAME

	local base = part(model, "Base", Vector3.new(7.4, 0.4, 4.6), frame * CFrame.new(0, 0.2, 0), Palette.World.Path)
	model.PrimaryPart = base
	local counter =
		part(model, "Counter", Vector3.new(6.4, 2.8, 1.6), frame * CFrame.new(0, 0.4 + 1.4, -1.3), candy.Orange)
	part(model, "CounterTop", Vector3.new(6.8, 0.3, 2), frame * CFrame.new(0, 3.35, -1.3), white)
	part(model, "Back", Vector3.new(6.4, 4.4, 0.3), frame * CFrame.new(0, 2.6, 2.05), paler(candy.Orange))
	for _, x in { -3.45, 3.45 } do
		for _, z in { -1.9, 1.9 } do
			part(model, "Post", Vector3.new(0.5, 7, 0.5), frame * CFrame.new(x, 3.9, z), white)
			local cap = part(model, "PostCap", Vector3.new(0.8, 0.8, 0.8), frame * CFrame.new(x, 7.6, z), candy.Yellow)
			cap.Shape = Enum.PartType.Ball
			soft(cap)
		end
	end
	-- The awning: four stripes, tipped down toward the front.
	local tilt = CFrame.Angles(math.rad(-11.5), 0, 0)
	for index = 1, 4 do
		local x = -3.7 + (index - 0.5) * 1.85
		soft(
			part(
				model,
				"Awning",
				Vector3.new(1.85, 0.25, 5.1),
				frame * CFrame.new(x, 6.95, -0.15) * tilt,
				if index % 2 == 1 then candy.Pink else white
			)
		)
	end
	local sign = soft(part(model, "Sign", Vector3.new(5.2, 1.8, 0.3), frame * CFrame.new(0, 7.35, -2.75), candy.Pink))
	local signGui = surfaceGui(sign, "SignGui")
	signLabel(signGui, "🏷️ MARKET", UDim2.fromScale(0.94, 0.62), UDim2.fromScale(0.03, 0.04), white)
	signLabel(signGui, "Only this server", UDim2.fromScale(0.8, 0.3), UDim2.fromScale(0.1, 0.66), candy.Yellow)
	local front = surfaceGui(counter, "CounterGui")
	signLabel(front, "🐶 Buy & sell nurses", UDim2.fromScale(0.9, 0.36), UDim2.fromScale(0.05, 0.12), white)
	signLabel(front, "No swaps · No chat", UDim2.fromScale(0.7, 0.26), UDim2.fromScale(0.15, 0.6), candy.Yellow)
	-- Two price tags on the counter.
	for _, x in { -2.2, 2.2 } do
		soft(
			part(
				model,
				"Tag",
				Vector3.new(0.9, 0.6, 0.12),
				frame * CFrame.new(x, 3.8, -1.6) * CFrame.Angles(0, 0, math.rad(if x < 0 then 12 else -12)),
				candy.Yellow
			)
		)
	end
	addPrompt(counter)
	model.WorldPivot = frame
	return model
end

-- The brother's kiosk, if there is one: cloned clean (no scripts, no Highlights, no shadows), with a Prompt.
local function kitKiosk(frame: CFrame): Model?
	local kit = ServerStorage:FindFirstChild("ClinicKit")
	local template = kit and kit:FindFirstChild(MODEL_NAME)
	if not (template and template:IsA("Model")) then
		return nil
	end
	local model = template:Clone()
	local prompt: ProximityPrompt? = nil
	local firstPart: BasePart? = nil
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") then
			warn("[Market] Removed a script from ClinicKit.PlayerMarket:", descendant:GetFullName())
			descendant:Destroy()
		elseif descendant:IsA("Highlight") then
			descendant:Destroy() -- the perf budget: at most one Highlight in the world
		elseif descendant:IsA("Light") then
			descendant.Shadows = false
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			firstPart = firstPart or descendant
		elseif descendant:IsA("ProximityPrompt") and descendant.Name == PROMPT_NAME then
			prompt = descendant
		end
	end
	if not prompt then
		local holder = model.PrimaryPart or firstPart
		if not holder then
			warn("[Market] ClinicKit.PlayerMarket has no parts; using the placeholder")
			model:Destroy()
			return nil
		end
		addPrompt(holder)
	end
	model.Name = MODEL_NAME
	model:PivotTo(frame)
	return model
end

local function buildKiosk()
	local town = Config.Town.Origin
	local offset = (Config.Market :: any).Offset
	local at = if typeof(offset) == "Vector3" then town + offset else town
	local foot = Vector3.new(at.X, streetTop(), at.Z)
	local toward = Vector3.new(0, 0, town.Z - at.Z)
	local face = if toward.Magnitude > 0.5 then toward.Unit else Vector3.new(0, 0, -1)
	local frame = CFrame.lookAt(foot, foot + face)
	local old = Workspace:FindFirstChild(MODEL_NAME)
	if old then
		warn("[Market] Replacing an existing Workspace." .. MODEL_NAME)
		old:Destroy()
	end
	local model = kitKiosk(frame) or placeholderKiosk(frame)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("ProximityPrompt") and descendant.Name == PROMPT_NAME then
			descendant:SetAttribute(KIOSK_ATTRIBUTE, "Market")
		end
	end
	model.Parent = Workspace
end

------------------------------------------------------------------------------------------------------------------
-- Standing at the kiosk (Config.KioskReach; 0 = off). The kiosk is found in the world at call time, wherever it was
-- built or moved to: the part that holds its prompt, else the model's pivot.
------------------------------------------------------------------------------------------------------------------

local function kioskSpot(): Vector3?
	local model = Workspace:FindFirstChild(MODEL_NAME)
	if not model then
		return nil
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			local holder = descendant.Parent
			if holder and holder:IsA("BasePart") then
				return holder.Position
			elseif holder and holder:IsA("Attachment") then
				return holder.WorldPosition
			end
		end
	end
	return if model:IsA("PVInstance") then model:GetPivot().Position else nil
end

-- True when the check is off, when there is no kiosk to stand at, or when the player's HumanoidRootPart is within
-- Config.KioskReach studs of it. The server's own positions only: nothing from the client is read.
local function nearKiosk(player: Player): boolean
	local reach = (Config :: any).KioskReach
	if type(reach) ~= "number" or reach <= 0 then
		return true
	end
	local spot = kioskSpot()
	if not spot then
		return true
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return false
	end
	return Pure.near(root.Position, spot, reach)
end

------------------------------------------------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------------------------------------------------

function Market.start()
	Remotes.serve("GetMarket", function(_player: Player)
		return true, "", Market.view()
	end)
	Remotes.serve("ListNurse", function(player: Player, nurseId: any, price: any)
		if not nearKiosk(player) then
			return false, FAR
		end
		return Market.list(player, nurseId, price)
	end)
	Remotes.serve("Unlist", function(player: Player, id: any)
		return Market.unlist(player, id)
	end)
	Remotes.serve("BuyListing", function(player: Player, id: any, price: any)
		if not nearKiosk(player) then
			return false, FAR
		end
		return Market.buy(player, id, price)
	end)

	-- A seller who leaves takes their listings with them, at once (their leave-save waits a frame for this).
	Players.PlayerRemoving:Connect(function(player: Player)
		for id, record in listings do
			if record.Player == player then
				drop(id)
			end
		end
		lastList[player] = nil
		lastBuy[player] = nil
	end)

	-- A listed nurse keeps working: its level on the Market follows the seller's save, and a listing whose nurse
	-- left the save (it can't, while listed; belt and braces) ends.
	PlayerData.Changed:Connect(function(player: Player, data: any)
		for id, record in listings do
			if record.Player == player then
				local entry = if type(data) == "table" and type(data.Nurses) == "table"
					then data.Nurses[record.NurseId]
					else nil
				if type(entry) ~= "table" then
					drop(id)
				elseif record.Price < MarketLogic.floor(Config, record.Rarity, entry.Copies) then
					-- A copy came while listed: the price is now below what the Agency pays for it (Logic/Market.floor).
					-- The listing ends; the seller lists it again at a fair price.
					drop(id)
					Remotes.toast(player, RELIST)
				elseif type(entry.Level) == "number" and entry.Level ~= record.Level then
					record.Level = entry.Level
					newsSoon()
				end
			end
		end
	end)

	local ok, err = pcall(buildKiosk)
	if not ok then
		warn("[Market] The kiosk wasn't built:", err)
	end
end

return Market
