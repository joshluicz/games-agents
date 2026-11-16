--!strict
-- STUB (Task 0). Owned by Task 2: replace with the real stations (build plan §B5).
-- The real one puts a hold-to-make prompt on every Station_* of every placed room (Plots.observeRooms),
-- checks the hold time on the server, enforces Plots.canWork, then Carry.add and Daily.onMake.

local Stations = {}

function Stations.start() end

return Stations
