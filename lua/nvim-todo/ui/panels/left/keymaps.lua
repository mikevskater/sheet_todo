-- Left panel keymap handlers (12 handlers for group CRUD and navigation).
local M = {}

local state = require('nvim-todo.ui.multi_panel.state')
local tree_state = require('nvim-todo.ui.panels.left.tree_state')
local sync = require('nvim-todo.ui.multi_panel.sync')
local right_buffer = require('nvim-todo.ui.panels.right.buffer')
local crud = require('nvim-todo.data.group.crud')
local active = require('nvim-todo.data.manager.active')
local cursor = require('nvim-todo.data.group.cursor')
local path_utils = require('nvim-todo.data.group.path')
local config = require('nvim-todo.config')

---Restore focus to the left (groups) panel after a dialog closes.
local function refocus_left()
  vim.schedule(function()
    if state.panel_state then
      state.panel_state:focus_panel(state.PANEL_GROUPS)
    end
  end)
end

function M.handle_select_group()
  local path = tree_state.get_group_under_cursor()
  if path then
    sync.switch_group(path)
  end
end

function M.handle_expand()
  local node = tree_state.get_node_under_cursor()
  if not node or not node.has_children then return end
  tree_state.expand(node.path)
  state.panel_state:render_panel(state.PANEL_GROUPS)
end

function M.handle_collapse()
  local node = tree_state.get_node_under_cursor()
  if not node then return end

  if node.has_children and state.tree_state.expanded[node.path] then
    tree_state.collapse(node.path)
    state.panel_state:render_panel(state.PANEL_GROUPS)
  else
    -- Leaf or already collapsed: jump to parent
    tree_state.jump_to_parent(node.path)
  end
end

function M.handle_add_child_group()
  local path = tree_state.get_group_under_cursor()
  if not path then
    path = ""
  end

  vim.ui.input({ prompt = "New sub-group name: " }, function(name)
    if not name or name == "" then refocus_left(); return end
    vim.schedule(function()
      if crud.add_group(path, name) then
        if path ~= "" then
          tree_state.expand(path)
        end
        state.panel_state:render_panel(state.PANEL_GROUPS)
        state.panel_state:focus_panel(state.PANEL_GROUPS)
        vim.notify("Group '" .. name .. "' added", vim.log.levels.INFO)
      else
        state.panel_state:focus_panel(state.PANEL_GROUPS)
        vim.notify("Failed to add group (duplicate name or invalid)", vim.log.levels.WARN)
      end
    end)
  end)
end

function M.handle_add_root_group()
  vim.ui.input({ prompt = "New root group name: " }, function(name)
    if not name or name == "" then refocus_left(); return end
    vim.schedule(function()
      if crud.add_group("", name) then
        state.panel_state:render_panel(state.PANEL_GROUPS)
        state.panel_state:focus_panel(state.PANEL_GROUPS)
        vim.notify("Group '" .. name .. "' added", vim.log.levels.INFO)
      else
        state.panel_state:focus_panel(state.PANEL_GROUPS)
        vim.notify("Group '" .. name .. "' already exists", vim.log.levels.WARN)
      end
    end)
  end)
end

