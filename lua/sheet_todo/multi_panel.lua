-- Multi-panel UI for group tabs
-- Left panel: hierarchical group tree with CRUD keymaps
-- Right panel: editable markdown with all notepad features
local M = {}

local cfg = require('sheet_todo.config')
local group_manager = require('sheet_todo.group_manager')
local hide_completed = require('sheet_todo.features.hide_completed')
local folding = require('sheet_todo.features.folding')
local sticky_headers = require('sheet_todo.features.sticky_headers')

---@class MultiPanelState
---@field panel_state table? MultiPanelState from nvim-float
---@field right_buf number?
---@field right_win number?
---@field saved_content string? Last saved content (for unsaved detection)
---@field has_unsaved_changes boolean
---@field ignore_changes boolean
---@field on_save function? Save callback from init.lua
local state = {
  panel_state = nil,
  right_buf = nil,
  right_win = nil,
  saved_content = nil,
  has_unsaved_changes = false,
  ignore_changes = false,
  on_save = nil,
}

local PANEL_GROUPS = "groups"
local PANEL_EDITOR = "editor"
local unsaved_marker = "\u{25cf}"

-- ============================================================================
-- TREE STATE (UI-only, not persisted)
-- ============================================================================

local tree_state = {
  expanded = {},      -- table<string, boolean> set of expanded paths
  visible_nodes = {}, -- TreeNode[] from last render
}

local hl_cache = {} -- color hex -> highlight group name

-- ============================================================================
-- HIGHLIGHT GROUPS
-- ============================================================================

local function setup_highlights()
  vim.api.nvim_set_hl(0, 'SheetTodoActiveGroup', { default = true, bold = true })
end

---Create or retrieve a cached highlight group for a hex color.
---@param hex string Hex color (e.g. "#E06C75")
---@return string hl_group Name of the highlight group
local function get_color_hl(hex)
  if hl_cache[hex] then
    return hl_cache[hex]
  end
  -- Sanitize hex to valid hl group name
  local safe = hex:gsub("#", "")
  local name = "SheetTodo_" .. safe
  vim.api.nvim_set_hl(0, name, { fg = hex })
  hl_cache[hex] = name
  return name
end

---Get the display icon for a group.
---@param group GroupEntry
---@param is_expanded boolean
---@param has_children boolean
---@return string
local function get_group_icon(group, is_expanded, has_children)
  if group.icon and group.icon ~= "" then
    return group.icon
  end
  if has_children then
    return is_expanded and "\u{25bc}" or "\u{25b6}"  -- ▼ / ▶
  end
  return "\u{2022}"  -- •
end

-- ============================================================================
-- LEFT PANEL RENDERING
-- ============================================================================

---Render the left panel group tree.
---@param _mp_state table MultiPanelState (unused)
---@return string[] lines, table[] highlights
local function render_left_panel(_mp_state)
  local nodes = group_manager.build_tree(tree_state.expanded)
  tree_state.visible_nodes = nodes

  local lines = {}
  local highlights = {}
  local active_path = group_manager.get_active_group()

  for i, node in ipairs(nodes) do
    local indent = string.rep("  ", node.level)
    local icon = get_group_icon(node.group, node.is_expanded, node.has_children)
    local line = indent .. icon .. " " .. node.name
    table.insert(lines, line)

    local line_idx = i - 1  -- 0-indexed for nvim API
    local is_active = (node.path == active_path)

    if is_active then
      -- Active group: bold highlight on whole line, no custom color
      table.insert(highlights, {
        line = line_idx,
        col_start = 0,
        col_end = #line,
        hl_group = 'SheetTodoActiveGroup',
      })
    else
      -- Apply custom colors to icon and name spans
      local icon_start = #indent
      local icon_end = icon_start + #icon
      local name_start = icon_end + 1  -- +1 for space
      local name_end = #line

      if node.group.icon_color and node.group.icon_color ~= "" then
        table.insert(highlights, {
          line = line_idx,
          col_start = icon_start,
          col_end = icon_end,
          hl_group = get_color_hl(node.group.icon_color),
        })
      end

      if node.group.name_color and node.group.name_color ~= "" then
        table.insert(highlights, {
          line = line_idx,
          col_start = name_start,
          col_end = name_end,
          hl_group = get_color_hl(node.group.name_color),
        })
      end
    end
  end

  if #lines == 0 then
    lines = { "  (no groups)" }
  end

  return lines, highlights
