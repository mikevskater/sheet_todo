-- Expand/collapse state and cursor helpers for the left panel tree.
local M = {}

local state = require('nvim-todo.ui.multi_panel.state')
local path_utils = require('nvim-todo.data.group.path')
local active = require('nvim-todo.data.manager.active')

---Sync current expanded set to the data layer for persistence.
local function sync_to_data()
  active.set_expanded_paths(state.tree_state.expanded)
end

---Expand a tree node by path.
---@param path string
function M.expand(path)
  state.tree_state.expanded[path] = true
  sync_to_data()
end

---Collapse a node and all its descendants.
---@param path string
function M.collapse(path)
  local prefix = path .. "."
  state.tree_state.expanded[path] = nil
  for p, _ in pairs(state.tree_state.expanded) do
    if p:find("^" .. vim.pesc(prefix)) then
      state.tree_state.expanded[p] = nil
    end
  end
  sync_to_data()
end

---Move cursor to the row matching the given path in visible_nodes.
---@param path string
function M.cursor_follow_path(path)
  for i, node in ipairs(state.tree_state.visible_nodes) do
    if node.path == path then
      state.panel_state:set_cursor(state.PANEL_GROUPS, i, 0)
      break
    end
  end
end

---Get the visible tree node under cursor in the left panel.
---@return TreeNode?
function M.get_node_under_cursor()
  if not state.panel_state then return nil end
  local row = state.panel_state:get_cursor(state.PANEL_GROUPS)
  if not row then return nil end
  return state.tree_state.visible_nodes[row]
end

---Get the group path under cursor in the left panel.
---@return string?
function M.get_group_under_cursor()
  local node = M.get_node_under_cursor()
  return node and node.path or nil
end

---Remove expanded entries for a path and all its descendants.
---@param path string
function M.remove_expanded_subtree(path)
  M.collapse(path)
end

---Remap expanded paths when a group is renamed or reparented.
---@param old_prefix string Old path prefix
---@param new_prefix string New path prefix
function M.remap_expanded_paths(old_prefix, new_prefix)
  local new_expanded = {}
  for p, v in pairs(state.tree_state.expanded) do
    if p == old_prefix then
      new_expanded[new_prefix] = v
    elseif p:find("^" .. vim.pesc(old_prefix) .. "%.") then
      new_expanded[new_prefix .. p:sub(#old_prefix + 1)] = v
    else
      new_expanded[p] = v
    end
  end
  state.tree_state.expanded = new_expanded
  sync_to_data()
end

---Find parent node row and set cursor there.
---@param path string Current node path
function M.jump_to_parent(path)
  local parent_path = path_utils.get_parent_path(path)
  if parent_path ~= "" then
    for i, n in ipairs(state.tree_state.visible_nodes) do
      if n.path == parent_path then
        state.panel_state:set_cursor(state.PANEL_GROUPS, i, 0)
        break
      end
    end
  end
end

return M