function M.handle_delete_group()
  local path = tree_state.get_group_under_cursor()
  if not path then return end

  local node = tree_state.get_node_under_cursor()
  local has_children = node and node.has_children

  local msg = "Delete group '" .. path .. "'"
  if has_children then
    msg = msg .. " and all sub-groups"
  end
  msg = msg .. "? (y/n): "

  vim.ui.input({ prompt = msg }, function(answer)
    if answer ~= "y" and answer ~= "Y" then refocus_left(); return end
    vim.schedule(function()
      local was_active = active.get_active_group()
      local was_under = was_active == path
        or (was_active and was_active:find("^" .. vim.pesc(path) .. "%."))

      tree_state.remove_expanded_subtree(path)

      if crud.remove_group(path) then
        if was_under then
          right_buffer.set_content(active.get_active_content())
          vim.schedule(function()
            right_buffer.set_cursor(cursor.get_active_cursor())
          end)
          local new_name = active.get_active_group() or "Editor"
          local parts = path_utils.split_path(new_name)
          state.panel_state:update_panel_title(state.PANEL_EDITOR, " " .. (parts[#parts] or new_name) .. " ")
        end
        state.panel_state:render_panel(state.PANEL_GROUPS)
        state.panel_state:focus_panel(state.PANEL_GROUPS)
        vim.notify("Group '" .. path .. "' deleted", vim.log.levels.INFO)
      else
        state.panel_state:focus_panel(state.PANEL_GROUPS)
        vim.notify("Cannot delete the last group", vim.log.levels.WARN)
      end
    end)
  end)
end

function M.handle_rename_group()
  local node = tree_state.get_node_under_cursor()
  if not node then return end
  local path = node.path

  vim.ui.input({ prompt = "Rename '" .. node.name .. "' to: ", default = node.name }, function(new_name)
    if not new_name or new_name == "" or new_name == node.name then refocus_left(); return end
    vim.schedule(function()
      local ok, new_path = crud.rename_group(path, new_name)
      if ok then
        if new_path then
          tree_state.remap_expanded_paths(path, new_path)
        end

        state.panel_state:render_panel(state.PANEL_GROUPS)
        state.panel_state:focus_panel(state.PANEL_GROUPS)
        local act = active.get_active_group()
        if act then
          local parts = path_utils.split_path(act)
          state.panel_state:update_panel_title(state.PANEL_EDITOR, " " .. (parts[#parts] or act) .. " ")
        end
        vim.notify("Renamed to '" .. new_name .. "'", vim.log.levels.INFO)
      else
        state.panel_state:focus_panel(state.PANEL_GROUPS)
        vim.notify("Rename failed (duplicate name or invalid)", vim.log.levels.WARN)
      end
    end)
  end)
end

function M.handle_set_icon()
  local path = tree_state.get_group_under_cursor()
  if not path then return end

  vim.ui.input({ prompt = "Icon (Nerd Font/emoji, empty to clear): " }, function(icon)
    if icon == nil then refocus_left(); return end
    vim.schedule(function()
      crud.set_icon(path, icon)
      state.panel_state:render_panel(state.PANEL_GROUPS)
      state.panel_state:focus_panel(state.PANEL_GROUPS)
    end)
  end)
end

---Fallback color picker using presets + manual hex input.
---@param path string Group path
local function pick_color_fallback(path)
  local presets = config.get('group_color_presets') or {}
  local items = {}
  for _, p in ipairs(presets) do
    table.insert(items, p.name .. " (" .. p.color .. ")")
  end
  table.insert(items, "Custom hex...")
  table.insert(items, "Clear color")

  vim.ui.select(items, { prompt = "Pick a color:" }, function(choice, idx)
    if not choice then refocus_left(); return end
    vim.schedule(function()
      if choice == "Clear color" then
        crud.set_colors(path, nil, nil)
        state.panel_state:render_panel(state.PANEL_GROUPS)
        state.panel_state:focus_panel(state.PANEL_GROUPS)
      elseif choice == "Custom hex..." then
        vim.ui.input({ prompt = "Hex color (e.g. #FF5733): " }, function(hex)
          if not hex or hex == "" then refocus_left(); return end
          vim.schedule(function()
            crud.set_colors(path, hex, hex)
            state.panel_state:render_panel(state.PANEL_GROUPS)
            state.panel_state:focus_panel(state.PANEL_GROUPS)
          end)
        end)
      else
        local preset = presets[idx]
        if preset then
          crud.set_colors(path, preset.color, preset.color)
          state.panel_state:render_panel(state.PANEL_GROUPS)
          state.panel_state:focus_panel(state.PANEL_GROUPS)
        end
      end
    end)
  end)
end

function M.handle_set_color()
  local path = tree_state.get_group_under_cursor()
  if not path then return end

  local node = tree_state.get_node_under_cursor()
  local cp_ok, colorpicker = pcall(require, "nvim-colorpicker")
  if cp_ok then
    local initial = (node and node.group.icon_color) or "#808080"
    colorpicker.pick({
      color = initial,
      title = "Group Color: " .. (node and node.name or path),
      on_select = function(result)
        local hex = result.color
        vim.schedule(function()
          crud.set_colors(path, hex, hex)
          state.panel_state:render_panel(state.PANEL_GROUPS)
          state.panel_state:focus_panel(state.PANEL_GROUPS)
        end)
      end,
      on_cancel = function()
        vim.schedule(function()
          if state.panel_state then
            state.panel_state:focus_panel(state.PANEL_GROUPS)
          end
        end)
      end,
    })
  else
    pick_color_fallback(path)
  end
end

function M.handle_reorder_down()
  local path = tree_state.get_group_under_cursor()
  if path and crud.reorder_down(path) then
    state.panel_state:render_panel(state.PANEL_GROUPS)
    tree_state.cursor_follow_path(path)
  end
end

function M.handle_reorder_up()
  local path = tree_state.get_group_under_cursor()
  if path and crud.reorder_up(path) then
    state.panel_state:render_panel(state.PANEL_GROUPS)
    tree_state.cursor_follow_path(path)
  end
end

function M.handle_reparent()
  local node = tree_state.get_node_under_cursor()
  if not node then return end
  local path = node.path

  local targets = crud.get_reparent_targets(path)
  if #targets == 0 then
    vim.notify("No valid destinations for this group", vim.log.levels.INFO)
    return
  end

  local labels = {}
  for _, t in ipairs(targets) do
    table.insert(labels, t.label)
  end

  vim.ui.select(labels, { prompt = "Move '" .. node.name .. "' to:" }, function(choice, idx)
    if not choice or not idx then refocus_left(); return end
    vim.schedule(function()
      local target = targets[idx]
      local ok, new_path = crud.reparent_group(path, target.path)
      if ok and new_path then
        tree_state.remap_expanded_paths(path, new_path)

        -- Auto-expand dest parent so the moved group is visible
        if target.path ~= "" then
          tree_state.expand(target.path)
        end

        state.panel_state:render_panel(state.PANEL_GROUPS)
        state.panel_state:focus_panel(state.PANEL_GROUPS)
        tree_state.cursor_follow_path(new_path)

        local act = active.get_active_group()
        if act then
          local parts = path_utils.split_path(act)
          state.panel_state:update_panel_title(state.PANEL_EDITOR, " " .. (parts[#parts] or act) .. " ")
        end

        vim.notify("Moved '" .. node.name .. "' to " .. (target.path == "" and "root" or target.path), vim.log.levels.INFO)
      else
        state.panel_state:focus_panel(state.PANEL_GROUPS)
        vim.notify("Move failed (duplicate name or invalid destination)", vim.log.levels.WARN)
      end
    end)
  end)
end

return M
