-- The show() orchestrator for multi-panel UI.
local M = {}

local state = require('nvim-todo.ui.multi_panel.state')
local highlights = require('nvim-todo.ui.highlights')
local statuscolumn = require('nvim-todo.ui.multi_panel.statuscolumn')
local controls_mod = require('nvim-todo.ui.multi_panel.controls')
local right_buffer = require('nvim-todo.ui.panels.right.buffer')
local change_tracker = require('nvim-todo.ui.panels.right.change_tracker')
local left_render = require('nvim-todo.ui.panels.left.render')
local left_keymaps = require('nvim-todo.ui.panels.left.keymaps')
local right_keymaps = require('nvim-todo.ui.panels.right.keymaps')
local active = require('nvim-todo.data.manager.active')
local config = require('nvim-todo.config')
local folding = require('nvim-todo.features.folding')
local sticky_headers = require('nvim-todo.features.sticky_headers')

---Show the multi-panel UI.
---@param on_save_callback function Save callback from init.lua
function M.show(on_save_callback)
  local ok, nvim_float = pcall(require, 'nvim-float')
  if not ok then
    vim.notify("nvim-float required for multi-panel mode", vim.log.levels.ERROR)
    return
  end

  nvim_float.ensure_setup()
  highlights.setup()
  statuscolumn.setup_global()

  state.on_save = on_save_callback
  state.has_unsaved_changes = false
  state.saved_content = nil
  state.ignore_changes = false

  -- Restore tree state from data layer (persisted expanded paths)
  state.tree_state.expanded = active.get_expanded_paths()
  state.tree_state.visible_nodes = {}

  local controls = controls_mod.build_controls()
  local km = config.get('keymaps')

  local panel_state = nvim_float.create_multi_panel({
    layout = {
      split = "horizontal",
      children = {
        {
          name = state.PANEL_GROUPS,
          title = " Groups ",
          ratio = config.get('left_panel_width'),
          on_render = left_render.render,
          cursorline = false,
        },
        {
          name = state.PANEL_EDITOR,
          title = " Editor ",
          ratio = 1 - config.get('left_panel_width'),
          filetype = "markdown",
          on_create = function(buf, win)
            vim.api.nvim_buf_set_option(buf, 'modifiable', true)
            vim.api.nvim_buf_set_option(buf, 'readonly', false)
          end,
        },
      },
    },
    total_width_ratio = 0.85,
    total_height_ratio = 0.8,
    initial_focus = state.PANEL_EDITOR,
    controls = controls,
    on_close = function()
      require('nvim-todo.ui.multi_panel.close').cleanup()
    end,
  })

  if not panel_state then
    vim.notify("Failed to create multi-panel layout", vim.log.levels.ERROR)
    return
  end

  state.panel_state = panel_state
  state.left_buf = panel_state:get_panel_buffer(state.PANEL_GROUPS)
  state.right_buf = panel_state:get_panel_buffer(state.PANEL_EDITOR)
  state.right_win = panel_state:get_panel_window(state.PANEL_EDITOR)

  -- Set up right panel features
  if state.right_buf and state.right_win then
    vim.api.nvim_set_option_value('wrap', true, { win = state.right_win })
    vim.api.nvim_set_option_value('linebreak', true, { win = state.right_win })

    local ln_on = active.get_active_line_numbers()
    vim.api.nvim_set_option_value('number', ln_on, { win = state.right_win })
    vim.api.nvim_set_option_value('relativenumber', ln_on and vim.o.relativenumber or false, { win = state.right_win })

    statuscolumn.apply()
    change_tracker.attach(state.right_buf)
    controls_mod.disable_completion(state.right_buf)
    folding.setup(state.right_win, state.right_buf)
    sticky_headers.setup(state.right_win, state.right_buf)
  end

  -- Shared keymaps (both panels)
  local close_keys = km.close
  if type(close_keys) ~= 'table' then close_keys = { close_keys } end

  local shared_keymaps = {}
  for _, key in ipairs(close_keys) do
    shared_keymaps[key] = right_keymaps.handle_close
  end

  local save_key = km.save
  if type(save_key) == 'table' then save_key = save_key[1] end
  shared_keymaps[save_key] = right_keymaps.handle_save

  local function toggle_panel_focus()
    local cur_win = vim.api.nvim_get_current_win()
    local groups_win = panel_state:get_panel_window(state.PANEL_GROUPS)
    local editor_win = panel_state:get_panel_window(state.PANEL_EDITOR)
    if cur_win == groups_win then
      panel_state:focus_panel(state.PANEL_EDITOR)
    else
      panel_state:focus_panel(state.PANEL_GROUPS)
    end
  end
  shared_keymaps['<Tab>'] = toggle_panel_focus
  shared_keymaps['<S-Tab>'] = toggle_panel_focus
  panel_state:set_keymaps(shared_keymaps)

  -- Left panel keymaps
  panel_state:set_panel_keymaps(state.PANEL_GROUPS, {
    ['<CR>'] = left_keymaps.handle_select_group,
    ['zo'] = left_keymaps.handle_expand,
    ['zc'] = left_keymaps.handle_collapse,
    ['a'] = left_keymaps.handle_add_child_group,
    ['A'] = left_keymaps.handle_add_root_group,
    ['d'] = left_keymaps.handle_delete_group,
    ['r'] = left_keymaps.handle_rename_group,
    ['i'] = left_keymaps.handle_set_icon,
    ['c'] = left_keymaps.handle_set_color,
    ['J'] = left_keymaps.handle_reorder_down,
    ['K'] = left_keymaps.handle_reorder_up,
    ['m'] = left_keymaps.handle_reparent,
    ['<2-LeftMouse>'] = left_keymaps.handle_select_group,
  })

  -- Right panel keymaps
  local right_km = {}
  local save_key2 = km.save
  if type(save_key2) == 'table' then save_key2 = save_key2[1] end
  right_km[save_key2] = right_keymaps.handle_save

  local revert_key = km.revert
  if type(revert_key) == 'table' then revert_key = revert_key[1] end
  right_km[revert_key] = right_keymaps.handle_revert

  local toggle_key = km.toggle_completed
  if type(toggle_key) == 'table' then toggle_key = toggle_key[1] end
  right_km[toggle_key] = right_keymaps.handle_toggle_completed

  local next_key = km.next_todo
  if type(next_key) == 'table' then next_key = next_key[1] end
  right_km[next_key] = right_keymaps.handle_next_todo

  local line_num_key = km.toggle_line_numbers
  if type(line_num_key) == 'table' then line_num_key = line_num_key[1] end
  right_km[line_num_key] = right_keymaps.handle_toggle_line_numbers

  local checkbox_key = km.toggle_checkbox
  if type(checkbox_key) == 'table' then checkbox_key = checkbox_key[1] end
  right_km[checkbox_key] = right_keymaps.handle_toggle_checkbox

  -- Custom fold keymaps
  right_km['za'] = function() folding.toggle_fold() end
  right_km['zM'] = function() folding.close_all_folds() end
  right_km['zR'] = function() folding.open_all_folds() end

  panel_state:set_panel_keymaps(state.PANEL_EDITOR, right_km)

  -- Insert-mode save keymap on right panel
  if state.right_buf and vim.api.nvim_buf_is_valid(state.right_buf) then
    vim.keymap.set('i', save_key2, right_keymaps.handle_save, { buffer = state.right_buf, nowait = true, silent = true })
  end
end

return M
