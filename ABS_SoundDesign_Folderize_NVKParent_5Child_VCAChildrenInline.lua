-- NVK folder + VCA scaffolding (auto-increment FX_* token)
-- - Scans existing track names for FX_([A-Z]+), picks next token (A..Z, AA..)
-- - Inserts 5 empty tracks named "FX_<TOKEN>"
-- - Selects those 5 and runs NVK command
-- - Renames folder parent to "FX_<TOKEN> GRP"
-- - Inserts VCA track inside the folder as first child named "VCA_FX_<TOKEN>"
-- - Grouping (one free group bit):
--     * VCA (child): VOLUME_VCA_LEAD, MUTE_LEAD, SOLO_LEAD
--     * Children (5): VOLUME_VCA_FOLLOW, MUTE_FOLLOW, SOLO_FOLLOW
--     * Parent GRP (folder): ungrouped
-- - No pan grouping
-- Tested in REAPER 7.x

local N_CHILD = 5
local NVK_CMD_STR = "_RSb3f44c3fbf26ce6b97c4d382261dbff5f183d9ec"
local CLEAR_ITM = "40289"

local function fail(msg)
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("NVK + VCA setup (failed)", -1)
  reaper.ShowMessageBox(msg, "Script", 0)
  return
end

local clr_cmd = reaper.NamedCommandLookup(CLEAR_ITM)
if clr_cmd == 0 then
  return fail("Couldn't find the NVK command ID:\n"..CLEAR_ITM.."\nMake sure the NVK action is installed.")
end
reaper.Main_OnCommand(clr_cmd, 0)

-- ===== Helpers: token math (A..Z, AA..AZ, BA.. etc.) =====
local function token_to_num(tok)
  local n = 0
  for i = 1, #tok do
    local c = tok:byte(i) - 64
    if c < 1 or c > 26 then return nil end
    n = n * 26 + c
  end
  return n
end

local function num_to_token(n)
  if not n or n < 1 then return "A" end
  local t = ""
  while n > 0 do
    local rem = (n - 1) % 26
    t = string.char(65 + rem) .. t
    n = math.floor((n - 1) / 26)
  end
  return t
end

local function get_track_name(tr)
  local _, name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
  return name or ""
end

local function count_tracks() return reaper.CountTracks(0) end

-- Find the max FX_* token present; return next token
local function compute_next_fx_token()
  local max_n = 0
  for i = 0, count_tracks() - 1 do
    local tr = reaper.GetTrack(0, i)
    local name = get_track_name(tr)

    -- Exclude any track named exactly "FX_VCA" from influencing the token
    if name ~= "FX_VCA" then
      local tok = name:match("FX_([A-Z]+)")
      if tok then
        local n = token_to_num(tok)
        if n and n > max_n then max_n = n end
      end
    end
  end
  local next_n = (max_n == 0) and 1 or (max_n + 1)
  return num_to_token(next_n)
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

-- ===== Determine names =====
local TOKEN = compute_next_fx_token()
local CHILD_NAME  = "FX_" .. TOKEN
local FOLDER_NAME = CHILD_NAME .. " GRP"
local VCA_NAME    = "VCA_" .. CHILD_NAME      -- << no space; no trailing GRP

-- 1) Insert 5 empty tracks named CHILD_NAME at end
local start_idx = count_tracks()
for i = 0, N_CHILD-1 do
  reaper.InsertTrackAtIndex(start_idx + i, true)
  local tr = reaper.GetTrack(0, start_idx + i)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", CHILD_NAME, true)
end

-- 2) Select those 5 tracks and run NVK command
reaper.Main_OnCommand(40297, 0) -- Unselect all
for i = 0, N_CHILD-1 do
  local tr = reaper.GetTrack(0, start_idx + i)
  reaper.SetTrackSelected(tr, true)
end

local nvk_cmd = reaper.NamedCommandLookup(NVK_CMD_STR)
if nvk_cmd == 0 then
  return fail("Couldn't find the NVK command ID:\n"..NVK_CMD_STR.."\nMake sure the NVK action is installed.")
