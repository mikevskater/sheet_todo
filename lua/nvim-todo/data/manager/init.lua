---@class nvim-todo.data.manager
local M = {}

local loader = require('nvim-todo.data.manager.loader')
local saver = require('nvim-todo.data.manager.saver')
local active = require('nvim-todo.data.manager.active')

-- Loader
M.normalize = loader.normalize
M.load = loader.load
M.is_loaded = loader.is_loaded
M.get_group_count = loader.get_group_count
M.reset = loader.reset

-- Saver
M.serialize = saver.serialize
M.mark_as_saved = saver.mark_as_saved
M.has_unsaved_changes = saver.has_unsaved_changes
M.is_group_dirty = saver.is_group_dirty

-- Active
M.get_active_group = active.get_active_group
M.set_active_group = active.set_active_group
M.get_active_content = active.get_active_content
M.set_active_content = active.set_active_content
M.get_active_saved_content = active.get_active_saved_content
M.get_root_groups = active.get_root_groups
M.get_expanded_paths = active.get_expanded_paths
M.set_expanded_paths = active.set_expanded_paths
M.get_active_line_numbers = active.get_active_line_numbers
M.set_active_line_numbers = active.set_active_line_numbers

return M
