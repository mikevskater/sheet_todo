-- Group manager for multi-panel tabs
-- Tree-based data model: groups can have children (sub-groups)
-- Paths are dot-separated (e.g. "Work.Projects.Active")
local M = {}

local pantry = require('sheet_todo.pantry')

---@class GroupEntry
---@field name string
---@field content string Decoded content string
---@field cursor_pos { line: number, col: number }
---@field icon string? Nerd Font char or emoji
---@field icon_color string? Hex color string
---@field name_color string? Hex color string
---@field children GroupEntry[]? Sub-groups (nil = leaf)

---@class TreeNode
---@field path string Dot-separated path
---@field name string Display name
---@field level number Depth (0 = root)
---@field is_expanded boolean
---@field has_children boolean
---@field group GroupEntry

---@class GroupManagerState
---@field groups GroupEntry[]
---@field active_group string? Dot-separated path
---@field loaded boolean
local state = {
  groups = {},
  active_group = nil,
  loaded = false,
}

-- ============================================================================
-- PATH UTILITIES
-- ============================================================================

---Split a dot-separated path into segments.
---@param path string
---@return string[]
local function split_path(path)
  if not path or path == "" then return {} end
  local parts = {}
  for part in path:gmatch("[^%.]+") do
    table.insert(parts, part)
  end
  return parts
end

---Join a parent path and a child name.
---@param parent_path string
---@param name string
---@return string
local function join_path(parent_path, name)
  if not parent_path or parent_path == "" then
    return name
  end
  return parent_path .. "." .. name
end

---Get the parent path from a full path.
---@param path string
---@return string parent Empty string for root-level items
local function get_parent_path(path)
  local parts = split_path(path)
  if #parts <= 1 then return "" end
  table.remove(parts)
  return table.concat(parts, ".")
end

-- ============================================================================
-- DATA NORMALIZATION
-- ============================================================================

---Detect format and normalize to version 2 (groups format).
---@param raw_data table? Raw parsed JSON from Pantry
---@return table normalized Always in version 2 format (content still Base64-encoded)
function M.normalize(raw_data)
  if not raw_data then
    return {
      version = 2,
      groups = { { name = "Default", content = "", cursor_pos = { line = 1, col = 0 } } },
      active_group = "Default",
      last_modified = os.time(),
    }
  end

  -- Already new format
  if raw_data.version == 2 then
    return raw_data
  end

  -- Old format: wrap in single Default group
  return {
    version = 2,
    groups = {
      {
        name = "Default",
        content = raw_data.content or "",
        cursor_pos = raw_data.cursor_pos or { line = 1, col = 0 },
      },
    },
    active_group = "Default",
    last_modified = raw_data.last_modified or os.time(),
  }
end

-- ============================================================================
-- RECURSIVE DECODE / ENCODE
-- ============================================================================

---Recursively decode a group entry from Pantry format.
---@param raw table Raw group with Base64-encoded content
---@return GroupEntry
local function decode_group(raw)
  local entry = {
    name = raw.name,
    content = pantry.decode_content(raw.content),
    cursor_pos = raw.cursor_pos or { line = 1, col = 0 },
    icon = raw.icon,
    icon_color = raw.icon_color,
    name_color = raw.name_color,
    children = nil,
  }
  if raw.children and #raw.children > 0 then
    entry.children = {}
    for _, child in ipairs(raw.children) do
      table.insert(entry.children, decode_group(child))
    end
  end
  return entry
end

---Recursively encode a group entry for Pantry format.
---@param group GroupEntry
---@return table Raw group with Base64-encoded content
local function encode_group(group)
  local raw = {
    name = group.name,
    content = pantry.encode_content(group.content),
    cursor_pos = group.cursor_pos,
  }
  -- Only include optional fields if they have values
  if group.icon and group.icon ~= "" then
    raw.icon = group.icon
  end
  if group.icon_color and group.icon_color ~= "" then
    raw.icon_color = group.icon_color
  end
  if group.name_color and group.name_color ~= "" then
    raw.name_color = group.name_color
  end
  if group.children and #group.children > 0 then
    raw.children = {}
    for _, child in ipairs(group.children) do
      table.insert(raw.children, encode_group(child))
    end
  end
  return raw
