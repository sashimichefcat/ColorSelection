local mod = get_mod("ColorSelection")

local UISettings = require("scripts/settings/ui/ui_settings")
local recreate_player_hud

local function color_for_slot(slot)
	if not slot or slot < 1 then
		return 1
	end
	return slot
end

local function get_color(prefix)
	return {
		mod:get(prefix .. "_a") or 255,
		mod:get(prefix .. "_r") or 255,
		mod:get(prefix .. "_g") or 255,
		mod:get(prefix .. "_b") or 255,
	}
end

local ColorAllocator = {
	cfg_colors = {},
	slot_to_index = {},
	index_taken = {},
}

function ColorAllocator:reset(my_slot)
	self.slot_to_index = {}
	self.index_taken = { false, false, false, false }
	if my_slot and my_slot >= 1 then
		self.slot_to_index[my_slot] = 1
		self.index_taken[1] = true
	end
end

function ColorAllocator:setup(my_slot)
	self.cfg_colors = {
		get_color("player_color"),
		get_color("player2_color"),
		get_color("player3_color"),
		get_color("player4_color"),
	}
	self:reset(my_slot)
end

function ColorAllocator:color_for(slot)
	slot = color_for_slot(slot)

	local idx = self.slot_to_index[slot]
	if idx then
		return self.cfg_colors[idx]
	end

	for i = 1, 4 do
		if not self.index_taken[i] then
			self.slot_to_index[slot] = i
			self.index_taken[i] = true
			return self.cfg_colors[i]
		end
	end

	local fallback = ((slot - 1) % 4) + 1
	return self.cfg_colors[fallback]
end

local function _on_player_removed(player)
	local slot = player and player:slot()
	if not slot then
		return
	end
	local idx = ColorAllocator.slot_to_index[slot]
	if idx then
		ColorAllocator.slot_to_index[slot] = nil
		ColorAllocator.index_taken[idx] = false
	end
end

local PlayerManager = require("scripts/foundation/managers/player/player_manager")
mod:hook(PlayerManager, "remove_player", function(orig, self, peer_id, local_player_id, ...)
	local player = self:player(peer_id, local_player_id)
	if player then
		_on_player_removed(player)
	end
	return orig(self, peer_id, local_player_id, ...)
end)

local function apply_widget_color(panel)
	if not panel or not panel._widgets_by_name or not mod:get("color_hud_names") then
		return
	end
	local slot = panel._player_slot
	if not slot then
		return
	end
	local color = ColorAllocator:color_for(slot)
	local widget = panel._widgets_by_name.player_name
	if not widget or not widget.style or not widget.style.text then
		return
	end
	local tc = widget.style.text.text_color
	if tc[2] ~= color[2] or tc[3] ~= color[3] or tc[4] ~= color[4] then
		tc[2], tc[3], tc[4] = color[2], color[3], color[4]
		if widget.style.text.default_text_color then
			local d = widget.style.text.default_text_color
			d[2], d[3], d[4] = color[2], color[3], color[4]
		end
		widget.dirty = true
	end
end

local function alias_ability_bar_widget(panel)
	local w = panel and panel._widgets_by_name
	if not w then
		return
	end
	if w.ability_bar then
		w.ability_bar_widget = w.ability_bar
	elseif not w.ability_bar_widget then
		w.ability_bar_widget = { visible = false, dirty = false, style = { texture = { color = { 255, 255, 255, 255 }, size = { 0, 0 } } } }
	end
end

mod:hook_safe("HudElementPersonalPlayerPanel", "init", function(self) alias_ability_bar_widget(self) end)
mod:hook_safe("HudElementTeamPlayerPanel",     "init", function(self) alias_ability_bar_widget(self) end)
mod:hook_safe("HudElementPlayerPanelBase",     "destroy", function(self) alias_ability_bar_widget(self) end)

local function colourise_team_panels(handler)
	local panels = handler and handler._player_panels_array
	if not panels then return end
	for i = 1, #panels do
		local p = panels[i] and panels[i].panel
		if p then apply_widget_color(p) end
	end
end

