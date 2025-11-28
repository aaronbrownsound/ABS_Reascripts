-- Master: force final state = pinned at top (no toggling)
do
  local r = reaper
  local m = r.GetMasterTrack(0)
  if m then
    -- Preserve current selection
    local prev = {}
    local n = r.CountSelectedTracks(0)
    for i = 0, n-1 do prev[#prev+1] = r.GetSelectedTrack(0, i) end

    -- Ensure Arrange/TCP focus and select only Master
    r.SetCursorContext(0, nil)     -- Arrange/TCP
    r.Main_OnCommand(40297, 0)     -- Unselect all tracks
    r.SetOnlyTrackSelected(m)

    -- Deterministic end-state: unpin Master, then pin Master
    r.Main_OnCommand(40001, 0)     -- Track: Unpin tracks from top of arrange view (selected only)
    r.Main_OnCommand(40000, 0)     -- Track: Pin tracks to top of arrange view (selected only)

    -- Restore prior selection
    r.Main_OnCommand(40297, 0)
    for _, t in ipairs(prev) do
      if t and r.ValidatePtr2(0, t, "MediaTrack*") then
        r.SetTrackSelected(t, true)
      end
    end
  end
end

