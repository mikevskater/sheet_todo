---Group CRUD operations: add, rename, delete, reorder, reparent, icon, colors.
---@class nvim-todo.data.group.crud
local M = {}

local state = require('nvim-todo.data.group.state')
local tree = require('nvim-todo.data.group.tree')
local path_utils = require('nvim-todo.data.group.path')
local table_utils = require('nvim-todo.utils.table')

---Count total groups recursively.
---@param list GroupEntry[]
---@return number
local function count_all_groups(list)
  local count = 0
  for _, g in ipairs(list) do
    count = count + 1
    if g.children then
      count = count + count_all_groups(g.children)
    end
  end
  return count
end

---Check if candidate_path is a descendant of ancestor_path (or equal).
---@param candidate_path string
---@param ancestor_path string
---@return boolean
local function is_descendant_or_self(candidate_path, ancestor_path)
  return candidate_path == ancestor_path
    or candidate_path:find("^" .. vim.pesc(ancestor_path) .. "%.") ~= nil
end

---Add a new empty group as child of parent_path (or root if parent_path is "").
---Validates: no dots in name, no sibling duplicate.
---@param parent_path string Parent path ("" for root level)
---@param name string Group name (must not contain dots)
---@return boolean success
function M.add_group(parent_path, name)
  if not name or name == "" then
    return false
  end
  if name:find("%.") then
    return false
  end

  local target_list
  if parent_path == "" then
    target_list = state.groups
  else
    local parent = tree.find_group(parent_path)
    if not parent then
      return false
    end
    if not parent.children then
      parent.children = {}
    end
    target_list = parent.children
  end

  for _, g in ipairs(target_list) do
    if g.name == name then
      return false
    end
  end

  local new_entry = {
    name = name,
    content = "",
    cursor_pos = { line = 1, col = 0 },
    saved_content = "",
    dirty = false,
  }

  -- Inherit parent colors
  if parent_path ~= "" then
    local parent = tree.find_group(parent_path)
    if parent then
      new_entry.icon_color = parent.icon_color
      new_entry.name_color = parent.name_color
    end
  end

  table.insert(target_list, new_entry)
  return true
end

---Remove a group by path. Cascade deletes children.
---Cannot remove if it's the only group in the entire tree.
---If active group was under deleted subtree, switch to first root.
---@param path string
---@return boolean success
function M.remove_group(path)
  local total = count_all_groups(state.groups)
  if total <= 1 then
    return false
  end

  local _, parent_list, idx = tree.find_group(path)
  if not parent_list or not idx then
    return false
  end

  table.remove(parent_list, idx)

  -- Clean up expanded_paths for deleted subtree
  local cleaned = {}
  for _, p in ipairs(state.expanded_paths or {}) do
    if p ~= path and not p:find("^" .. vim.pesc(path) .. "%.") then
      table.insert(cleaned, p)
    end
  end
  state.expanded_paths = cleaned

  -- If active group was the deleted path or a descendant, switch to first root
  if state.active_group then
    if state.active_group == path or state.active_group:find("^" .. vim.pesc(path) .. "%.") then
      state.active_group = state.groups[1] and state.groups[1].name or nil
    end
  end

  return true
end

---Rename a group at path.
---Updates active_group and expanded_paths if they reference the renamed subtree.
---@param path string
---@param new_name string
---@return boolean success, string? new_path
function M.rename_group(path, new_name)
  if not new_name or new_name == "" then
    return false, nil
  end
  if new_name:find("%.") then
    return false, nil
  end

  local group, parent_list, _ = tree.find_group(path)
  if not group or not parent_list then
    return false, nil
  end

  for _, g in ipairs(parent_list) do
    if g.name == new_name and g ~= group then
      return false, nil
    end
  end

  group.name = new_name

  local parent = path_utils.get_parent_path(path)
  local new_path = path_utils.join_path(parent, new_name)

  state.expanded_paths = table_utils.remap_path_prefixes_array(state.expanded_paths or {}, path, new_path)

  if state.active_group then
    local remapped = table_utils.remap_path_prefixes_array({ state.active_group }, path, new_path)
    state.active_group = remapped[1]
  end

  return true, new_path
