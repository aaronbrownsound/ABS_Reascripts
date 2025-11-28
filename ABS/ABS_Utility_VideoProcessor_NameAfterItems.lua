-- @description Apply VP: Overlay Text/Timecode with item name to all selected VIDEO items
-- @version 1.0
-- @author you
-- @about Iterates over all selected items, filters to video/image sources, and for each:
--        - Adds "Video processor"
--        - Sets preset "Overlay: Text/Timecode"
--        - Injects code with #text set to the item name (escaped)

local proj = 0

-- -------- Helpers --------
local function isfinite(x) return type(x)=="number" and x==x and x>-math.huge and x<math.huge end

-- Resolve base media source type, unwrapping SECTION parents
local function get_base_source_type(take)
  if not take then return nil end
  local src = reaper.GetMediaItemTake_Source(take)
  if not src then return nil end
  local t = reaper.GetMediaSourceType(src, "")
  -- unwrap SECTION to its parent source if available
  while t == "SECTION" do
    local parent = reaper.GetMediaSourceParent and reaper.GetMediaSourceParent(src) or nil
    if not parent then break end
    src = parent
    t = reaper.GetMediaSourceType(src, "")
  end
  return t
end

-- Consider these as “video-like” for overlay: VIDEO, IMAGE, GIF (and any type containing "VIDEO")
local function is_video_take(take)
  local t = get_base_source_type(take)
  if not t then return false end
  t = string.upper(t)
  if t == "VIDEO" or t == "IMAGE" or t == "GIF" then return true end
  if string.find(t, "VIDEO", 1, true) then return true end
  return false
end

-- Escape item names for putting inside a quoted string in EEL code
local function escape_for_eel_double_quoted(s)
  if not s or s == "" then return "" end
  -- Replace backslash then double quotes; strip newlines/tabs -> space
  s = s:gsub("\\", "\\\\")
  s = s:gsub("\"", "\\\"")
  s = s:gsub("[%c]", " ")  -- control chars -> space
  -- Trim excessive spaces
  s = s:gsub("  +", " ")
  return s
end

-- Build Video Processor code with item text injected
local function build_vp_code(item_text)
  -- Insert as a literal double-quoted string
  local esc = escape_for_eel_double_quoted(item_text or "")
  return [[
// Text/timecode overlay
#text="]] .. esc .. [["; // set to string to override
font="Arial";

//@param1:size 'text height' 0.05 0.01 0.2 0.1 0.001
//@param2:ypos 'y position' 0.95 0 1 0.5 0.01
//@param3:xpos 'x position' 0.5 0 1 0.5 0.01
//@param4:border 'bg pad' 0.1 0 1 0.5 0.01
//@param5:fgc 'text bright' 1.0 0 1 0.5 0.01
//@param6:fga 'text alpha' 1.0 0 1 0.5 0.01
//@param7:bgc 'bg bright' 0.75 0 1 0.5 0.01
//@param8:bga 'bg alpha' 0.5 0 1 0.5 0.01
//@param9:bgfit 'fit bg to text' 0 0 1 0.5 1
//@param10:ignoreinput 'ignore input' 0 0 1 0.5 1

//@param12:tc 'show timecode' 0 0 1 0.5 1
//@param13:tcdf 'dropframe timecode' 0 0 1 0.5 1

input = ignoreinput ? -2:0;
project_wh_valid===0 ? input_info(input,project_w,project_h);
gfx_a2=0;
gfx_blit(input,1);
gfx_setfont(size*project_h,font);
tc>0.5 ? (
  t = floor((project_time + project_timeoffs) * framerate + 0.0000001);
  f = ceil(framerate);
  tcdf > 0.5 && f != framerate ? (
    period = floor(framerate * 600);
    ds = floor(framerate * 60);
    ds > 0 ? t += 18 * ((t / period)|0) + ((((t%period)-2)/ds)|0)*2;
  );
  sprintf(#text,"%02d:%02d:%02d:%02d",(t/(f*3600))|0,(t/(f*60))%60,(t/f)%60,t%f);
) : strcmp(#text,"")==0 ? input_get_name(-1,#text);
gfx_str_measure(#text,txtw,txth);
b = (border*txth)|0;
yt = ((project_h - txth - b*2)*ypos)|0;
xp = (xpos * (project_w-txtw))|0;
gfx_set(bgc,bgc,bgc,bga);
bga>0?gfx_fillrect(bgfit?xp-b:0, yt, bgfit?txtw+b*2:project_w, txth+b*2);
gfx_set(fgc,fgc,fgc,fga);
gfx_str_draw(#text,xp,yt+b);
]]
end

-- -------- Main processing for a single item --------
local function process_item(item)
  if not item then return end
  local take = reaper.GetActiveTake(item)
  if not take then return end
  if not is_video_take(take) then return end

  -- Item/Take name
  local name = reaper.GetTakeName(take) or ""

  -- Add Video Processor (create if not present; 1 = insert if needed)
  local fx_index = reaper.TakeFX_AddByName(take, "Video processor", 1)
  if fx_index < 0 then return end

  -- Switch to the preset (if available)
  reaper.TakeFX_SetPreset(take, fx_index, "Overlay: Text/Timecode")

  -- Inject code with our text
  local code = build_vp_code(name)
  reaper.TakeFX_SetNamedConfigParm(take, fx_index, "code", code)

  -- Optional: force a refresh of the UI/FX (harmless if omitted)
  reaper.TrackList_AdjustWindows(false)
end

-- -------- Entry point: iterate all selected video items --------
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local sel_count = reaper.CountSelectedMediaItems(proj)
if sel_count > 0 then
  -- Snapshot selected items first to avoid issues if anything changes selection/ordering
  local items = {}
  for i = 0, sel_count-1 do
    items[#items+1] = reaper.GetSelectedMediaItem(proj, i)
  end
  for _, it in ipairs(items) do
    process_item(it)
  end
end

reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Apply VP Overlay Text/Timecode with item name to selected VIDEO items", -1)

