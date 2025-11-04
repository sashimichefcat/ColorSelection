local mod = get_mod("ColorSelection")
local UISettings = require("scripts/settings/ui/ui_settings")


mod._colors_revision = 0

local apply_slot_colors
local restore_previous_colors

local function recreate_player_hud()
  local ui_manager = Managers.ui

  if not ui_manager or not ui_manager._hud then
    return false
  end

  local player_manager = Managers.player
  local player = player_manager:local_player(1)

  if not player then
    return false
  end

  local hud = ui_manager._hud
  local peer_id = player:peer_id()
  local local_player_id = player:local_player_id()
  local elements = hud._element_definitions
  local visibility_groups = hud._visibility_groups

  hud:destroy()
  ui_manager:create_player_hud(peer_id, local_player_id, elements, visibility_groups)

  return true
end

local previous_slot_colors = nil

local previous_metatable = nil
local metatable_installed = false

local function restore_previous_colors()
  if previous_slot_colors then
    UISettings.player_slot_colors = previous_slot_colors
    previous_slot_colors = nil

    if metatable_installed then
        setmetatable(UISettings.player_slot_colors, previous_metatable)
      previous_metatable = nil
      metatable_installed = false
    end

    mod._colors_revision = (mod._colors_revision or 0) + 1
  end
end

local function deep_clone_color_table(tbl)
  if not tbl then
    return nil
  end

  local copy = {}

  for i, color in ipairs(tbl) do
    if type(color) == "table" then
      local c = {}
      for k, v in ipairs(color) do
        c[k] = v
      end
      copy[i] = c
    else
      copy[i] = color
    end
  end

  return copy
end


mod.on_unload = function()
  restore_previous_colors()
end

local function apply_slot_colors()

  if not previous_slot_colors then
    previous_slot_colors = deep_clone_color_table(UISettings.player_slot_colors)
  end

  local player_manager = Managers.player
  local local_player_slot = 1

  if player_manager then
    local p = player_manager:local_player_safe(1)
    if p then
      local_player_slot = p:slot() or 1
    end
  end

  for idx = 1, 4 do
    local r, g, b, a

    if idx == 1 then
      r = mod:get("player_color_r")
      g = mod:get("player_color_g")
      b = mod:get("player_color_b")
      a = mod:get("player_color_a")
    else
      r = mod:get(string.format("player%d_color_r", idx))
      g = mod:get(string.format("player%d_color_g", idx))
      b = mod:get(string.format("player%d_color_b", idx))
      a = mod:get(string.format("player%d_color_a", idx))
    end

    r = r or 255
    g = g or 255
    b = b or 255
    a = a or 255

    local target_slot = ((local_player_slot - 1 + (idx - 1)) % 4) + 1

  UISettings.player_slot_colors[target_slot] = { a, r, g, b }
  end

  if not metatable_installed then
    previous_metatable = getmetatable(UISettings.player_slot_colors)

    local function color_loop_index(tbl, key)
      if type(key) == "number" and key >= 1 then
        local len = #tbl

        if len > 0 then
          local idx = ((key - 1) % len) + 1
          return rawget(tbl, idx)
        end
      end

      if previous_metatable and previous_metatable.__index then
        local idxer = previous_metatable.__index

        if type(idxer) == "function" then
          return idxer(tbl, key)
        else
          return idxer[key]
        end
      end
    end

    setmetatable(UISettings.player_slot_colors, {
      __index = color_loop_index,
      __newindex = previous_metatable and previous_metatable.__newindex or nil,
      __metatable = previous_metatable and previous_metatable.__metatable or nil,
    })

    metatable_installed = true
  end

  recreate_player_hud()

  mod._colors_revision = (mod._colors_revision or 0) + 1
end

local last_slot_checked = nil
local last_player_count = nil

mod.update = function()
  local player_manager = Managers.player

  if not player_manager then
    return
  end

  local player = player_manager:local_player_safe(1)

  if not player or player.remote or not player:is_human_controlled() then
    return
  end

  local current_slot = player:slot()

  if current_slot and current_slot ~= last_slot_checked then
    last_slot_checked = current_slot
    apply_slot_colors()
  end

  if player_manager and player_manager.num_human_players then
    local count = player_manager:num_human_players()

    if count ~= last_player_count then
      last_player_count = count
      apply_slot_colors()
    end
  end
end

mod.on_setting_changed = function()
  apply_slot_colors()
end

mod.on_all_mods_loaded = function()
  apply_slot_colors()

  if mod.command then
    mod:command("cs_sync", "sync player slot colors", function()
      apply_slot_colors()
      mod:echo("[ColorSelection] Colors synced.")
    end)
  end
end

mod.on_game_state_changed = function(status, state)
  if status == "enter" then
    apply_slot_colors()
  elseif status == "exit" then
    restore_previous_colors()
  end
end

mod:hook_require("scripts/ui/hud/elements/player_panel_base/hud_element_player_panel_base", function(HudElementPlayerPanelBase)
  mod:hook_safe(HudElementPlayerPanelBase, "_update_player_name_prefix", function(self)
    if self._colors_revision ~= mod._colors_revision then
      self._colors_revision = mod._colors_revision
      self._player_slot = nil
    end
  end)
end)