end

-- ============================================================================
-- LOAD / SERIALIZE
-- ============================================================================

---Load groups from normalized data. Decodes Base64 content recursively.
---@param data table? Raw data from Pantry (or nil for empty)
function M.load(data)
  local normalized = M.normalize(data)

  state.groups = {}
  for _, g in ipairs(normalized.groups) do
    table.insert(state.groups, decode_group(g))
  end

  state.active_group = normalized.active_group
  -- Ensure active_group points to a valid group
  if not M.find_group(state.active_group) then
    state.active_group = state.groups[1] and state.groups[1].name or nil
  end

  state.loaded = true
end

---Serialize state to version 2 format ready for Pantry (Base64-encodes content recursively).
---@return table data Ready for JSON encoding and Pantry save
function M.serialize()
  local groups = {}
  for _, g in ipairs(state.groups) do
    table.insert(groups, encode_group(g))
  end

  return {
    version = 2,
    groups = groups,
    active_group = state.active_group,
    last_modified = os.time(),
  }
end

-- ============================================================================
-- GROUP LOOKUP
-- ============================================================================

---Find a group by dot-separated path. Walks the tree by segments.
---@param path string? Dot-separated path (e.g. "Work.Projects")
---@return GroupEntry? group, GroupEntry[]? parent_list, number? index_in_parent
function M.find_group(path)
  if not path or path == "" then return nil, nil, nil end

  local parts = split_path(path)
  if #parts == 0 then return nil, nil, nil end

  local current_list = state.groups
  local group = nil
  local parent_list = nil
  local index = nil

  for _, segment in ipairs(parts) do
    local found = false
    for i, g in ipairs(current_list) do
      if g.name == segment then
        group = g
        parent_list = current_list
        index = i
        current_list = g.children or {}
        found = true
        break
      end
    end
    if not found then
      return nil, nil, nil
    end
  end

  return group, parent_list, index
end

-- ============================================================================
-- GROUP QUERIES
-- ============================================================================

---Get the active group path.
---@return string?
function M.get_active_group()
  return state.active_group
end

---Get the active group's decoded content string.
---@return string
function M.get_active_content()
  local g = M.find_group(state.active_group)
  if g then
    return g.content or ""
  end
  return ""
end

---Update the active group's content in memory.
---@param content string
function M.set_active_content(content)
  local g = M.find_group(state.active_group)
  if g then
    g.content = content
  end
end

---Get the active group's cursor position.
---@return { line: number, col: number }
function M.get_active_cursor()
  local g = M.find_group(state.active_group)
  if g then
    return g.cursor_pos or { line = 1, col = 0 }
  end
  return { line = 1, col = 0 }
end

---Set the active group's cursor position.
---@param pos { line: number, col: number }
function M.set_active_cursor(pos)
  local g = M.find_group(state.active_group)
  if g then
    g.cursor_pos = pos
  end
end

---Get the root-level groups array.
---@return GroupEntry[]
function M.get_root_groups()
  return state.groups
end

-- ============================================================================
-- TREE BUILDING (for UI rendering)
-- ============================================================================

---Build a flat list of visible tree nodes for rendering.
---Only recurses into groups whose paths are in expanded_set.
---@param expanded_set table<string, boolean> Set of expanded paths
---@return TreeNode[]
function M.build_tree(expanded_set)
  local nodes = {}

  local function walk(list, parent_path, level)
    for _, g in ipairs(list) do
      local path = join_path(parent_path, g.name)
      local has_children = g.children ~= nil and #g.children > 0
      local is_expanded = has_children and (expanded_set[path] == true)

      table.insert(nodes, {
        path = path,
        name = g.name,
        level = level,
        is_expanded = is_expanded,
        has_children = has_children,
        group = g,
      })

      if is_expanded then
        walk(g.children, path, level + 1)
      end
    end
  end

  walk(state.groups, "", 0)
  return nodes
