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
--- Renders markdown with template, joins with thread history via marker
---@param bufnr? integer
function M.show(bufnr)
  bufnr = bufnr or 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local text = table.concat(lines, '\n')

  -- Use muttlook --action draft (handles markers, thread history, template)
  local output = vim.fn.system('muttlook --action draft', text)
  if vim.v.shell_error == 0 then
    local html = vim.fn.expand('~/.cache/muttlook/mimelook.html')
    vim.fn.system({ 'open', html })
  else
    -- Fallback to plain pandoc
    local body = M.extract_body(lines)
    local body_text = table.concat(body, '\n')
    local html = vim.fn.system(M.build_cmd(), body_text)
    if vim.v.shell_error ~= 0 then
      vim.notify('Preview failed: ' .. html, vim.log.levels.ERROR)
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
end

return M