end

---Reorder a group up (swap with previous sibling).
---@param path string
---@return boolean success
function M.reorder_up(path)
  local _, parent_list, idx = tree.find_group(path)
  if not parent_list or not idx or idx <= 1 then
    return false
  end
  parent_list[idx], parent_list[idx - 1] = parent_list[idx - 1], parent_list[idx]
  return true
end

---Reorder a group down (swap with next sibling).
---@param path string
---@return boolean success
function M.reorder_down(path)
  local _, parent_list, idx = tree.find_group(path)
  if not parent_list or not idx or idx >= #parent_list then
    return false
  end
  parent_list[idx], parent_list[idx + 1] = parent_list[idx + 1], parent_list[idx]
  return true
end

---Get valid reparent destinations for a source group.
---@param source_path string
---@return { label: string, path: string }[]
function M.get_reparent_targets(source_path)
  local targets = {}
  local source_parent = path_utils.get_parent_path(source_path)

  if source_parent ~= "" then
    local grandparent = path_utils.get_parent_path(source_parent)
    if grandparent ~= "" then
      local gp_group = tree.find_group(grandparent)
      table.insert(targets, { label = "Up to: " .. (gp_group and gp_group.name or grandparent), path = grandparent })
    end
    table.insert(targets, { label = "Up to: Root", path = "" })
  end

  local sibling_list
  if source_parent == "" then
    sibling_list = state.groups
  else
    local parent_group = tree.find_group(source_parent)
    sibling_list = parent_group and parent_group.children or {}
  end

  for _, sib in ipairs(sibling_list) do
    local sib_path = path_utils.join_path(source_parent, sib.name)
    if sib_path ~= source_path and not is_descendant_or_self(sib_path, source_path) then
      table.insert(targets, { label = "Into: " .. sib.name, path = sib_path })
    end
  end

  return targets
end

---Move a group from its current parent to a new parent.
---@param source_path string Dot-separated path of group to move
---@param dest_parent_path string Dot-separated path of new parent ("" for root)
---@return boolean success, string? new_path
function M.reparent_group(source_path, dest_parent_path)
  local source_group, old_list, old_idx = tree.find_group(source_path)
  if not source_group or not old_list or not old_idx then
    return false, nil
  end

  if dest_parent_path ~= "" and is_descendant_or_self(dest_parent_path, source_path) then
    return false, nil
  end

  local dest_list
  if dest_parent_path == "" then
    dest_list = state.groups
  else
    local dest_group = tree.find_group(dest_parent_path)
    if not dest_group then
      return false, nil
    end
    if not dest_group.children then
      dest_group.children = {}
    end
    dest_list = dest_group.children
  end

  for _, g in ipairs(dest_list) do
    if g.name == source_group.name then
      return false, nil
    end
  end

  table.remove(old_list, old_idx)
  table.insert(dest_list, source_group)

  local new_path = path_utils.join_path(dest_parent_path, source_group.name)

  if state.active_group then
    local remapped = table_utils.remap_path_prefixes_array({ state.active_group }, source_path, new_path)
    state.active_group = remapped[1]
  end

  state.expanded_paths = table_utils.remap_path_prefixes_array(state.expanded_paths or {}, source_path, new_path)

  state.dirty = true
  return true, new_path
end

---Set icon for a group.
---@param path string
---@param icon string Icon character (empty string to clear)
---@return boolean success
function M.set_icon(path, icon)
  local g = tree.find_group(path)
  if not g then return false end
  g.icon = (icon and icon ~= "") and icon or nil
  return true
end

---Set colors for a group (icon + name).
---@param path string
---@param icon_color string? Hex color (nil to clear)
---@param name_color string? Hex color (nil to clear)
---@return boolean success
function M.set_colors(path, icon_color, name_color)
  local g = tree.find_group(path)
  if not g then return false end
  g.icon_color = (icon_color and icon_color ~= "") and icon_color or nil
  g.name_color = (name_color and name_color ~= "") and name_color or nil
  return true
end

---Get total number of groups (recursive).
---@return number
function M.get_group_count()
  return count_all_groups(state.groups)
end

return M
