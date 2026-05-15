-- nvim-mail: Neovim mail compose enhancements
-- Attachment awareness, muttlook marker visibility, thread context,
-- contact completion, preview, and smart snippets.
local M = {}

M.config = {
  -- Contact completion
  contacts = {
    cmd = 'khard',
    args = { 'email', '-p', '--remove-first-line' },
  },
  -- Snippet domain→context mapping (override in setup)
  snippets = nil,
}

function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend('force', M.config, opts)

  local attachment = require('nvim-mail.attachment')
  local marker = require('nvim-mail.marker')
  local thread = require('nvim-mail.thread')
  local preview = require('nvim-mail.preview')
  local contacts = require('nvim-mail.contacts')
  local snippets = require('nvim-mail.snippets')

  -- Apply user config
  if opts.contacts then contacts.config = vim.tbl_deep_extend('force', contacts.config, opts.contacts) end
  if opts.snippets then snippets.config = vim.tbl_deep_extend('force', snippets.config, opts.snippets) end

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

  -- Thread context: <leader>mt
  vim.keymap.set('n', '<leader>mt', function()
    thread.show(0)
  end, { buffer = true, desc = '[T]hread context (notmuch)' })

  -- Preview: <leader>mp
  vim.keymap.set('n', '<leader>mp', function()
    preview.show(0)
  end, { buffer = true, desc = '[P]review mail as HTML' })

  -- Contact completion: register cmp source
  contacts.register_cmp()

  -- Smart snippets: load context-aware snippets
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  snippets.load_for_buffer(lines)
end

return M
