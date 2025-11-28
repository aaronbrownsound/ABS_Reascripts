--[[
Delete empty child tracks under ALL parent folders (single confirmation),
with configurable ignore lists, and preserve folder boundaries so no merges occur.

Also deletes the parent folder track when:
  - ALL of its children have NO items, AND
  - the parent has NO items OR (if ALLOW_PARENT_DELETE_IF_ONLY_MUTED = true) only muted items, AND
  - the parent is not ignored (by name/VI/FX per config).

Tested in REAPER 6/7. No SWS required.
--]]

---------------------------------
-- CONFIG (edit to taste)
---------------------------------
local IGNORE_SUBSTRINGS_ENABLED = false       -- if true, names CONTAINING any of IGNORE_SUBSTRINGS are ignored
local IGNORE_SUBSTRINGS = { "VCA" }          -- case-insensitive substrings to ignore when the toggle above is true
local IGNORE_EXACT      = { "VIDEO" }        -- names EXACTLY matching any of these (case-insensitive) are ignored
local TREAT_CHILD_MUTED_AS_EMPTY = false     -- if true, child tracks with only muted items count as "empty"
local ALLOW_PARENT_DELETE_IF_ONLY_MUTED = true -- if true, parent may be deleted when all children empty AND parent has only muted items
local IGNORE_TRACKS_WITH_VI  = true          -- if true, ignore tracks that contain a virtual instrument in the FX chain
local IGNORE_TRACKS_WITH_FX  = false         -- if true, ignore tracks that contain ANY FX in the FX chain (this also covers VIs)
---------------------------------


local r = reaper

-- ---------------- helpers ----------------

local function folder_delta(tr)
  return r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") or 0
end

local function is_folder_parent(tr)
  return (folder_delta(tr) or 0) > 0
end

