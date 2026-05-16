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
    -- ['ericsson'] = '-e "source ~/.config/mutt/accounts/2-work.muttrc"',
    -- ['monkeyxite'] = '-e "source ~/.config/mutt/accounts/1-monkeyxite@gmail.com.muttrc"',
    -- ['gmail'] = '-e "source ~/.config/mutt/accounts/1-monkeyxite@gmail.com.muttrc"',
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

function M.setup(opts)
  opts = opts or {}
  -- Only merge opts into config on first call (lazy.nvim opts)
  if not M._configured then
    M.config = vim.tbl_deep_extend('force', M.config, opts)
    M._configured = true
  end

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
  map('q', function()
    local start_line = vim.fn.line("'<") or vim.fn.line('.')
    local end_line = vim.fn.line("'>") or vim.fn.line('.')
    local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
    for i, l in ipairs(lines) do
      lines[i] = '> ' .. l
    end
    vim.api.nvim_buf_set_lines(0, start_line - 1, end_line, false, lines)
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
  map('C', function()
    local contacts = require('nvim-mail.contacts')
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local unresolved = {}
    local pending = 0
    local header_end = 0

    -- Find header block
    for i, l in ipairs(lines) do
      if l == '' then header_end = i - 1; break end
    end

    -- Collect address header indices and names to resolve
    local tasks = {}  -- { line_idx, original_line, names[] }
    for i = 1, header_end do
      local line = lines[i]
      if contacts.is_header_line(line) then
        local after = line:match('^%a+:%s*(.*)')
        if after and after ~= '' then
          -- Split by comma, collect entries that have no @
          local entries = vim.split(after, ',', { trimempty = true })
          local names = {}
          for _, e in ipairs(entries) do
            e = vim.trim(e)
            if not e:find('@') then names[#names + 1] = e end
          end
          if #names > 0 then
            tasks[#tasks + 1] = { idx = i, line = line, entries = entries, names = names }
            pending = pending + #names
          end
        end
      end
    end

    if pending == 0 then
      vim.notify('All addresses already resolved', vim.log.levels.INFO)
      return
    end

    -- For each task, resolve names async in parallel
    local resolved_lines = {}
    local done = 0
    local total = #tasks

    local function finish()
      done = done + 1
      if done < total then return end
      -- Apply resolved lines
      for _, t in ipairs(tasks) do
        if resolved_lines[t.idx] then
          lines[t.idx] = resolved_lines[t.idx]
        end
      end
      vim.schedule(function()
        vim.api.nvim_buf_set_lines(0, 0, header_end, false, vim.list_slice(lines, 1, header_end))
        if #unresolved > 0 then
          vim.notify('⚠ No email found for: ' .. table.concat(unresolved, ', '), vim.log.levels.WARN)
        else
          vim.notify('✓ All contacts resolved', vim.log.levels.INFO)
        end
      end)
    end

    -- Transliterate non-ASCII for Ericsson email pattern matching
    local _tr = {
      ['à']='a',['á']='a',['â']='a',['ã']='a',['ä']='a',['å']='a',
      ['æ']='ae',['ç']='c',['è']='e',['é']='e',['ê']='e',['ë']='e',
      ['ì']='i',['í']='i',['î']='i',['ï']='i',['ñ']='n',
      ['ò']='o',['ó']='o',['ô']='o',['õ']='o',['ö']='o',['ø']='o',
      ['ù']='u',['ú']='u',['û']='u',['ü']='u',['ý']='y',
    }
    local function tr(s)
      return (s:gsub('[%z\1-\127\194-\244][\128-\191]*', function(c)
        return _tr[c] or c
      end))
    end

    -- Strip Ericsson-style suffixes, use longest non-first part as surname
    local function normalize_name(n)
      n = vim.trim(n:gsub('%s+[A-Z][A-Z]?$', ''):gsub('%s+I+$', ''))
      return n
    end

    local function parse_khard(stdout)
      local line = vim.split(stdout or '', "\n")[1] or ''
      local email = vim.split(line, "\t")[1] or ''
      email = vim.trim(email)
      return email:find('@') and email or nil
    end

    -- Auto-save to khard when notmuch finds a match
    local function save_to_khard(first, last, email)
      local vcard = table.concat({
        'BEGIN:VCARD', 'VERSION:3.0',
        'FN:' .. first .. ' ' .. last,
        'N:' .. last .. ';' .. first .. ';;;',
        'EMAIL;TYPE=WORK:' .. email,
        'END:VCARD',
      }, '\n')
      vim.system({ 'khard', 'add', '--input-format=vcard' }, { text = true, stdin = vcard })
    end

    -- Stage 2: notmuch with Ericsson email pattern + name validation
    local function notmuch_lookup(name, cb)
      local norm = normalize_name(name)
      local parts = vim.split(norm, ' ', { trimempty = true })
      if #parts < 2 then cb(nil); return end
      local first, last = tr(parts[1]:lower()), tr(parts[#parts]:lower())
      -- Use longest non-first part as check_last (handles "Magnus Lundgren X")
      local check_last = last
      for _, p in ipairs(parts) do
        local tp = tr(p:lower())
        if tp ~= tr(parts[1]:lower()) and #tp > #check_last then check_last = tp end
      end
      -- Build Ericsson email candidates
      local candidates = {}
      if #parts == 3 then
        local mid = tr(parts[2]:lower())
        candidates[#candidates+1] = first..'.'..mid..'.'..last
        candidates[#candidates+1] = first..'.'..last..'.'..mid
      end
      candidates[#candidates+1] = first..'.'..last

      local tried, found = 0, false
      local total = #candidates * 2  -- sender + recipient per candidate
      local function done(email)
        if found then return end
        found = true
        if email then save_to_khard(parts[1], parts[#parts], email) end
        cb(email)
      end
      for _, cand in ipairs(candidates) do
        for _, cmd in ipairs({
          { 'notmuch', 'address', '--deduplicate=address', 'from:'..cand..'@ericsson' },
          { 'notmuch', 'address', '--deduplicate=address', 'to:'..cand..'@ericsson' },
        }) do
          vim.system(cmd, { text = true }, function(result)
            tried = tried + 1
            if found then return end
            for _, line in ipairs(vim.split(result.stdout or '', "\n")) do
              local dname, email = line:match('^(.-)%s*<([^>]+@ericsson%.com)>')
              if email and dname then
                local dtr = tr(dname:lower())
                local dwords = vim.split(dtr, '%s+')
                local has_first = vim.tbl_contains(dwords, first)
                local has_last = #check_last > 1 and vim.tbl_contains(dwords, check_last)
                if has_first and has_last then done(email); return end
              end
            end
            if tried >= total then done(nil) end
          end)
        end
      end
    end

    -- 2-stage resolver: khard → notmuch → ldap (with warning)
    local function resolve_name(name, cb)
      local norm = normalize_name(name)
      local parts = vim.split(norm, ' ', { trimempty = true })
      local first_last = #parts >= 2 and (parts[1] .. ' ' .. parts[#parts]) or norm
      local khard_queries = { name }
      if norm ~= name then khard_queries[#khard_queries+1] = norm end
      if first_last ~= norm then khard_queries[#khard_queries+1] = first_last end

      local function try_khard(i)
        if i > #khard_queries then
          notmuch_lookup(name, function(email)
            if email then cb(email); return end
            -- Last resort: ldap (slow, DavMail)
            vim.schedule(function()
              vim.notify('⏳ LDAP lookup for: ' .. name, vim.log.levels.WARN)
            end)
            local norm2 = normalize_name(name)
            local p = vim.split(norm2, ' ', { trimempty = true })
            vim.system(
              { 'ldap_owa_query', p[1] or norm2, p[2] or '', 'work' },
              { text = true }, function(result)
                local line = vim.split(result.stdout or '', "\n")[1] or ''
                local email2 = vim.trim(vim.split(line, "\t")[1] or '')
                if email2:find('@') then
                  -- Auto-save ldap result to khard
                  local p2 = vim.split(normalize_name(name), ' ', { trimempty = true })
                  save_to_khard(p2[1] or name, p2[#p2] or '', email2)
                end
                cb(email2:find('@') and email2 or nil)
              end)
          end)
          return
        end
        vim.system({ 'khard', 'email', '--parsable', '--remove-first-line', khard_queries[i] },
          { text = true }, function(result)
            local email = parse_khard(result.stdout)
            if email then cb(email) else try_khard(i + 1) end
          end)
      end
      try_khard(1)
    end

    for _, t in ipairs(tasks) do
      local name_results = {}
      local name_pending = #t.names
      for _, name in ipairs(t.names) do
        resolve_name(name, function(email)
            if email and email ~= '' then
              name_results[name] = string.format('%s <%s>', name, email)
            else
              name_results[name] = nil
              unresolved[#unresolved + 1] = name
            end
            name_pending = name_pending - 1
            if name_pending == 0 then
              -- Rebuild the header line
              local new_entries = {}
              for _, e in ipairs(t.entries) do
                local trimmed = vim.trim(e)
                new_entries[#new_entries + 1] = name_results[trimmed] or trimmed
              end
              local prefix = t.line:match('^(%a+:%s*)')
              resolved_lines[t.idx] = prefix .. table.concat(new_entries, ', ')
              finish()
            end
          end)
      end
    end
  end, ' Resolve contacts')

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
