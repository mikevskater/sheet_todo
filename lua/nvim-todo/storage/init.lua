---@class nvim-todo.storage
local M = {}

M.http = require('nvim-todo.storage.http')
M.pantry = require('nvim-todo.storage.pantry')

return M
