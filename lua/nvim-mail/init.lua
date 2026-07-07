-- nvim-mail: Neovim mail compose enhancements
-- Replaces vim-mail with pure Lua: navigation, attachment awareness,
-- muttlook markers, thread context, contacts, preview, snippets, send.
local M = {}

M.config = {
  contacts = {
    cmd = 'khard',
    args = { 'email', '-p', '--remove-first-line' },
  },
  snippets = nil,
  from_list = {},
  spell_langs = { 'en', 'sv' },
  prefix = ',m', -- keymap prefix
  -- Account detection for send: pattern → neomutt account source
  send_accounts = {
    -- ['work'] = '-e "source ~/.config/mutt/accounts/work.muttrc"',
    -- ['personal'] = '-e "source ~/.config/mutt/accounts/personal.muttrc"',
  },
}

-- Register filetype detection (eml files, neomutt temp files)
vim.filetype.add({
  extension = { eml = 'mail' },
  pattern = {
    ['/tmp/neomutt%-.*'] = 'mail',
    ['/tmp/mutt%-.*'] = 'mail',
  },
})

-- Merge user opts into config. Call this from your plugin manager's
-- `config` / `opts` hook. Does NOT apply any buffer-local setup — that
-- is handled by ftplugin/mail.lua via M.attach_buffer().
function M.setup(opts)
  opts = opts or {}
  if not M._configured then
    M.config = vim.tbl_deep_extend('force', M.config, opts)
    M._configured = true
    -- Propagate submodule configs so user opts.contacts / opts.snippets are honored.
    if M.config.contacts then
      local contacts = require('nvim-mail.contacts')
      contacts.config = vim.tbl_deep_extend('force', contacts.config, M.config.contacts)
    end
    if M.config.snippets then
      local snippets = require('nvim-mail.snippets')
      snippets.config = vim.tbl_deep_extend('force', snippets.config, M.config.snippets)
    end
  end
end