mod:hook_require("scripts/ui/hud/elements/team_panel_handler/hud_element_team_panel_handler", function(H)
	if not H.__cs_hooked then
		H.__cs_hooked = true
		mod:hook_safe(H, "update", function(self) colourise_team_panels(self) end)
	end
end)

local function install_player_panel_hooks(base)
	if not base or base.__cs_hooks then return end
	base.__cs_hooks = true
	mod:hook_safe(base, "_update_player_name_prefix", function(self)
		if self._colors_revision ~= mod._colors_revision then
			self._colors_revision = mod._colors_revision
			self._player_slot = nil
		end
		if mod:get("color_hud_names") and self._player_name_prefix and self._player_name_prefix:find("{#reset%(%)}") then
			self._player_name_prefix = self._player_name_prefix:gsub("{#reset%(%)}", "")
		end
	end)
	mod:hook_safe(base, "_set_player_name",          function(self) apply_widget_color(self) end)
	mod:hook_safe(base, "_update_player_features",   function(self) apply_widget_color(self) end)
end

mod:hook_require("scripts/ui/hud/elements/player_panel_base/hud_element_player_panel_base", function(B) install_player_panel_hooks(B) end)

mod._colors_revision = 0
local previous_slot_colors, previous_metatable

local function deep_clone(tbl)
	if not tbl then return nil end
	local c = {}
	for i, col in ipairs(tbl) do
		c[i] = { col[1], col[2], col[3], col[4] }
	end
	return c
end

local function restore_previous()
	if previous_slot_colors then
		UISettings.player_slot_colors = previous_slot_colors
		if previous_metatable then
			setmetatable(UISettings.player_slot_colors, previous_metatable)
		end
		previous_slot_colors, previous_metatable = nil, nil
		mod._colors_revision = mod._colors_revision + 1
	end
end

mod.on_unload = restore_previous

local function apply_slot_colors()
	if not previous_slot_colors then
		previous_slot_colors = deep_clone(UISettings.player_slot_colors)
		previous_metatable   = getmetatable(UISettings.player_slot_colors)
	end

	local my_slot
	local pm = Managers.player
	if pm then
		local lp = pm:local_player_safe(1)
		if lp then
			my_slot = lp:slot()
		end
	end

	ColorAllocator:setup(my_slot)

	local new_slot_colors = setmetatable({}, {
		__index = function(_, k)
			if type(k) ~= "number" or k < 1 then return nil end
			return ColorAllocator:color_for(k)
		end,
	})

	UISettings.player_slot_colors = new_slot_colors
	if previous_metatable then
		setmetatable(UISettings.player_slot_colors, previous_metatable)
	end

	mod._colors_revision = mod._colors_revision + 1
	recreate_player_hud()
end

recreate_player_hud = function()
	local ui_manager = Managers.ui
	if not ui_manager or not ui_manager._hud then return false end
	local player = Managers.player:local_player(1)
	if not player then return false end
	local hud = ui_manager._hud
	local elements, visibility_groups = hud._element_definitions, hud._visibility_groups
	hud:destroy()
	ui_manager:create_player_hud(player:peer_id(), player:local_player_id(), elements, visibility_groups)
	return true
end

local last_slot_checked, last_player_count = -1, -1

mod.update = function()
	local pm = Managers.player
	if not pm then return end
	local p = pm:local_player_safe(1)
	if not p or not p:is_human_controlled() then return end
	local s = p:slot()
	if s and s ~= last_slot_checked then last_slot_checked = s apply_slot_colors() end
	local c = pm:num_human_players() or 0
	if c ~= last_player_count then last_player_count = c apply_slot_colors() end
end

mod.on_setting_changed = function(id)
	if id == "color_nameplate" or id == "color_hud_names" then
		mod._colors_revision = mod._colors_revision + 1
		if id == "color_hud_names" then recreate_player_hud() end
		return
	end
	apply_slot_colors()
end

mod.on_all_mods_loaded = function()
	apply_slot_colors()
	if mod.command then
		mod:command("cs_sync", "sync player slot colors", function() apply_slot_colors() mod:echo("[ColorSelection] Colors synced.") end)
	end
end

mod.on_game_state_changed = function(state)
	if state == "enter" then
		apply_slot_colors()
	elseif state == "exit" then
		restore_previous()
	end
end