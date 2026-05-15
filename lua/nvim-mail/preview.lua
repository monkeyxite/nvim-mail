-- Inline markdown preview: render mail body as HTML and open in browser
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

--- Build pandoc command for markdown → HTML
---@return string
function M.build_cmd()
  return 'pandoc -f markdown -t html5 --standalone --metadata title=Preview'
end

--- Preview current buffer's body as HTML in browser
---@param bufnr? integer
function M.show(bufnr)
  bufnr = bufnr or 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local body = M.extract_body(lines)
  local text = table.concat(body, '\n')

  local cmd = M.build_cmd()
  local html = vim.fn.system(cmd, text)
  if vim.v.shell_error ~= 0 then
    vim.notify('pandoc failed: ' .. html, vim.log.levels.ERROR)
    return
  end

  local tmp = '/tmp/nvim-mail-preview.html'
  local f = io.open(tmp, 'w')
  if f then
    f:write(html)
    f:close()
    vim.fn.system({ 'open', tmp })
  end
end

return M