end
reaper.Main_OnCommand(nvk_cmd, 0)

-- 3) Find the folder parent (first with I_FOLDERDEPTH == 1)
local parent_idx
for i = start_idx, count_tracks()-1 do
  local tr = reaper.GetTrack(0, i)
  if reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") == 1 then
    parent_idx = i
    break
  end
end
if not parent_idx then parent_idx = start_idx end
local parent_tr = reaper.GetTrack(0, parent_idx)
reaper.GetSetMediaTrackInfo_String(parent_tr, "P_NAME", FOLDER_NAME, true)

-- 4) Collect up to 5 children (before inserting VCA so handles stay valid)
local children = {}
local i = parent_idx + 1
while i < count_tracks() and #children < N_CHILD do
  local tr = reaper.GetTrack(0, i)
  children[#children+1] = tr
  if reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") == -1 then break end
  i = i + 1
end
if #children < N_CHILD then
  children = {}
  for j = 1, N_CHILD do
    local tr = reaper.GetTrack(0, parent_idx + j)
    if tr then children[#children+1] = tr end
  end
end

-- 5) Insert VCA track inside the folder as first child
reaper.InsertTrackAtIndex(parent_idx + 1, true)
local vca_tr = reaper.GetTrack(0, parent_idx + 1)
reaper.GetSetMediaTrackInfo_String(vca_tr, "P_NAME", VCA_NAME, true)

-- ===== Grouping: VCA leads; Children follow; Parent ungrouped =====

local ATTRS_TO_CHECK = {
  "VOLUME_VCA_LEAD","VOLUME_VCA_FOLLOW",
  "MUTE_LEAD","MUTE_FOLLOW",
  "SOLO_LEAD","SOLO_FOLLOW",
}

local function find_free_group_bit()
  local used_mask = 0
  local tr_count = reaper.CountTracks(0)
  for i = 0, tr_count-1 do
    local tr = reaper.GetTrack(0, i)
    for _, attr in ipairs(ATTRS_TO_CHECK) do
      local membership = reaper.GetSetTrackGroupMembership(tr, attr, 0, 0) or 0
      used_mask = used_mask | membership
    end
  end
  for bit = 0, 31 do
    local m = (1 << bit)
    if (used_mask & m) == 0 then
      return m
    end
  end
  return 1
end

local BIT_GRP = find_free_group_bit()

local function set_grp(tr, attr, on)
  reaper.GetSetTrackGroupMembership(tr, attr, BIT_GRP, on and BIT_GRP or 0)
end

local function clear_groups(tr)
  local attrs = {
    "VOLUME_LEAD","VOLUME_FOLLOW","PAN_LEAD","PAN_FOLLOW",
    "MUTE_LEAD","MUTE_FOLLOW","SOLO_LEAD","SOLO_FOLLOW",
    "VOLUME_VCA_LEAD","VOLUME_VCA_FOLLOW"
  }
  for _, a in ipairs(attrs) do set_grp(tr, a, false) end
end

-- Clear only the new tracks' groups (don’t touch the rest of the project)
clear_groups(vca_tr)
clear_groups(parent_tr)
for _, tr in ipairs(children) do if tr then clear_groups(tr) end end

-- VCA: Lead for VCA Volume, Mute, Solo
set_grp(vca_tr, "VOLUME_VCA_LEAD", true)
set_grp(vca_tr, "MUTE_LEAD", true)
set_grp(vca_tr, "SOLO_LEAD", true)

-- Children: Follow the VCA (volume/mute/solo)
for _, tr in ipairs(children) do
  if tr then
    set_grp(tr, "VOLUME_VCA_FOLLOW", true)
    set_grp(tr, "MUTE_FOLLOW", true)
    set_grp(tr, "SOLO_FOLLOW", true)
  end
end

-- Parent: intentionally left ungrouped

reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("NVK + VCA setup (VCA leads; children follow; parent ungrouped)", -1)

