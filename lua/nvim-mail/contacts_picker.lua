-- Telescope contact picker: search khard + notmuch, insert or create contacts
-- Usage: require('telescope').extensions.nvim_mail.contacts()
local M = {}

local function contacts_picker(opts)
  opts = opts or {}
  local pickers    = require('telescope.pickers')
  local finders    = require('telescope.finders')
  local conf       = require('telescope.config').values
  local actions    = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local previewers = require('telescope.previewers')

  -- Load all addresses once, fuzzy filter client-side
  local result = vim.system(
    { 'notmuch', 'address', '--format=text', '--deduplicate=address', '*' },
    { text = true }
  ):wait(10000)
  local entries = {}
  local seen = {}
  for _, line in ipairs(vim.split(result.stdout or '', '\n')) do
    if line ~= '' then
      local name, email = line:match('^(.-)%s*<([^>]+)>')
      if not email then email = vim.trim(line); name = '' end
      email = vim.trim(email or '')
      if email:find('@') and not seen[email] then
        seen[email] = true
        entries[#entries + 1] = { email = email, name = vim.trim(name or '') }
      end
    end
  end

  pickers.new(opts, {
    prompt_title = '  Contacts (' .. #entries .. ')',
    finder = finders.new_table({
      results = entries,
      entry_maker = function(r)
        local display = r.name ~= '' and string.format('%s <%s>', r.name, r.email) or r.email
        return {
          value   = { email = r.email, name = r.name, type = 'notmuch' },
          display = display,
          ordinal = r.name .. ' ' .. r.email,
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    previewer = previewers.new_buffer_previewer({
      title = 'Contact Details',
      define_preview = function(self, entry)
        if not entry or not entry.value then return end
        local r = entry.value
        -- Show khard vcard if available
        local lines = {
          '# ' .. (r.name or ''),
          '',
          'Email : ' .. (r.email or ''),
          'Source: ' .. (r.type or ''),
          '',
        }
        -- Try khard show for full details
        local result = vim.system({ 'khard', 'show', r.name or '' }, { text = true }):wait()
        if result.code == 0 and result.stdout ~= '' then
          vim.list_extend(lines, vim.split(result.stdout, '\n'))
        else
          -- Fallback: notmuch address details
          local nm = vim.system(
            { 'notmuch', 'address', '--format=json', '--deduplicate=address',
              'from:' .. (r.email or '') },
            { text = true }
          ):wait()
          if nm.code == 0 then
            local ok, data = pcall(vim.json.decode, nm.stdout)
            if ok and data and data[1] then
              lines[#lines + 1] = 'Notmuch: ' .. (data[1].name or '') .. ' <' .. (data[1].address or '') .. '>'
            end
          end
        end
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      end,
    }),
    sorter = require('telescope.sorters').empty(),
    attach_mappings = function(prompt_bufnr, map)

      -- Enter: insert "Name <email>" at cursor in calling buffer
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local entry = action_state.get_selected_entry()
        if not entry then return end
        local r = entry.value
        local text = string.format('%s <%s>', r.name or '', r.email or '')
        vim.api.nvim_put({ text }, 'c', true, true)
      end)

      -- C-y: yank email to clipboard
      map({ 'i', 'n' }, '<C-y>', function()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        vim.fn.setreg('+', entry.value.email or '')
        vim.notify('Copied: ' .. (entry.value.email or ''), vim.log.levels.INFO)
      end)

      -- C-n: create new khard contact from notmuch result
      map({ 'i', 'n' }, '<C-n>', function()
        actions.close(prompt_bufnr)
        local entry = action_state.get_selected_entry()
        local name  = entry and entry.value.name  or ''
        local email = entry and entry.value.email or ''

        -- Prompt for first/last name split
        local parts = vim.split(name, ' ', { trimempty = true })
        local first = parts[1] or ''
        local last  = table.concat(vim.list_slice(parts, 2), ' ')

        vim.ui.input({ prompt = 'First name: ', default = first }, function(fn)
          if not fn then return end
          vim.ui.input({ prompt = 'Last name: ', default = last }, function(ln)
            if not ln then return end
            vim.ui.input({ prompt = 'Email: ', default = email }, function(em)
              if not em or em == '' then return end
              vim.ui.select(
                { 'work', 'home', 'other' },
                { prompt = 'Email type:' },
                function(etype)
                  if not etype then return end
                  -- Build minimal vCard and pipe to khard add
                  local vcard = table.concat({
                    'BEGIN:VCARD',
                    'VERSION:3.0',
                    'FN:' .. fn .. ' ' .. ln,
                    'N:' .. ln .. ';' .. fn .. ';;;',
                    'EMAIL;TYPE=' .. etype:upper() .. ':' .. em,
                    'END:VCARD',
                  }, '\n')
                  local result = vim.system(
                    { 'khard', 'add', '--input-format=vcard' },
                    { text = true, stdin = vcard }
                  ):wait()
                  if result.code == 0 then
                    vim.notify('✓ Contact created: ' .. fn .. ' ' .. ln, vim.log.levels.INFO)
                  else
                    vim.notify('✗ khard add failed: ' .. (result.stderr or ''), vim.log.levels.ERROR)
                  end
                end
              )
            end)
          end)
        end)
      end)

      return true
    end,
  }):find()
end

M.contacts = contacts_picker
return M
