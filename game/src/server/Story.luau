--!strict
-- STUB (Task 0). Owned by Task 4: replace with the real regulars' stories (build plan §B5).
--   Story.dueRegular(owner): RegularId? · Story.onCure(owner, regularId)
--   Story.bubble(owner, regularId): { Emote: string, Bubble: string }

local Story = {}

function Story.dueRegular(_owner: Player): string?
	return nil
end

function Story.onCure(_owner: Player, _regularId: string?) end

function Story.bubble(_owner: Player, _regularId: string): { Emote: string, Bubble: string }
	return { Emote = "🙂", Bubble = "" }
end

function Story.start() end

return Story
