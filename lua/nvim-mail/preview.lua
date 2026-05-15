-- Inline markdown preview: render mail draft via muttlook (with thread history)
local M = {}

local marker = require('nvim-mail.marker')

--- Extract body lines (after headers, excluding muttlook markers)
---@param lines string[]
---@return string[]
function M.extract_body(lines)
  local body = {}
  local in_body = false
  for _, l in ipairs(lines) do
    if not in_body then
      if l == '' then in_body = true end
    else
      -- Skip muttlook markers
      if not l:match('^%[//%]: # %(muttlook%-') then
        body[#body + 1] = l
      end
    end
  end
  return body
end

--- Build pandoc command for markdown → HTML (fallback)
---@return string
function M.build_cmd()
  return 'pandoc -f markdown -t html5 --standalone --metadata title=Preview'
end

--- Preview current buffer via muttlook --action draft (primary)
--- Exactly mirrors the ,m send flow: save file, pipe to muttlook, open HTML
---@param bufnr? integer
function M.show(bufnr)
  bufnr = bufnr or 0

  -- Save the file first
  vim.cmd('write')
  local file = vim.fn.expand('%')

  -- Write original.msg from draft headers so muttlook can find the replied-to message
  -- (muttlook falls back to original.msg when no marker is present)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local headers = {}
  for _, l in ipairs(lines) do
    if l == '' then break end
    headers[#headers + 1] = l
  end
  local cache_dir = vim.fn.expand('~/.cache/muttlook')
  vim.fn.mkdir(cache_dir, 'p')
  local org = io.open(cache_dir .. '/original.msg', 'w')
  if org then
    org:write(table.concat(headers, '\n') .. '\n\n')
    org:close()
  end

  -- Pipe the full file to muttlook (same as ,m macro)
  vim.fn.system('cat ' .. vim.fn.shellescape(file) .. ' | muttlook --action draft')
  if vim.v.shell_error == 0 then
    local html = vim.fn.expand('~/.cache/muttlook/mimelook.html')
    vim.fn.system({ 'open', html })
  else
    vim.notify('muttlook --action draft failed', vim.log.levels.ERROR)
  end
end

return M
