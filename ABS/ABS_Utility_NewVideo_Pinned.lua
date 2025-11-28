--[[
ReaScript Name: Add 'video' track, pin via cmd 40000 (arrange focus-safe), restore selection & time
Author: you + ChatGPT
Requirements:
  - For guaranteed pinning, install JS_ReaScriptAPI (ReaPack: "js_ReaScriptAPI: ReaScriptAPI extension")
    so we can set focus explicitly to the Arrange view before firing 40000.
]]

local r = reaper
local PIN_CMD = 40000  -- "Track: Pin tracks to top of arrange view"

-- ---------- helpers: save/restore ----------
local function save_track_selection()
  local t = {}
  local n = r.CountSelectedTracks(0)
  for i = 0, n-1 do t[#t+1] = r.GetSelectedTrack(0, i) end
  return t
end

local function restore_track_selection(t)
  r.Main_OnCommand(40297, 0) -- Unselect all tracks
  for _, tr in ipairs(t) do
    if tr and r.ValidatePtr2(0, tr, "MediaTrack*") then
      r.SetTrackSelected(tr, true)
    end
  end
end

local function save_time_location()
  local proj = 0
  local cur = r.GetCursorPositionEx(proj)
  local ts_s, ts_e = r.GetSet_LoopTimeRange2(proj, false, false, 0, 0, false)
  return {cur = cur, ts_s = ts_s, ts_e = ts_e}
end

local function restore_time_location(s)
  if not s then return end
  local proj = 0
  r.SetEditCurPos2(proj, s.cur or 0, false, false)
  r.GetSet_LoopTimeRange2(proj, true, false, s.ts_s or 0, s.ts_e or 0, false)
end

local function set_track_infinite_silence(tr)
  -- Set volume fader to -inf (0.0 amplitude)
  if tr and reaper.ValidatePtr2(0, tr, "MediaTrack*") then
    reaper.SetMediaTrackInfo_Value(tr, "D_VOL", 0.0)
  end
end
-- ---------- focus Arrange/TCP using JS (best) or vanilla (fallback) ----------
local function focus_arrange_view()
  -- Best: JS_ReaScriptAPI
  if r.APIExists and r.APIExists("JS_Window_Find") then
    local main = r.GetMainHwnd()
    if main then
      -- The arrange/trackview child window is commonly named "trackview"
      -- We'll try a few likely handles.
      local arrange = r.JS_Window_Find("trackview", true)  -- search by title substring
      if not arrange then
        -- If title search fails, try finding by class under main window
        -- (class names vary by OS/theme; this is a best-effort fallback)
        arrange = r.JS_Window_FindChildByID(main, 0x3E9) -- ID guess; harmless if nil
      end
      if arrange then
        r.JS_Window_SetFocus(arrange)
        return true
      end
    end
  end

  -- Fallback: vanilla nudges that usually give TCP focus
  r.SetCursorContext(0, nil)     -- 0 = arrange/tcp
  r.Main_OnCommand(40913, 0)     -- View: Scroll track view to selected tracks
  return false
end

-- ---------- main ----------
r.Undo_BeginBlock()

local sel_before  = save_track_selection()
local time_before = save_time_location()

-- Insert new track at top for predictability
r.InsertTrackAtIndex(0, true)
r.TrackList_AdjustWindows(false)
local tr = r.GetTrack(0, 0)

-- Name it 'video'
r.GetSetMediaTrackInfo_String(tr, "P_NAME", "video", true)

-- Ensure it's at infinite silence volume
set_track_infinite_silence(tr)



-- Select only this track
r.Main_OnCommand(40297, 0)   -- Unselect all tracks
r.SetOnlyTrackSelected(tr)
r.UpdateArrange()

-- Ensure arrange has focus, then fire the pin
local had_js_focus = focus_arrange_view()
if r.Main_OnCommandEx then
  r.Main_OnCommandEx(PIN_CMD, 0, 0)
else
  r.Main_OnCommand(PIN_CMD, 0)
end

-- If pin still didn't happen in your setup, comment the above and try deferring:
-- r.defer(function() r.Main_OnCommand(PIN_CMD, 0) end)

-- Restore original selection/time
restore_track_selection(sel_before)
restore_time_location(time_before)

r.UpdateArrange()
r.Undo_EndBlock("Add 'video' track, pin (40000), restore selection & time", -1)

-- Helpful console note if JS wasn’t available (so you know why focus might still block pinning)
if not had_js_focus and (not r.APIExists or not r.APIExists("JS_Window_Find")) then
  r.ShowConsoleMsg(
    "[Pin via 40000] Note: JS_ReaScriptAPI not found, used vanilla focus fallback. " ..
    "If pin didn't trigger, install JS_ReaScriptAPI via ReaPack so we can hard-focus the Arrange view before running 40000.\n"
  )
end

