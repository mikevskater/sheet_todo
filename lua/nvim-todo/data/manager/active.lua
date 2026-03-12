---Active group accessors: get/set active group, content, line numbers, expanded paths.
---@class nvim-todo.data.manager.active
local M = {}

local state = require('nvim-todo.data.group.state')
local tree = require('nvim-todo.data.group.tree')

---Get the active group path.
---@return string?
function M.get_active_group()
  return state.active_group
end

---Switch active group by path. Caller should save current content first.
---@param path string Dot-separated path
---@return boolean success
function M.set_active_group(path)
  local g = tree.find_group(path)
  if not g then
    return false
  end
  state.active_group = path
  return true
end

---Get the active group's decoded content string.
---@return string
function M.get_active_content()
  local g = tree.find_group(state.active_group)
  if g then
    return g.content or ""
  end
  return ""
end

---Update the active group's content in memory.
---@param content string
function M.set_active_content(content)
  local g = tree.find_group(state.active_group)
  if g then
    g.content = content
    g.dirty = (content ~= (g.saved_content or ""))
    state.dirty = true
  end
end

---Get the active group's last-saved content (Pantry snapshot).
---@return string?
function M.get_active_saved_content()
  local g = tree.find_group(state.active_group)
  if g then
    return g.saved_content
  end
  return nil
end

---Get the root-level groups array.
---@return GroupEntry[]
function M.get_root_groups()
  return state.groups
end

---Get the persisted expanded paths as a set (table<string, boolean>).
---@return table<string, boolean>
function M.get_expanded_paths()
  local set = {}
  for _, p in ipairs(state.expanded_paths or {}) do
    set[p] = true
  end
  return set
end

---Set the expanded paths from a set (table<string, boolean>).
---@param expanded_set table<string, boolean>
function M.set_expanded_paths(expanded_set)
  local paths = {}
  for p, v in pairs(expanded_set) do
    if v then
      table.insert(paths, p)
    end
  end
  state.expanded_paths = paths
end

---Get the active group's line_numbers setting.
---@return boolean
function M.get_active_line_numbers()
  local g = tree.find_group(state.active_group)
  if g then
    return g.line_numbers == true
  end
  return false
end

---Set the active group's line_numbers setting.
---@param enabled boolean
function M.set_active_line_numbers(enabled)
  local g = tree.find_group(state.active_group)
  if g then
    g.line_numbers = enabled or nil
  end
end

return M
