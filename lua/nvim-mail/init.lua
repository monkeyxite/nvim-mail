-- nvim-mail: Neovim mail compose enhancements
-- Replaces vim-mail with pure Lua: navigation, attachment awareness,
-- muttlook markers, thread context, contacts, preview, snippets.
local M = {}

M.config = {
  contacts = {
    cmd = 'khard',
    args = { 'email', '-p', '--remove-first-line' },
  },
  snippets = nil,
  from_list = {},
  spell_langs = { 'en', 'sv' },
  prefix = ',m', -- keymap prefix (localleader-based)
}

function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend('force', M.config, opts)

  local attachment = require('nvim-mail.attachment')
  local marker = require('nvim-mail.marker')
  local thread = require('nvim-mail.thread')
  local preview = require('nvim-mail.preview')
  local snippets = require('nvim-mail.snippets')
  local nav = require('nvim-mail.navigate')

  -- Apply user config
  if opts.contacts then
    local contacts = require('nvim-mail.contacts')
    contacts.config = vim.tbl_deep_extend('force', contacts.config, opts.contacts)
  end
  if opts.snippets then snippets.config = vim.tbl_deep_extend('force', snippets.config, opts.snippets) end

  local p = M.config.prefix
  local map = function(key, fn, desc)
    vim.keymap.set('n', p .. key, fn, { buffer = true, desc = desc })
  end

  -- === Navigation (replaces vim-mail) ===
  map('t', function() nav.goto_field('^[Tt]o:', 'A') end, ' To:')
  map('c', function() nav.goto_field('^[Cc]c:', 'A') end, ' Cc:')
  map('b', function() nav.goto_field('^[Bb]cc:', 'A') end, ' Bcc:')
  map('s', function() nav.goto_field('^[Ss]ubject:', 'A') end, ' Subject:')
  map('f', function() nav.goto_field('^[Ff]rom:', 'A') end, ' From:')
  map('F', function() nav.switch_from(M.config.from_list) end, ' Switch From')
  map('R', function() nav.goto_field('^[Rr]eply%-[Tt]o:', 'A') end, ' Reply-To:')
  map('B', function() nav.goto_body() end, ' Body')
  map('S', function() nav.goto_signature() end, ' Signature')
  map('r', function() nav.goto_reply() end, ' Jump to reply')
  map('E', function() nav.goto_end_of_reply() end, ' End of reply')
  map('k', function() nav.kill_quoted_sig() end, ' Kill quoted sig')
  map('l', function() nav.switch_spell(M.config.spell_langs) end, ' Switch spell')

  -- === New features ===
  map('T', function() thread.show(0) end, ' Thread context')
  map('p', function() preview.show(0) end, ' Preview HTML')

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

  -- Smart snippets: load context-aware snippets
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  snippets.load_for_buffer(lines)
end

return M
