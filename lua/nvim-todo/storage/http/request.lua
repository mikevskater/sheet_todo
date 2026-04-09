---@class nvim-todo.storage.http.request
local M = {}

local config = require('nvim-todo.config')

---@class HttpResponse
---@field status number HTTP status code
---@field body string Response body

---Parse HTTP status code from curl's -w output marker.
---@param response_text string Raw curl stdout
---@return string body Response body without status marker
---@return number status HTTP status code
local function parse_response(response_text)
  local body = response_text
  local status = 200
  local status_marker = "---HTTP_STATUS:"
  local status_start = response_text:find(status_marker)
  if status_start then
    local status_end = response_text:find("---", status_start + #status_marker)
    if status_end then
      local status_str = response_text:sub(status_start + #status_marker, status_end - 1)
      status = tonumber(status_str) or 200
      body = response_text:sub(1, status_start - 2)
    end
  end
  return body, status
end

---Execute an async HTTP request via curl and jobstart.
---@param method string HTTP method (GET, POST, PUT, DELETE)
---@param url string Request URL
---@param data any? Request body (string or table)
---@param headers table<string, string>? HTTP headers
---@param callback fun(response: HttpResponse?, err: string?)
function M.request(method, url, data, headers, callback)
  local cmd = { 'curl', '-s', '-w', '\n---HTTP_STATUS:%{http_code}---', '-X', method }
  local request_body = nil

  -- Windows SSL fix
  if vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1 then
    table.insert(cmd, '--ssl-no-revoke')
  end

  -- Timeout
  local timeout = math.floor(config.get('timeout_ms') / 1000)
  table.insert(cmd, '--max-time')
  table.insert(cmd, tostring(timeout))

  -- Headers
  for key, value in pairs(headers or {}) do
    table.insert(cmd, '-H')
    table.insert(cmd, key .. ': ' .. value)
  end

  -- Request body for POST/PUT via stdin
  if data and (method == 'POST' or method == 'PUT') then
    if type(data) == 'table' then
      local content_type = headers and headers['Content-Type'] or ''
      if content_type:find('application/json') then
        request_body = vim.json.encode(data)
      else
        local parts = {}
        for key, value in pairs(data) do
          table.insert(parts, key .. '=' .. tostring(value))
        end
        request_body = table.concat(parts, '&')
      end
    else
      request_body = tostring(data)
    end
    table.insert(cmd, '--data-binary')
    table.insert(cmd, '@-')
  end

  table.insert(cmd, url)

  local stdout_data = {}
  local stderr_data = {}

  -- Append a chunk of jobstart "lines" to `buf`, honoring the rule from
  -- `:h channel-lines`: the first item of every subsequent on_stdout/on_stderr
  -- invocation is a *continuation* of the previous chunk's last line, not a
  -- new line. Joining with "\n" unconditionally (as the old code did) splices
  -- stray newlines into the middle of tokens when a buffer boundary falls
  -- mid-line, which can corrupt JSON keys/values.
  local function append_chunk(buf, recv_data)
    if not recv_data or #recv_data == 0 then return end
    for i, line in ipairs(recv_data) do
      if i == 1 and #buf > 0 then
        buf[#buf] = buf[#buf] .. line
      else
        table.insert(buf, line)
      end
    end
  end

  local job_opts = {
    stdin = request_body and 'pipe' or nil,
    on_stdout = function(_, recv_data, _)
      append_chunk(stdout_data, recv_data)
    end,
    on_stderr = function(_, recv_data, _)
      append_chunk(stderr_data, recv_data)
    end,
    on_exit = function(_, exit_code, _)
      vim.schedule(function()
        if exit_code ~= 0 then
          local error_msg = #stderr_data > 0
            and table.concat(stderr_data, "\n")
            or "Request failed with exit code " .. exit_code
          callback(nil, error_msg)
        else
          local response_text = table.concat(stdout_data, "\n")
          local body, status = parse_response(response_text)
          callback({ status = status, body = body }, nil)
        end
      end)
    end,
  }

  local job_id = vim.fn.jobstart(cmd, job_opts)

  if job_id <= 0 then
    callback(nil, "Failed to start curl command")
    return
  end

  if request_body then
    vim.fn.chansend(job_id, request_body)
    vim.fn.chanclose(job_id, 'stdin')
  end
end

return M
