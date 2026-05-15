-- Thread context: show notmuch thread in a vsplit
local M = {}

local marker = require('nvim-mail.marker')

--- Extract message-id from headers or muttlook marker
---@param lines string[]
---@return string? msgid (without angle brackets)
function M.extract_msgid(lines)
  -- First try In-Reply-To header
  for _, l in ipairs(lines) do
    if l == '' then break end -- end of headers
    local id = l:match('^In%-Reply%-To:%s*<?([^>]+)>?')
    if id then return id end
  end
  -- Fallback to muttlook marker
  local markers = marker.find_markers(lines)
  if markers.reply_to then
    -- Strip angle brackets if present
    return markers.reply_to.msgid:match('^<?([^>]+)>?$')
  end
  return nil
end

--- Build notmuch command to show thread
---@param msgid string
---@return string
function M.build_cmd(msgid)
  return string.format('notmuch show --format=text --entire-thread=true thread:{id:%s}', msgid)
end

--- Open thread context in a vsplit
---@param bufnr? integer
function M.show(bufnr)
  bufnr = bufnr or 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local msgid = M.extract_msgid(lines)
  if not msgid then
    vim.notify('No reply-to found — cannot show thread', vim.log.levels.WARN)
    return
  end
  local cmd = M.build_cmd(msgid)
  local output = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    vim.notify('notmuch failed: ' .. output, vim.log.levels.ERROR)
    return
  end
  vim.cmd('vnew')
  vim.bo.buftype = 'nofile'
  vim.bo.filetype = 'mail'
  vim.bo.swapfile = false
  vim.api.nvim_buf_set_name(0, '[Thread: ' .. msgid:sub(1, 30) .. ']')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(output, '\n'))
  vim.bo.modifiable = false
end

return M
