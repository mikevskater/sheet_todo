-- Shared UI state singleton for multi-panel system.
-- All panel modules require() this for shared access.

---@class MultiPanelState
---@field panel_state table? MultiPanelState from nvim-float
---@field left_buf number?
---@field right_buf number?
---@field right_win number?
---@field saved_content string? Last saved content (for unsaved detection)
---@field has_unsaved_changes boolean
---@field ignore_changes boolean
---@field on_save function? Save callback from init.lua
---@field tree_state MultiPanelTreeState

---@class MultiPanelTreeState
---@field expanded table<string, boolean> Set of expanded paths
---@field visible_nodes TreeNode[] From last render

local PANEL_GROUPS = "groups"
local PANEL_EDITOR = "editor"
local unsaved_marker = "\u{25cf}"

---@type MultiPanelState
local state = {
  panel_state = nil,
  left_buf = nil,
  right_buf = nil,
  right_win = nil,
  saved_content = nil,
  has_unsaved_changes = false,
  ignore_changes = false,
  on_save = nil,
  tree_state = {
    expanded = {},
    visible_nodes = {},
  },
}

---Reset all UI state to defaults.
function state.reset()
  state.panel_state = nil
  state.left_buf = nil
  state.right_buf = nil
  state.right_win = nil
  state.saved_content = nil
  state.has_unsaved_changes = false
  state.ignore_changes = false
  state.on_save = nil
  state.tree_state.expanded = {}
  state.tree_state.visible_nodes = {}
end

state.PANEL_GROUPS = PANEL_GROUPS
state.PANEL_EDITOR = PANEL_EDITOR
state.unsaved_marker = unsaved_marker

return state
