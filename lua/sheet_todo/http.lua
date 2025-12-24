-- ============================================================================
-- HTTP MODULE
-- ============================================================================
-- Async HTTP client using curl via jobstart
--
-- LEARNING POINTS:
-- - Running external processes asynchronously
-- - Handling streaming output (stdout/stderr)
-- - Building curl commands programmatically
-- - Timeout handling for HTTP requests
-- ============================================================================

local config = require('sheet_todo.config')

local M = {}

-- ============================================================================
-- HTTP REQUEST FUNCTIONS
-- ============================================================================

-- Make a GET request
function M.get(url, headers, callback)
  M.request('GET', url, nil, headers, callback)
end

-- Make a POST request
function M.post(url, data, headers, callback)
  M.request('POST', url, data, headers, callback)
end

-- Make a PUT request
function M.put(url, data, headers, callback)
  M.request('PUT', url, data, headers, callback)
end

-- Make a DELETE request
function M.delete(url, headers, callback)
  M.request('DELETE', url, nil, headers, callback)
end

-- Generic HTTP request
function M.request(method, url, data, headers, callback)
  -- Build curl command
  local cmd = {'curl', '-s', '-w', '\n---HTTP_STATUS:%{http_code}---', '-X', method}
  
  -- Add SSL options for Windows (fixes exit code 35)
  if vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1 then
    table.insert(cmd, '--ssl-no-revoke')
  end
  
  -- Add timeout
  local timeout = math.floor(config.get('timeout_ms') / 1000)
  table.insert(cmd, '--max-time')
  table.insert(cmd, tostring(timeout))
  
  -- Add headers
  for key, value in pairs(headers or {}) do
    table.insert(cmd, '-H')
    table.insert(cmd, key .. ': ' .. value)
  end
  
  -- Add data for POST/PUT requests
  if data and (method == 'POST' or method == 'PUT') then
    -- If data is a table, encode as form data or JSON
    if type(data) == 'table' then
      -- Check if we should use JSON
      local content_type = headers and headers['Content-Type'] or ''
      if content_type:find('application/json') then
        table.insert(cmd, '-d')
        table.insert(cmd, vim.json.encode(data))
      else
        -- Form data
        for key, value in pairs(data) do
          table.insert(cmd, '-d')
          table.insert(cmd, key .. '=' .. M.url_encode(value))
        end
      end
    else
      table.insert(cmd, '-d')
      table.insert(cmd, tostring(data))
    end
  end
  
  -- Add URL
  table.insert(cmd, url)
  
  -- Storage for response
  local stdout_data = {}
  local stderr_data = {}
  
  -- Start the job
  local job_id = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stdout_data, line)
          end
        end
      end
    end,
    
    on_stderr = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stderr_data, line)
          end
        end
      end
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
          
          -- Parse out the HTTP status code we added with -w flag
          local body = response_text
          local status = 200
          
          local status_marker = "---HTTP_STATUS:"
          local status_start = response_text:find(status_marker)
          if status_start then
            local status_end = response_text:find("---", status_start + #status_marker)
            if status_end then
              local status_str = response_text:sub(status_start + #status_marker, status_end - 1)
              status = tonumber(status_str) or 200
              body = response_text:sub(1, status_start - 2) -- Remove status line and trailing newline
            end
          end
          
          callback({
            status = status,
            body = body
          }, nil)
        end
      end)
    end,
  })
  
  if job_id <= 0 then
    callback(nil, "Failed to start curl command")
  end
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- URL encode a string
function M.url_encode(str)
  if not str then return "" end
  str = string.gsub(str, "\n", "\r\n")
  str = string.gsub(str, "([^%w%-%.%_%~ ])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
  str = string.gsub(str, " ", "+")
  return str
end

-- Build query string from table
function M.build_query_string(params)
  if not params or vim.tbl_isempty(params) then
    return ""
  end
  
  local parts = {}
  for key, value in pairs(params) do
    table.insert(parts, M.url_encode(key) .. '=' .. M.url_encode(tostring(value)))
  end
  
  return '?' .. table.concat(parts, '&')
end

return M