local function track_index_0(tr)
  return math.floor((r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") or 1) - 1)
end

local function track_name(tr, fallback_idx)
  local ok, name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
  if ok and name ~= "" then return name end
  if fallback_idx then return ("Track %d"):format(fallback_idx + 1) end
  return ""
end

local function to_upper(s) return (s or ""):upper() end

local function in_list_ci(value, list)
  local v = to_upper(value)
  for _, item in ipairs(list or {}) do
    if v == to_upper(item) then return true end
  end
  return false
end

local function contains_any_ci(value, list)
  local v = to_upper(value)
  for _, item in ipairs(list or {}) do
    if v:find(to_upper(item), 1, true) then return true end
  end
  return false
end

local function name_is_ignored(tr)
  local nm = track_name(tr)
  if IGNORE_SUBSTRINGS_ENABLED and contains_any_ci(nm, IGNORE_SUBSTRINGS) then
    return true
  end
  if in_list_ci(nm, IGNORE_EXACT) then
    return true
  end
  return false
end

-- NEW: FX / instrument helpers
local function track_has_any_fx(tr)
  -- regular (post) FX chain only; input FX are not considered here
  local cnt = r.TrackFX_GetCount(tr) or 0
  return cnt > 0
end

local function track_has_instrument(tr)
  -- returns true if there's an instrument in the FX chain
  -- TrackFX_GetInstrument returns fx index or -1 if none
  local fx_idx = r.TrackFX_GetInstrument(tr) or -1
  return fx_idx >= 0
end

-- NEW: unified ignore check
local function track_is_ignored(tr)
  if name_is_ignored(tr) then return true end
  if IGNORE_TRACKS_WITH_FX and track_has_any_fx(tr) then return true end
  if IGNORE_TRACKS_WITH_VI and track_has_instrument(tr) then return true end
  return false
end

local function count_items(tr)
  return r.CountTrackMediaItems(tr) or 0
end

local function track_all_items_muted(tr)
  local cnt = r.CountTrackMediaItems(tr)
  if cnt == 0 then return false end
  for i = 0, cnt - 1 do
    local it = r.GetTrackMediaItem(tr, i)
    if it and (r.GetMediaItemInfo_Value(it, "B_MUTE") or 0) < 0.5 then
      return false
    end
  end
  return true
end

local function track_empty_or_only_muted(tr, allow_only_muted)
  local cnt = count_items(tr)
  if cnt == 0 then return true end
  if allow_only_muted then
    return track_all_items_muted(tr)
  end
  return false
end

local function child_is_empty(tr)
  local cnt = count_items(tr)
  if cnt == 0 then return true end
  if TREAT_CHILD_MUTED_AS_EMPTY then
    return track_all_items_muted(tr)
  end
  return false
end

-- Return an array of all folder blocks in the project
-- each: { parent_tr, parent_idx, parent_level, children = { {tr, idx}, ... } }
local function collect_all_folder_blocks()
  local proj = 0
  local n = r.CountTracks(proj)
  local blocks = {}
  local i = 0
  while i < n do
    local tr = r.GetTrack(proj, i)
    if not tr then break end
    local d = folder_delta(tr)
    if d > 0 then
      local parent_idx = i
      local parent_tr = tr
      local parent_level = d
      local level = d
      local children = {}
      i = i + 1
      while i < n and level > 0 do
        local ch = r.GetTrack(proj, i)
        if not ch then break end
        table.insert(children, { tr = ch, idx = i })
        level = level + folder_delta(ch)
        i = i + 1
      end
      table.insert(blocks, {
        parent_tr = parent_tr,
        parent_idx = parent_idx,
        parent_level = parent_level,
        children = children
      })
    else
      i = i + 1
    end
  end
  return blocks
end

-- Re-collect a folder’s current children after deletions
local function recollect_children_for_parent(parent_tr)
  local proj = 0
  local n = r.CountTracks(proj)
  local parent_idx = track_index_0(parent_tr)
  if parent_idx < 0 or parent_idx >= n then return {}, parent_idx, 0 end
  local parent_level = folder_delta(parent_tr)
  if parent_level <= 0 then return {}, parent_idx, parent_level end

  local level = parent_level
  local children = {}
  local i = parent_idx + 1
  while i < n and level > 0 do
    local ch = r.GetTrack(proj, i)
    if not ch then break end
    table.insert(children, { tr = ch, idx = i })
    level = level + folder_delta(ch)
    i = i + 1
  end
  return children, parent_idx, parent_level
end

-- Build confirmation text
local function build_confirmation(groups)
  local lines = {}
  local total = 0
  for _, g in ipairs(groups) do
    table.insert(lines, ("Parent: %s"):format(g.parent_label))
    if g.delete_parent then
      table.insert(lines, "  • (parent) " .. g.parent_label)
      total = total + 1
    end
    if #g.candidates == 0 then
      if not g.delete_parent then
        table.insert(lines, "  (no empty children)")
      end
    else
      local shown = 0
      for i, c in ipairs(g.candidates) do
        local nm = track_name(c.tr, c.idx)
        table.insert(lines, ("  • %s"):format(nm))
        shown = shown + 1
        if shown == 30 and #g.candidates > 30 then
          table.insert(lines, ("  ... and %d more"):format(#g.candidates - 30))
          break
        end
      end
      total = total + #g.candidates
    end
    table.insert(lines, "")
  end
  local header = ("Tracks to delete (total %d across %d folder(s)):\n\n")
      :format(total, #groups)
  return header .. table.concat(lines, "\n"), total
end

-- ---------------- main ----------------

r.Undo_BeginBlock()

local blocks = collect_all_folder_blocks()
if #blocks == 0 then
  r.ShowMessageBox("No folder parents found in this project.", "Delete Empty Children (All Folders)", 0)
  r.Undo_EndBlock("Delete empty children (all) - no folders", -1)
  return
end

-- Build groups and filter:
-- - child deletion: non-folder child that's "empty" per settings and not ignored (name/VI/FX)
-- - parent deletion: ALL children have NO items (strictly zero), AND parent empty or only muted (per config), AND parent not ignored (name/VI/FX)
local groups = {}
local any = false

for _, b in ipairs(blocks) do
  local parent_label = track_name(b.parent_tr, b.parent_idx)
  if parent_label == "" then parent_label = ("Track %d"):format(b.parent_idx + 1) end

  -- children deletion candidates
  local candidates = {}
  -- compute "all children have NO items" (STRICT) for parent-deletion test
  local all_children_no_items = true
  for _, info in ipairs(b.children) do
    local tr = info.tr
    local items = count_items(tr)
    if items ~= 0 then
      all_children_no_items = false
    end
    if (folder_delta(tr) <= 0)
        and child_is_empty(tr)
        and (not track_is_ignored(tr)) then
      table.insert(candidates, { tr = tr, idx = info.idx })
    end
  end

  -- parent deletion check (strict: children must have ZERO items, regardless of muted)
  local delete_parent = false
  if all_children_no_items
     and (not track_is_ignored(b.parent_tr))
     and track_empty_or_only_muted(b.parent_tr, ALLOW_PARENT_DELETE_IF_ONLY_MUTED) then
    delete_parent = true
  end

  if delete_parent or #candidates > 0 then any = true end

  table.insert(groups, {
    parent_tr = b.parent_tr,
    parent_idx = b.parent_idx,
    parent_level = b.parent_level,
    parent_label = parent_label,
    candidates = candidates,
    delete_parent = delete_parent
  })
end

if not any then
  r.ShowMessageBox("Nothing to delete: no eligible empty children and no parents that qualify (respecting ignore lists / VI / FX).", "Delete Empty Children (All Folders)", 0)
  r.Undo_EndBlock("Delete empty children (all) - none eligible", -1)
  return
end

-- Single confirmation dialog
local confirm_text, total = build_confirmation(groups)
local resp = r.ShowMessageBox(confirm_text .. "\nProceed?", "Delete Empty Children (All Folders)", 4)
if resp ~= 6 then
  r.Undo_EndBlock("Delete empty children (all) - user cancelled", -1)
  return
end

-- Execute deletions bottom->top per group, parents last (since parent index < children)
table.sort(groups, function(a, b) return a.parent_idx > b.parent_idx end)

r.PreventUIRefresh(1)

for _, g in ipairs(groups) do
  -- gather actual deletion list for the group
  local del_list = {}
  for _, c in ipairs(g.candidates) do table.insert(del_list, c) end
  if g.delete_parent then
    table.insert(del_list, { tr = g.parent_tr, idx = g.parent_idx, is_parent = true })
  end

  if #del_list > 0 then
    table.sort(del_list, function(a, b) return a.idx > b.idx end)
    for _, d in ipairs(del_list) do
      r.DeleteTrack(d.tr)
    end

    -- If parent still exists (not deleted), repair its folder boundary
    if not g.delete_parent then
      local children_after, _, parent_level_now = recollect_children_for_parent(g.parent_tr)
      if parent_level_now > 0 then
        if #children_after == 0 then
          r.SetMediaTrackInfo_Value(g.parent_tr, "I_FOLDERDEPTH", 0)
        else
          local sum_prev = 0
          for i = 1, (#children_after - 1) do
            local tr = children_after[i].tr
            sum_prev = sum_prev + folder_delta(tr)
          end
          local last_tr = children_after[#children_after].tr
          local needed_last = -parent_level_now - sum_prev
          local cur = folder_delta(last_tr)
          if math.floor(cur) ~= math.floor(needed_last) then
            r.SetMediaTrackInfo_Value(last_tr, "I_FOLDERDEPTH", needed_last)
          end
        end
      end
    end
  end
end

r.PreventUIRefresh(-1)
r.UpdateArrange()

r.Undo_EndBlock(("Delete empty child tracks (all folders) — deleted %d"):format(total), -1)

