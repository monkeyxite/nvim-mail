-- nvim-mail: Neovim mail compose enhancements
-- Attachment awareness, muttlook marker visibility, and more.
local M = {}

function M.setup(opts)
  opts = opts or {}
  local attachment = require('nvim-mail.attachment')
  local marker = require('nvim-mail.marker')

  -- Attachment awareness: warn on BufWritePre
  vim.api.nvim_create_autocmd('BufWritePre', {
    buffer = 0,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local missing, match = attachment.check(lines)
      if missing then
        vim.notify(
          string.format('⚠ Mentioned "%s" but no attachment found!', match or 'attachment'),
          vim.log.levels.WARN
        )
      end
    end,
    desc = 'Mail: attachment awareness check',
  })

  -- Muttlook marker: show as virtual text
  marker.apply(0)
  vim.api.nvim_create_autocmd({ 'BufRead', 'TextChanged' }, {
    buffer = 0,
    callback = function() marker.apply(0) end,
    desc = 'Mail: muttlook marker extmark',
  })
end

return M
