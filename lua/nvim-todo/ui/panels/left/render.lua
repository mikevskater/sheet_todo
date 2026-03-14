-- Left panel render callback for nvim-float's on_render.
local M = {}

local state = require('nvim-todo.ui.multi_panel.state')
local tree = require('nvim-todo.data.group.tree')
local active = require('nvim-todo.data.manager.active')
local highlights = require('nvim-todo.ui.highlights')
local icons = require('nvim-todo.ui.icons')

local ns_virt = vim.api.nvim_create_namespace('nvim_todo_virt')

---Count unchecked todos (- [ ]) in group content.
---@param group GroupEntry
---@return number
local function count_open_todos(group)
  if not group.content or group.content == "" then return 0 end
  local count = 0
  for _ in group.content:gmatch("%- %[ %]") do
    count = count + 1
  end
  return count
end

---Render the left panel group tree.
---@param _mp_state table MultiPanelState (unused)
---@return string[] lines, table[] highlights
function M.render(_mp_state)
  local nodes = tree.build_tree(state.tree_state.expanded)
  state.tree_state.visible_nodes = nodes

  local lines = {}
  local hls = {}
  local virt_texts = {}
  local active_path = active.get_active_group()

  for i, node in ipairs(nodes) do
    local indent = string.rep("  ", node.level)
    local icon = icons.get_group_icon(node.group, node.is_expanded, node.has_children)
    local line = indent .. icon .. " " .. node.name

    table.insert(lines, line)

    local line_idx = i - 1  -- 0-indexed for nvim API

    -- Apply icon/name color highlights (same for active and non-active)
    local icon_start = #indent
    local icon_end = icon_start + #icon
    local name_start = icon_end + 1
    local name_end = name_start + #node.name

    if node.group.icon_color and node.group.icon_color ~= "" then
      table.insert(hls, {
        line = line_idx,
        col_start = icon_start,
        col_end = icon_end,
        hl_group = highlights.get_color_hl(node.group.icon_color),
      })
    end

    if node.group.name_color and node.group.name_color ~= "" then
      table.insert(hls, {
        line = line_idx,
        col_start = name_start,
        col_end = name_end,
        hl_group = highlights.get_color_hl(node.group.name_color),
      })
    end

    -- Build virtual text chunks for this line
    local is_active = (node.path == active_path)
    local is_dirty = is_active and state.has_unsaved_changes or (not is_active and node.group.dirty == true)
    local chunks = {}

    local todo_count = count_open_todos(node.group)
    if todo_count > 0 then
      table.insert(chunks, { '(' .. todo_count .. ')', 'NvimTodoCount' })
    end

    if is_dirty then
      table.insert(chunks, { state.unsaved_marker, 'NvimTodoUnsaved' })
    end

    if is_active then
      table.insert(chunks, { '\u{2192}', 'NvimTodoActiveArrow' })
    end

    -- Single-space separator before first chunk only
    if #chunks > 0 then
      chunks[1][1] = ' ' .. chunks[1][1]
    end

    virt_texts[line_idx] = chunks
  end

  if #lines == 0 then
    lines = { "  (no groups)" }
  end

  -- Apply extmarks after nvim-float writes buffer content
  vim.schedule(function()
    if not state.left_buf or not vim.api.nvim_buf_is_valid(state.left_buf) then return end
    vim.api.nvim_buf_clear_namespace(state.left_buf, ns_virt, 0, -1)
    for line_idx, chunks in pairs(virt_texts) do
      if #chunks > 0 then
        vim.api.nvim_buf_set_extmark(state.left_buf, ns_virt, line_idx, 0, {
          virt_text = chunks,
          virt_text_pos = 'eol',
        })
      end
    end
  end)

  return lines, hls
end

return M