end

-- ============================================================================
-- GROUP MUTATIONS
-- ============================================================================

---Switch active group by path. Caller should save current content first.
---@param path string Dot-separated path
---@return boolean success
function M.set_active_group(path)
  local g = M.find_group(path)
  if not g then
    return false
  end
  state.active_group = path
  return true
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
  -- No dots allowed in individual names
  if name:find("%.") then
    return false
  end

  local target_list
  if parent_path == "" then
    target_list = state.groups
  else
    local parent = M.find_group(parent_path)
    if not parent then
      return false
    end
    if not parent.children then
      parent.children = {}
    end
    target_list = parent.children
  end

  -- Check for sibling duplicate
  for _, g in ipairs(target_list) do
    if g.name == name then
      return false
    end
  end

  table.insert(target_list, {
    name = name,
    content = "",
    cursor_pos = { line = 1, col = 0 },
  })
  return true
end

---Count total groups recursively (for "cannot delete last group" check).
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

  local _, parent_list, idx = M.find_group(path)
  if not parent_list or not idx then
    return false
  end

  table.remove(parent_list, idx)

  -- If active group was the deleted path or a descendant, switch to first root
  if state.active_group then
    if state.active_group == path or state.active_group:find("^" .. vim.pesc(path) .. "%.") then
      state.active_group = state.groups[1] and state.groups[1].name or nil
    end
  end

  return true
end

---Rename a group at path.
---Updates active_group if it's the renamed group or a descendant.
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

  local group, parent_list, _ = M.find_group(path)
  if not group or not parent_list then
    return false, nil
  end

  -- Check for sibling duplicate
  for _, g in ipairs(parent_list) do
    if g.name == new_name and g ~= group then
      return false, nil
    end
  end

  local old_name = group.name
  group.name = new_name

  -- Compute new full path
  local parent = get_parent_path(path)
  local new_path = join_path(parent, new_name)

  -- Update active_group reference if it matches or is a descendant
  if state.active_group then
    if state.active_group == path then
      state.active_group = new_path
    elseif state.active_group:find("^" .. vim.pesc(path) .. "%.") then
      state.active_group = new_path .. state.active_group:sub(#path + 1)
    end
  end

  return true, new_path
end

---Reorder a group up (swap with previous sibling).
---@param path string
---@return boolean success
function M.reorder_up(path)
  local _, parent_list, idx = M.find_group(path)
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
  local _, parent_list, idx = M.find_group(path)
  if not parent_list or not idx or idx >= #parent_list then
    return false
  end
  parent_list[idx], parent_list[idx + 1] = parent_list[idx + 1], parent_list[idx]
  return true
end

---Set icon for a group.
---@param path string
---@param icon string Icon character (empty string to clear)
---@return boolean success
function M.set_icon(path, icon)
  local g = M.find_group(path)
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
  local g = M.find_group(path)
  if not g then return false end
  g.icon_color = (icon_color and icon_color ~= "") and icon_color or nil
  g.name_color = (name_color and name_color ~= "") and name_color or nil
  return true
end

-- ============================================================================
-- STATE MANAGEMENT
-- ============================================================================

---Check if groups are loaded.
---@return boolean
function M.is_loaded()
  return state.loaded
end

---Get total number of groups (recursive).
---@return number
function M.get_group_count()
  return count_all_groups(state.groups)
end

---Reset all state (on close).
function M.reset()
  state.groups = {}
  state.active_group = nil
  state.loaded = false
end

-- Expose path utilities for multi_panel
M.split_path = split_path
M.join_path = join_path
M.get_parent_path = get_parent_path

return M
