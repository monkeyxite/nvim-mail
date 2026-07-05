-- Telescope contact picker: khard first (fast), C-n expands to notmuch
-- Usage: require('telescope').extensions.nvim_mail.contacts()
local M = {}

local function parse_entries(stdout)
  local entries, seen = {}, {}
  for _, line in ipairs(vim.split(stdout or '', '\n')) do
    if line ~= '' then
      local email, name = line:match('^([^\t]+)\t([^\t]+)')
      if email and email:find('@') and not seen[email] then
        seen[email] = true
        entries[#entries + 1] = { email = vim.trim(email), name = vim.trim(name or '') }
      end
    end
  end
  return entries
end

local function make_picker(opts, entries, title)
  local pickers      = require('telescope.pickers')
  local finders      = require('telescope.finders')
  local conf         = require('telescope.config').values
  local actions      = require('telescope.actions')
  local action_state = require('telescope.actions.state')

  pickers.new(opts, {
    prompt_title = title .. '  C-e:notmuch  C-o:edit  C-n:new',
    finder = finders.new_table({
      results = entries,
      entry_maker = function(r)
        local display = r.name ~= '' and string.format('%s <%s>', r.name, r.email) or r.email
        return {
          value   = r,
          display = display,
          ordinal = r.name .. ' ' .. r.email,
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr, map)

      -- Enter: insert "Name <email>" at cursor
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local entry = action_state.get_selected_entry()
        if not entry then return end
        local r = entry.value
        local text = r.name ~= '' and string.format('%s <%s>', r.name, r.email) or r.email
        vim.api.nvim_put({ text }, 'c', true, true)
      end)

      -- C-y: yank email
      map({ 'i', 'n' }, '<C-y>', function()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        vim.fn.setreg('+', entry.value.email or '')
        vim.notify('Copied: ' .. (entry.value.email or ''), vim.log.levels.INFO)
      end)

      -- C-o: edit contact in khard
      map({ 'i', 'n' }, '<C-o>', function()
        actions.close(prompt_bufnr)
        local entry = action_state.get_selected_entry()
        if not entry then return end
        vim.cmd('terminal khard edit ' .. vim.fn.shellescape(entry.value.email))
      end)

      -- C-e: expand to notmuch (async, reopens picker with more results)
      map({ 'i', 'n' }, '<C-e>', function()
        actions.close(prompt_bufnr)
        vim.notify('Loading notmuch addresses...', vim.log.levels.INFO)
        vim.system(
          { 'notmuch', 'address', '--format=text', '--deduplicate=address', '*' },
          { text = true },
          function(result)
            local nm_entries = {}
            local seen = {}
            for _, e in ipairs(entries) do seen[e.email] = true end
            for _, line in ipairs(vim.split(result.stdout or '', '\n')) do
              if line ~= '' then
                local name, email = line:match('^(.-)%s*<([^>]+)>')
                if not email then email = vim.trim(line); name = '' end
                email = vim.trim(email or '')
                if email:find('@') and not seen[email] then
                  seen[email] = true
                  nm_entries[#nm_entries + 1] = { email = email, name = vim.trim(name or '') }
                end
              end
            end
            local all = vim.list_extend(vim.deepcopy(entries), nm_entries)
            vim.schedule(function()
              make_picker(opts, all, '  Contacts+Notmuch (' .. #all .. ')')
            end)
          end
        )
      end)

      -- C-n: create new khard contact from selected entry
      map({ 'i', 'n' }, '<C-n>', function()
        actions.close(prompt_bufnr)
        local entry = action_state.get_selected_entry()
        local name  = entry and entry.value.name  or ''
        local email = entry and entry.value.email or ''
        local parts = vim.split(name, ' ', { trimempty = true })
        vim.ui.input({ prompt = 'First name: ', default = parts[1] or '' }, function(fn)
          if not fn then return end
          vim.ui.input({ prompt = 'Last name: ', default = table.concat(vim.list_slice(parts, 2), ' ') }, function(ln)
            if not ln then return end
            vim.ui.input({ prompt = 'Email: ', default = email }, function(em)
              if not em or em == '' then return end
              vim.ui.select({ 'work', 'home', 'other' }, { prompt = 'Email type:' }, function(etype)
                if not etype then return end
                local vcard = table.concat({
                  'BEGIN:VCARD', 'VERSION:3.0',
                  'FN:' .. fn .. ' ' .. ln,
                  'N:' .. ln .. ';' .. fn .. ';;;',
                  'EMAIL;TYPE=' .. etype:upper() .. ':' .. em,
                  'END:VCARD',
                }, '\n')
                local res = vim.system({ 'khard', 'add', '--input-format=vcard' },
                  { text = true, stdin = vcard }):wait()
                if res.code == 0 then
                  vim.notify('✓ Contact created: ' .. fn .. ' ' .. ln, vim.log.levels.INFO)
                else
                  vim.notify('✗ ' .. (res.stderr or ''), vim.log.levels.ERROR)
                end
              end)
            end)
          end)
        end)
      end)

      return true
    end,
  }):find()
end

local function contacts_picker(opts)
  opts = opts or {}
  vim.notify('Loading contacts...', vim.log.levels.INFO)
  vim.system(
    { 'khard', 'email', '--parsable', '--remove-first-line', '' },
    { text = true },
    function(result)
      local entries = parse_entries(result.stdout)
      vim.schedule(function()
        make_picker(opts, entries, '  Contacts (' .. #entries .. ')')
      end)
    end
  )
end

M.contacts = contacts_picker
return M
