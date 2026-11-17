local UiRules = require("./uirules")
local files = {}
for _, n in { "BranchPanel", "BookPanel", "BadgeBook", "Mailbox", "PlayGifts", "DayReportPanel", "Celebrate" } do
	table.insert(files, "src/client/UI/" .. n .. ".luau")
end
print(UiRules.format(UiRules.calm(files)))
