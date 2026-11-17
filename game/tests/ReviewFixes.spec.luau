--!nocheck
-- Phase 4 review fixes (simple-start batch), read from the shipped source:
--   · the HUD's level row never says "Level up!" without a clinic (the server refuses: Levels.levelUp MSG.NoPlot);
--   · the Day Report's cash is what Economy.addCash really paid (a closing save or the cap pays nothing);
--   · a quiet day's Day Report shows no "+0" cash row.
-- Run from game/ with the rest:  lune run tests/run

local fs = require("@lune/fs")

local T = require("./expect")
local expect, test = T.expect, T.test

local function source(path: string): string
	for _, prefix in { "", "game/" } do
		if fs.isFile(prefix .. path) then
			return fs.readFile(prefix .. path)
		end
	end
	error("can't find " .. path .. " (run from game/)")
end

T.describe("Review fixes: level row, Day Report cash", function()
	test("the level row is never ready without a plot", function()
		local hud = source("src/client/UI/Hud.luau")
		local at = string.find(hud, "local function renderLevel", 1, true)
		expect(at ~= nil).toBe(true)
		local body = string.sub(hud, at, at + 600)
		expect(string.find(body, "state.PlotIndex == nil", 1, true) ~= nil).toBe(true)
		expect(string.find(body, "view.Ready = false", 1, true) ~= nil).toBe(true)
	end)

	test("Cure records only the cash addCash paid", function()
		local cure = source("src/server/Cure.luau")
		expect(string.find(cure, 'local ok, paid = safely("Economy.addCash"', 1, true) ~= nil).toBe(true)
		expect(string.find(cure, "helperStars, cashPaid)", 1, true) ~= nil).toBe(true)
		expect(string.find(cure, "helperStars, reward.Cash)", 1, true)).toBeNil()
	end)

	test("a quiet day shows no cash row", function()
		local panel = source("src/client/UI/DayReportPanel.luau")
		expect(string.find(panel, "report.CashGained > 0", 1, true) ~= nil).toBe(true)
	end)
end)