end

-- ============================================================================
-- RIGHT PANEL HELPERS
-- ============================================================================

---Get content from the right panel buffer.
---@return string
local function get_right_content()
  if not state.right_buf or not vim.api.nvim_buf_is_valid(state.right_buf) then
    return ""
  end
  local lines = vim.api.nvim_buf_get_lines(state.right_buf, 0, -1, false)
  return table.concat(lines, "\n")
end

---Get full content including hidden completed tasks.
---@return string
local function get_right_full_content()
  if hide_completed.is_active() then
    return hide_completed.get_full_content(state.right_buf)
  end
  return get_right_content()
end

---Set content in the right panel buffer.
---@param content string
local function set_right_content(content)
  if not state.right_buf or not vim.api.nvim_buf_is_valid(state.right_buf) then
    return
  end

  state.ignore_changes = true

  vim.api.nvim_buf_set_option(state.right_buf, 'modifiable', true)
  local lines = vim.split(content, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(state.right_buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(state.right_buf, 'modified', false)

  state.saved_content = content
  state.has_unsaved_changes = false

  vim.schedule(function()
    state.ignore_changes = false
  end)
end

---Get cursor position from the right panel.
---@return { line: number, col: number }
local function get_right_cursor()
  if not state.right_win or not vim.api.nvim_win_is_valid(state.right_win) then
    return { line = 1, col = 0 }
  end
  local pos = vim.api.nvim_win_get_cursor(state.right_win)
  return { line = pos[1], col = pos[2] }
end

---Set cursor position in the right panel.
---@param pos { line: number, col: number }
local function set_right_cursor(pos)
  if not state.right_win or not vim.api.nvim_win_is_valid(state.right_win) then
    return
  end
  if not state.right_buf or not vim.api.nvim_buf_is_valid(state.right_buf) then
    return
  end
  local total = vim.api.nvim_buf_line_count(state.right_buf)
  local line = math.max(1, math.min(pos.line or 1, total))
  vim.api.nvim_win_set_cursor(state.right_win, { line, pos.col or 0 })
end

-- ============================================================================
-- UNSAVED STATE
-- ============================================================================

local function update_unsaved_state()
  if not state.right_buf or not vim.api.nvim_buf_is_valid(state.right_buf) then
    return
  end

  local current = get_right_content()
  local prev = state.has_unsaved_changes

  if state.saved_content then
    state.has_unsaved_changes = (current ~= state.saved_content)
  else
    state.has_unsaved_changes = (#current > 0)
  end

  -- Update right panel title if state changed
  if prev ~= state.has_unsaved_changes and state.panel_state then
    local group_name = group_manager.get_active_group() or "Editor"
    -- Show just the leaf name in the title
    local parts = group_manager.split_path(group_name)
    local display_name = parts[#parts] or group_name
    local title = state.has_unsaved_changes
      and (unsaved_marker .. " " .. display_name .. " ")
      or (" " .. display_name .. " ")
    state.panel_state:update_panel_title(PANEL_EDITOR, title)
  end
end

-- ============================================================================
-- TREE NODE HELPERS
-- ============================================================================

---Get the visible tree node under cursor in the left panel.
---@return TreeNode?
local function get_node_under_cursor()
  if not state.panel_state then return nil end
  local row = state.panel_state:get_cursor(PANEL_GROUPS)
  if not row then return nil end
  return tree_state.visible_nodes[row]
end

---Get the group path under cursor in the left panel.
---@return string?
local function get_group_under_cursor()
  local node = get_node_under_cursor()
  return node and node.path or nil
end

-- ============================================================================
-- GROUP SWITCHING
-- ============================================================================

---Switch to a different group.
---@param path string Group path to switch to
local function switch_group(path)
  if not state.panel_state then return end
  if path == group_manager.get_active_group() then return end

  -- Save current right-panel content and cursor to group_manager
  local full_content = get_right_full_content()
  hide_completed.reset()
  group_manager.set_active_content(full_content)
  group_manager.set_active_cursor(get_right_cursor())

  -- Switch active group
  group_manager.set_active_group(path)

  -- Load new group's content
  set_right_content(group_manager.get_active_content())

  -- Restore cursor
  vim.schedule(function()
    set_right_cursor(group_manager.get_active_cursor())
  end)

  -- Update right panel title (show leaf name)
  local parts = group_manager.split_path(path)
  local display_name = parts[#parts] or path
  state.panel_state:update_panel_title(PANEL_EDITOR, " " .. display_name .. " ")

  -- Re-render left panel
  state.panel_state:render_panel(PANEL_GROUPS)
end

-- ============================================================================
-- LEFT PANEL KEYMAPS
-- ============================================================================

local function handle_select_group()
  local path = get_group_under_cursor()
  if path then
    switch_group(path)
  end
end

local function handle_expand()
  local node = get_node_under_cursor()
  if not node or not node.has_children then return end
  tree_state.expanded[node.path] = true
  state.panel_state:render_panel(PANEL_GROUPS)
end

local function handle_collapse()
  local node = get_node_under_cursor()
  if not node then return end

  if node.has_children and tree_state.expanded[node.path] then
    -- Collapse: remove this path and all descendant paths from expanded
    local prefix = node.path .. "."
    tree_state.expanded[node.path] = nil
    for p, _ in pairs(tree_state.expanded) do
      if p:find("^" .. vim.pesc(prefix)) then
        tree_state.expanded[p] = nil
      end
    end
    state.panel_state:render_panel(PANEL_GROUPS)
  else
    -- Leaf or already collapsed: jump to parent
    local parent_path = group_manager.get_parent_path(node.path)
    if parent_path ~= "" then
      -- Find the parent's row in visible_nodes
      for i, n in ipairs(tree_state.visible_nodes) do
        if n.path == parent_path then
          state.panel_state:set_cursor(PANEL_GROUPS, i, 0)
          break
        end
      end
    end
  end
end

local function handle_add_child_group()
  local path = get_group_under_cursor()
  if not path then
    -- No group under cursor, add at root
    path = ""
  end

  vim.ui.input({ prompt = "New sub-group name: " }, function(name)
    if not name or name == "" then return end
    vim.schedule(function()
      if group_manager.add_group(path, name) then
        -- Auto-expand parent so the new child is visible
        if path ~= "" then
          tree_state.expanded[path] = true
        end
        state.panel_state:render_panel(PANEL_GROUPS)
        vim.notify("Group '" .. name .. "' added", vim.log.levels.INFO)
      else
        vim.notify("Failed to add group (duplicate name or invalid)", vim.log.levels.WARN)
      end
    end)
  end)
end

local function handle_add_root_group()
  vim.ui.input({ prompt = "New root group name: " }, function(name)
    if not name or name == "" then return end
    vim.schedule(function()
      if group_manager.add_group("", name) then
        state.panel_state:render_panel(PANEL_GROUPS)
        vim.notify("Group '" .. name .. "' added", vim.log.levels.INFO)
      else
        vim.notify("Group '" .. name .. "' already exists", vim.log.levels.WARN)
      end
    end)
  end)
end

local function handle_delete_group()
  local path = get_group_under_cursor()
  if not path then return end

  local node = get_node_under_cursor()
  local has_children = node and node.has_children

  local msg = "Delete group '" .. path .. "'"
  if has_children then
    msg = msg .. " and all sub-groups"
  end
  msg = msg .. "? (y/n): "

  vim.ui.input({ prompt = msg }, function(answer)
    if answer ~= "y" and answer ~= "Y" then return end
    vim.schedule(function()
      local was_active = group_manager.get_active_group()
      local was_under = was_active == path
        or (was_active and was_active:find("^" .. vim.pesc(path) .. "%."))

      -- Clean expanded state for deleted subtree
      tree_state.expanded[path] = nil
      local prefix = path .. "."
      for p, _ in pairs(tree_state.expanded) do
        if p:find("^" .. vim.pesc(prefix)) then
          tree_state.expanded[p] = nil
        end
      end

      if group_manager.remove_group(path) then
        if was_under then
          -- Load the new active group's content
          set_right_content(group_manager.get_active_content())
          vim.schedule(function()
            set_right_cursor(group_manager.get_active_cursor())
          end)
          local new_name = group_manager.get_active_group() or "Editor"
          local parts = group_manager.split_path(new_name)
          state.panel_state:update_panel_title(PANEL_EDITOR, " " .. (parts[#parts] or new_name) .. " ")
        end
        state.panel_state:render_panel(PANEL_GROUPS)
        vim.notify("Group '" .. path .. "' deleted", vim.log.levels.INFO)
      else
        vim.notify("Cannot delete the last group", vim.log.levels.WARN)
      end
    end)
  end)
end

local function handle_rename_group()
  local node = get_node_under_cursor()
  if not node then return end
  local path = node.path

  vim.ui.input({ prompt = "Rename '" .. node.name .. "' to: ", default = node.name }, function(new_name)
    if not new_name or new_name == "" or new_name == node.name then return end
    vim.schedule(function()
      local ok, new_path = group_manager.rename_group(path, new_name)
      if ok then
        -- Update expanded state: rename path prefixes
        if new_path then
          local new_expanded = {}
          for p, v in pairs(tree_state.expanded) do
            if p == path then
              new_expanded[new_path] = v
            elseif p:find("^" .. vim.pesc(path) .. "%.") then
              new_expanded[new_path .. p:sub(#path + 1)] = v
            else
              new_expanded[p] = v
            end
          end
          tree_state.expanded = new_expanded
        end

        state.panel_state:render_panel(PANEL_GROUPS)
        -- Update right panel title if this was the active group
        local active = group_manager.get_active_group()
        if active then
          local parts = group_manager.split_path(active)
          state.panel_state:update_panel_title(PANEL_EDITOR, " " .. (parts[#parts] or active) .. " ")
        end
        vim.notify("Renamed to '" .. new_name .. "'", vim.log.levels.INFO)
      else
        vim.notify("Rename failed (duplicate name or invalid)", vim.log.levels.WARN)
      end
    end)
  end)
end

local function handle_set_icon()
  local path = get_group_under_cursor()
  if not path then return end

  vim.ui.input({ prompt = "Icon (Nerd Font/emoji, empty to clear): " }, function(icon)
    if icon == nil then return end  -- cancelled
    vim.schedule(function()
      group_manager.set_icon(path, icon)
      state.panel_state:render_panel(PANEL_GROUPS)
    end)
  end)
end

local function handle_set_color()
  local path = get_group_under_cursor()
  if not path then return end

  local presets = cfg.get('group_color_presets') or {}
  local items = {}
  for _, p in ipairs(presets) do
    table.insert(items, p.name .. " (" .. p.color .. ")")
  end
  table.insert(items, "Custom hex...")
  table.insert(items, "Clear color")

  vim.ui.select(items, { prompt = "Pick a color:" }, function(choice, idx)
    if not choice then return end
    vim.schedule(function()
      if choice == "Clear color" then
        group_manager.set_colors(path, nil, nil)
        state.panel_state:render_panel(PANEL_GROUPS)
      elseif choice == "Custom hex..." then
        vim.ui.input({ prompt = "Hex color (e.g. #FF5733): " }, function(hex)
          if not hex or hex == "" then return end
          vim.schedule(function()
            group_manager.set_colors(path, hex, hex)
            state.panel_state:render_panel(PANEL_GROUPS)
          end)
        end)
      else
        -- Preset
        local preset = presets[idx]
        if preset then
          group_manager.set_colors(path, preset.color, preset.color)
          state.panel_state:render_panel(PANEL_GROUPS)
        end
      end
    end)
  end)
end

local function handle_reorder_down()
  local path = get_group_under_cursor()
  if path and group_manager.reorder_down(path) then
    state.panel_state:render_panel(PANEL_GROUPS)
    -- Move cursor down to follow the group
    local row = state.panel_state:get_cursor(PANEL_GROUPS)
    if row then
      state.panel_state:set_cursor(PANEL_GROUPS, row + 1, 0)
    end
  end
end

local function handle_reorder_up()
  local path = get_group_under_cursor()
  if path and group_manager.reorder_up(path) then
    state.panel_state:render_panel(PANEL_GROUPS)
    -- Move cursor up to follow the group
    local row = state.panel_state:get_cursor(PANEL_GROUPS)
    if row then
      state.panel_state:set_cursor(PANEL_GROUPS, row - 1, 0)
    end
  end
end

-- ============================================================================
-- RIGHT PANEL ACTIONS
-- ============================================================================

local function handle_save()
  if state.on_save then
    state.on_save()
  end
end

local function handle_revert()
  if not state.saved_content then
    vim.notify("No saved content to revert to", vim.log.levels.WARN)
    return
  end
  hide_completed.reset()
  set_right_content(state.saved_content)
  vim.notify("Reverted to last saved content", vim.log.levels.INFO)
end

local function handle_toggle_completed()
  if state.right_buf and vim.api.nvim_buf_is_valid(state.right_buf) then
    hide_completed.toggle(state.right_buf)
  end
end

local function handle_next_todo()
  if not state.right_buf or not vim.api.nvim_buf_is_valid(state.right_buf) then
    return
  end
  if not state.right_win or not vim.api.nvim_win_is_valid(state.right_win) then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(state.right_buf, 0, -1, false)
  local cursor = vim.api.nvim_win_get_cursor(state.right_win)
  local current_line = cursor[1]
  local total = #lines

  for offset = 1, total do
    local idx = ((current_line - 1 + offset) % total) + 1
    if lines[idx]:match('^%s*%- %[ %]') then
      vim.api.nvim_win_set_cursor(state.right_win, { idx, 0 })
      return
    end
  end

  vim.notify("No unchecked todos", vim.log.levels.INFO)
end

local function handle_close()
  M.close()
end

-- ============================================================================
-- CONTROLS
-- ============================================================================

---Format a key or key table for display.
---@param k string|string[]
---@return string
local function fmt_key(k)
  if type(k) == 'table' then return table.concat(k, ' / ') end
  return k
end

---Build controls array for nvim-float's "? = Controls" footer.
---@return table[]
local function build_controls()
  local km = cfg.get('keymaps')
  return {
    { header = "Groups", keys = {
      { key = "Enter", desc = "Select group" },
      { key = "zo", desc = "Expand group" },
      { key = "zc", desc = "Collapse / go to parent" },
      { key = "a", desc = "Add child group" },
      { key = "A", desc = "Add root group" },
      { key = "d", desc = "Delete group" },
      { key = "r", desc = "Rename group" },
      { key = "i", desc = "Set icon" },
      { key = "c", desc = "Set color" },
      { key = "J / K", desc = "Reorder group" },
    }},
    { header = "Editing", keys = {
      { key = fmt_key(km.save), desc = "Save to cloud" },
      { key = fmt_key(km.revert), desc = "Revert to saved" },
    }},
    { header = "View", keys = {
      { key = fmt_key(km.toggle_completed), desc = "Hide/show completed" },
      { key = fmt_key(km.next_todo), desc = "Jump to next todo" },
    }},
    { header = "Folding", keys = {
      { key = "za", desc = "Toggle fold" },
      { key = "zM", desc = "Close all folds" },
      { key = "zR", desc = "Open all folds" },
    }},
    { header = "Navigation", keys = {
      { key = "Tab / S-Tab", desc = "Switch panel" },
      { key = fmt_key(km.close), desc = "Close" },
      { key = "?", desc = "Show controls" },
    }},
  }
end

-- ============================================================================
-- FEATURE SETUP
-- ============================================================================

---Disable autocomplete on the right panel buffer.
---@param buf number
local function disable_completion(buf)
  if not cfg.get('disable_completion') then
    return
  end
  vim.b[buf].sheet_todo_buffer = true
  vim.b[buf].completion = false -- blink.cmp
  pcall(function()
    require('cmp').setup.buffer({ enabled = false }) -- nvim-cmp
  end)
end

---Set up change tracking on the right panel buffer.
---@param buf number
local function attach_change_tracking(buf)
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      if state.ignore_changes then
        return
      end
      vim.schedule(function()
        update_unsaved_state()
      end)
    end,
  })
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

---Show the multi-panel UI.
---@param on_save_callback function Save callback from init.lua
function M.show(on_save_callback)
  local ok, nvim_float = pcall(require, 'nvim-float')
  if not ok then
    vim.notify("nvim-float required for multi-panel mode", vim.log.levels.ERROR)
    return
  end

  nvim_float.ensure_setup()
  setup_highlights()

  state.on_save = on_save_callback
  state.has_unsaved_changes = false
  state.saved_content = nil
  state.ignore_changes = false

  -- Reset tree state
  tree_state.expanded = {}
  tree_state.visible_nodes = {}

  local controls = build_controls()
  local km = cfg.get('keymaps')

  local panel_state = nvim_float.create_multi_panel({
    layout = {
      split = "horizontal",
      children = {
        {
          name = PANEL_GROUPS,
          title = " Groups ",
          ratio = cfg.get('left_panel_width'),
          on_render = render_left_panel,
        },
        {
          name = PANEL_EDITOR,
          title = " Editor ",
          ratio = 1 - cfg.get('left_panel_width'),
          filetype = "markdown",
          on_create = function(buf, win)
            -- Make editable
            vim.api.nvim_buf_set_option(buf, 'modifiable', true)
            vim.api.nvim_buf_set_option(buf, 'readonly', false)
          end,
        },
      },
    },
    total_width_ratio = 0.85,
    total_height_ratio = 0.8,
    initial_focus = PANEL_EDITOR,
    controls = controls,
    on_close = function()
      M.cleanup()
    end,
  })

  if not panel_state then
    vim.notify("Failed to create multi-panel layout", vim.log.levels.ERROR)
    return
  end

  state.panel_state = panel_state
  state.right_buf = panel_state:get_panel_buffer(PANEL_EDITOR)
  state.right_win = panel_state:get_panel_window(PANEL_EDITOR)

  -- Set up right panel features
  if state.right_buf and state.right_win then
    -- Wrap and linebreak for markdown
    vim.api.nvim_set_option_value('wrap', true, { win = state.right_win })
    vim.api.nvim_set_option_value('linebreak', true, { win = state.right_win })

    -- Change tracking
    attach_change_tracking(state.right_buf)

    -- Disable autocomplete
    disable_completion(state.right_buf)

    -- Collapsible headers
    folding.setup(state.right_win, state.right_buf)

    -- Sticky headers
    sticky_headers.setup(state.right_win, state.right_buf)
  end

  -- Set up shared keymaps (both panels)
  local close_keys = km.close
  if type(close_keys) ~= 'table' then close_keys = { close_keys } end

  local shared_keymaps = {}
  for _, key in ipairs(close_keys) do
    shared_keymaps[key] = handle_close
  end
  shared_keymaps['<Tab>'] = function() panel_state:focus_next_panel() end
  shared_keymaps['<S-Tab>'] = function() panel_state:focus_prev_panel() end
  panel_state:set_keymaps(shared_keymaps)

  -- Set up left panel keymaps
  panel_state:set_panel_keymaps(PANEL_GROUPS, {
    ['<CR>'] = handle_select_group,
    ['zo'] = handle_expand,
    ['zc'] = handle_collapse,
    ['a'] = handle_add_child_group,
    ['A'] = handle_add_root_group,
    ['d'] = handle_delete_group,
    ['r'] = handle_rename_group,
    ['i'] = handle_set_icon,
    ['c'] = handle_set_color,
    ['J'] = handle_reorder_down,
    ['K'] = handle_reorder_up,
  })

  -- Set up right panel keymaps
  local right_keymaps = {}
  local save_key = km.save
  if type(save_key) == 'table' then save_key = save_key[1] end
  right_keymaps[save_key] = handle_save

  local revert_key = km.revert
  if type(revert_key) == 'table' then revert_key = revert_key[1] end
  right_keymaps[revert_key] = handle_revert

  local toggle_key = km.toggle_completed
  if type(toggle_key) == 'table' then toggle_key = toggle_key[1] end
  right_keymaps[toggle_key] = handle_toggle_completed

  local next_key = km.next_todo
  if type(next_key) == 'table' then next_key = next_key[1] end
  right_keymaps[next_key] = handle_next_todo

  panel_state:set_panel_keymaps(PANEL_EDITOR, right_keymaps)

  -- Insert-mode save keymap on right panel
  if state.right_buf and vim.api.nvim_buf_is_valid(state.right_buf) then
    vim.keymap.set('i', save_key, handle_save, { buffer = state.right_buf, nowait = true, silent = true })
  end
end

---Set content in the right panel (called after loading from Pantry).
---@param content string
function M.set_content(content)
  set_right_content(content)
end

---Get content from the right panel.
---@return string
function M.get_content()
  return get_right_full_content()
end

---Get cursor position from the right panel.
---@return { line: number, col: number }
function M.get_cursor()
  return get_right_cursor()
end

---Set cursor position in the right panel.
---@param pos { line: number, col: number }
function M.set_cursor(pos)
  set_right_cursor(pos)
end

---Mark content as saved.
function M.mark_as_saved()
  state.saved_content = get_right_content()
  state.has_unsaved_changes = false
  if state.panel_state then
    local name = group_manager.get_active_group() or "Editor"
    local parts = group_manager.split_path(name)
    local display_name = parts[#parts] or name
    state.panel_state:update_panel_title(PANEL_EDITOR, " " .. display_name .. " ")
  end
end

---Render the left panel (refresh group list).
function M.render_groups()
  if state.panel_state then
    state.panel_state:render_panel(PANEL_GROUPS)
  end
end

---Update the right panel title with active group name.
function M.update_editor_title()
  if state.panel_state then
    local name = group_manager.get_active_group() or "Editor"
    local parts = group_manager.split_path(name)
    local display_name = parts[#parts] or name
    state.panel_state:update_panel_title(PANEL_EDITOR, " " .. display_name .. " ")
  end
end

---Set ignore changes flag (used during spinner/loading).
---@param value boolean
function M.set_ignore_changes(value)
  state.ignore_changes = value
end

---Clean up on close.
function M.cleanup()
  -- Save current right-panel content to group_manager
  if state.right_buf and vim.api.nvim_buf_is_valid(state.right_buf) then
    local full_content = get_right_full_content()
    group_manager.set_active_content(full_content)
    group_manager.set_active_cursor(get_right_cursor())
  end

  sticky_headers.cleanup()
  hide_completed.reset()

  state.panel_state = nil
  state.right_buf = nil
  state.right_win = nil
  state.saved_content = nil
  state.has_unsaved_changes = false
  state.ignore_changes = false
  state.on_save = nil

  -- Reset tree UI state
  tree_state.expanded = {}
  tree_state.visible_nodes = {}
  hl_cache = {}
end

---Close the multi-panel UI.
function M.close()
  if state.panel_state then
    state.panel_state:close()
  end
end

---Check if multi-panel is currently open.
---@return boolean
function M.is_open()
  return state.panel_state ~= nil
    and state.right_win ~= nil
    and vim.api.nvim_win_is_valid(state.right_win)
end

return M
