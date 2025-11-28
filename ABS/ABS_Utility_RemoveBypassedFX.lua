--[[
Delete Bypassed FX Without Automation (Tracks)
Author: You + ChatGPT
Description:
  Scans all tracks for FX that are bypassed AND have no bypass automation points.
  Prompts once; if Yes, deletes those FX.
]]

----------------------------------
-- CONFIG (edit to taste)
----------------------------------
local CONFIG = {
  include_input_fx = false,     -- true = also check Input/Rec FX
  prompt_per_track = false,     -- true = ask per-track; false = single global prompt
  show_report_in_console = false, -- leave false so only the prompt shows
  title = "Delete Bypassed FX Without Automation",
}

----------------------------------
-- Helpers
----------------------------------

-- Safe count of envelope points
local function envelope_has_points(env)
  if not env then return false end
  local cnt = reaper.CountEnvelopePoints(env)
  return (cnt or 0) > 0
end

-- Returns true if FX is bypassed (i.e., disabled)
local function fx_is_bypassed(track, fx_idx)
  -- TrackFX_GetEnabled returns true when enabled; false when bypassed
  local enabled = reaper.TrackFX_GetEnabled(track, fx_idx)
  return not enabled
end

-- Returns true if the FX bypass envelope exists and has automation points
local function fx_bypass_has_automation(track, fx_idx)
  -- parameter index -1 is the special "FX bypass" envelope
  local env = reaper.GetFXEnvelope(track, fx_idx, -1, false)
  return envelope_has_points(env)
end

-- Get track name (fallback to "Track N")
local function get_track_name(track, idx0)
  local ok, name = reaper.GetTrackName(track)
  if ok and name and name ~= "" then return name end
  return ("Track %d"):format((idx0 or 0) + 1)
end

-- Get FX name (fix: capture second return value instead of the boolean)
local function get_fx_name(track, fx_idx)
  local _, name = reaper.TrackFX_GetFXName(track, fx_idx, "")
  if name and name ~= "" then return name end
  return ("FX %d"):format(fx_idx + 1)
end

-- Utility to add a line to a string table
local function add(t, s) t[#t+1] = s end

----------------------------------
-- Scan
----------------------------------

local function scan_tracks()
  local results = {}  -- { [i] = { track, track_idx0, name, to_delete={ {fx_idx, fx_name}, ... } } }
  local total_candidates = 0

  local num_tracks = reaper.CountTracks(0)
  for ti = 0, num_tracks - 1 do
    local track = reaper.GetTrack(0, ti)
    local track_name = get_track_name(track, ti)

    local to_delete = {}

    -- Normal FX chain
    local fx_count = reaper.TrackFX_GetCount(track)
    for fi = 0, fx_count - 1 do
      if fx_is_bypassed(track, fi) and not fx_bypass_has_automation(track, fi) then
        table.insert(to_delete, { fx_idx = fi, fx_name = get_fx_name(track, fi) })
      end
    end

    -- Input/Rec FX chain (optional)
    if CONFIG.include_input_fx then
      local rec_count = reaper.TrackFX_GetRecCount(track) or 0
      local REC_BASE = 0x1000000 -- Rec FX base offset
      for rfi = 0, rec_count - 1 do
        local idx = REC_BASE + rfi
        if fx_is_bypassed(track, idx) and not fx_bypass_has_automation(track, idx) then
          table.insert(to_delete, { fx_idx = idx, fx_name = get_fx_name(track, idx) .. " (Input FX)" })
        end
      end
    end

    if #to_delete > 0 then
      results[#results+1] = {
        track = track,
        track_idx0 = ti,
        name = track_name,
        to_delete = to_delete
      }
      total_candidates = total_candidates + #to_delete
    end
  end

  return results, total_candidates
end

----------------------------------
-- Deletion
----------------------------------

local function delete_marked_fx(results)
  -- Delete in reverse index order per track to keep indices stable
  for _, entry in ipairs(results) do
    table.sort(entry.to_delete, function(a, b) return a.fx_idx > b.fx_idx end)
    for _, item in ipairs(entry.to_delete) do
      reaper.TrackFX_Delete(entry.track, item.fx_idx)
    end
  end
end

----------------------------------
-- Main
----------------------------------

local function main()
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local results, total = scan_tracks()

  -- Build report (shown only in the prompt unless you enable console)
  local report_lines = {}
  if total == 0 then
    add(report_lines, "No bypassed FX without automation were found on any tracks.")
  else
    add(report_lines, ("Found %d bypassed FX without automation:"):format(total))
    for _, entry in ipairs(results) do
      add(report_lines, ("  • %s"):format(entry.name))
      for _, item in ipairs(entry.to_delete) do
        add(report_lines, ("      - %s"):format(item.fx_name))
      end
    end
  end

  local report = table.concat(report_lines, "\n")

  if CONFIG.show_report_in_console then
    reaper.ShowConsoleMsg(("== %s ==\n%s\n\n"):format(CONFIG.title, report))
  end

  if total == 0 then
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Delete bypassed FX without automation (none found)", -1)
    reaper.ShowMessageBox("No bypassed FX without automation found.", CONFIG.title, 0)
    return
  end

  if CONFIG.prompt_per_track then
    -- Ask per track
    for _, entry in ipairs(results) do
      local msg_t = { ("Track: %s"):format(entry.name), "Delete these bypassed FX without automation?" }
      for _, item in ipairs(entry.to_delete) do
        add(msg_t, "  • " .. item.fx_name)
      end
      local resp = reaper.ShowMessageBox(table.concat(msg_t, "\n"), CONFIG.title, 4) -- Yes/No
      if resp == 6 then -- Yes
        table.sort(entry.to_delete, function(a, b) return a.fx_idx > b.fx_idx end)
        for _, item in ipairs(entry.to_delete) do
          reaper.TrackFX_Delete(entry.track, item.fx_idx)
        end
      end
    end
  else
    -- Single global prompt listing everything
    local resp = reaper.ShowMessageBox(report .. "\n\nDelete ALL listed FX?", CONFIG.title, 4)
    if resp == 6 then -- Yes
      delete_marked_fx(results)
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Delete bypassed FX without automation", -1)
  reaper.UpdateArrange()
end

main()