-- Apply buffer-local mappings, options, and autocmds to the current
-- mail buffer. Called by ftplugin/mail.lua on every mail buffer open.
function M.attach_buffer()
  local attachment = require('nvim-mail.attachment')
  local marker = require('nvim-mail.marker')
  local thread = require('nvim-mail.thread')
  local preview = require('nvim-mail.preview')
  local snippets = require('nvim-mail.snippets')
  local nav = require('nvim-mail.navigate')

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

  -- === Send mail (replaces vim-mail ,mm) ===
  map('m', function()
    local lines = vim.api.nvim_buf_get_lines(0, 0, 20, false)
    local acct = ''
    for _, line in ipairs(lines) do
      if line == '' then break end
      for pattern, acct_cmd in pairs(M.config.send_accounts) do
        if line:match('^From:') and line:lower():find(pattern) then
          acct = acct_cmd
          break
        end
      end
      if acct ~= '' then break end
    end
    vim.cmd('write')
    local file = vim.fn.expand('%')
    -- Run muttlook if body has markdown
    local body_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local has_markdown = false
    for _, l in ipairs(body_lines) do
      if l:match('^#') or l:match('^%*%*') or l:match('^|') or l:match('^%- %[') then
        has_markdown = true
        break
      end
    end
    if has_markdown then
      vim.fn.system('cat ' .. vim.fn.shellescape(file) .. ' | muttlook --action draft')
    end
    vim.cmd('terminal neomutt ' .. acct .. ' -H ' .. vim.fn.shellescape(file))
  end, ' Send mail')

  -- === Quote ===
  -- Normal mode: quote the current line only. Reading '< / '> in normal mode
  -- would consult stale visual marks (last visual selection, possibly from an
  -- unrelated buffer) — or return 0 if never set, crashing nvim_buf_set_lines
  -- with E5108 'start' > 'end'. Visual-mode quote handler below covers ranges.
  map('q', function()
    local cur = vim.fn.line('.')
    local line = vim.api.nvim_buf_get_lines(0, cur - 1, cur, false)[1] or ''
    vim.api.nvim_buf_set_lines(0, cur - 1, cur, false, { '> ' .. line })
  end, ' Quote')

  -- Also map quote in visual mode
  vim.keymap.set('v', M.config.prefix .. 'q', function()
    local start_line = vim.fn.line("'<")
    local end_line = vim.fn.line("'>")
    local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
    for i, l in ipairs(lines) do
      lines[i] = '> ' .. l
    end
    vim.api.nvim_buf_set_lines(0, start_line - 1, end_line, false, lines)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
  end, { buffer = true, desc = ' Quote' })

  -- === Contact resolve: ,mC replaces display names with emails in To/Cc/Bcc ===
  map('C', function() require('nvim-mail.resolver').resolve_buffer(0) end, ' Resolve contacts')

  -- === Contact picker: ,mK search khard+notmuch, insert or create ===
  map('K', function()
    require('telescope').extensions.nvim_mail.contacts()
  end, ' Contact picker')

  -- === Sync contacts ===
  map('a', function()
    vim.notify('Syncing contacts...', vim.log.levels.INFO)
    vim.fn.system({ 'khard', 'sync' })
    vim.notify('Contacts synced', vim.log.levels.INFO)
  end, ' Sync contacts')

  -- === Image paste (for muttlook CID) ===
  vim.keymap.set('n', p .. 'i', function()
    local tmpdir = vim.fn.expand('$HOME/.cache/muttlook')
    vim.fn.mkdir(tmpdir, 'p')
    local fname = 'paste_' .. os.date('%Y%m%d%H%M%S') .. '.png'
    local fpath = tmpdir .. '/' .. fname
    vim.fn.system({ 'pngpaste', fpath })
    if vim.v.shell_error == 0 then
      local pos = vim.api.nvim_win_get_cursor(0)
      vim.api.nvim_buf_set_lines(0, pos[1], pos[1], false, { '![' .. fname .. '](' .. fpath .. ')' })
    else
      vim.notify('No image in clipboard', vim.log.levels.WARN)
    end
  end, { buffer = true, desc = ' Paste image' })

  -- === Treesitter + spell ===
  vim.treesitter.language.register('markdown', 'mail')
  pcall(vim.treesitter.start, 0, 'markdown')
  local ok_ls, ls = pcall(require, 'luasnip')
  if ok_ls then ls.filetype_extend('mail', { 'markdown' }) end
  vim.opt_local.spell = true
  vim.opt_local.spelllang = table.concat(M.config.spell_langs, ',')
  vim.opt_local.wrap = true
  vim.opt_local.linebreak = true

  -- Mail header + body sanity checks on BufWritePre
  vim.api.nvim_create_autocmd('BufWritePre', {
    buffer = 0,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local warnings = {}

      -- Find header/body split
      local header_end = #lines
      for i, l in ipairs(lines) do
        if l == '' then header_end = i - 1; break end
      end

      -- Check required headers
      local headers = {}
      for i = 1, header_end do
        local k, v = lines[i]:match('^([%a%-]+):%s*(.*)')
        if k then headers[k:lower()] = v end
      end
      if not headers['to'] or headers['to'] == '' then
        warnings[#warnings+1] = '⚠ To: is empty'
      end
      if not headers['subject'] or headers['subject'] == '' then
        warnings[#warnings+1] = '⚠ Subject: is empty'
      end

      -- Check for headers accidentally typed in body
      for i = header_end + 2, #lines do
        if lines[i]:match('^(From|To|Cc|Bcc|Subject|Date|Message%-ID):%s') then
          warnings[#warnings+1] = '⚠ Header found in body (line ' .. i .. '): ' .. lines[i]:sub(1, 40)
          break
        end
      end

      -- Attachment check
      local missing, match = attachment.check(lines)
      if missing then
        warnings[#warnings+1] = string.format('⚠ Mentioned "%s" but no attachment found!', match or 'attachment')
      end

      if #warnings > 0 then
        vim.notify(table.concat(warnings, '\n'), vim.log.levels.WARN)
      end
    end,
    desc = 'Mail: header and body sanity checks',
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
