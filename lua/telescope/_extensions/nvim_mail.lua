-- Telescope extension for notmuch mail search (uses nm-livesearch)
-- Usage: require('telescope').extensions.nvim_mail.search()
local M = {}

local function get_msgid_cmd(thread)
  return 'notmuch search --output=messages --limit=1 thread:' .. thread .. ' | sed "s/^id://"'
end

local strip_ansi = [[sed 's/]].. '\027' .. [[[[][0-9;]*m//g']]

local function search(opts)
  opts = opts or {}
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local previewers = require('telescope.previewers')

  pickers.new(opts, {
    prompt_title = '  Notmuch Search',
    finder = finders.new_async_job({
      command_generator = function(prompt)
        if not prompt or prompt == '' then return nil end
        return { 'nm-livesearch', 'threads', prompt }
      end,
      entry_maker = function(line)
        if not line or line == '' then return nil end
        local ok, data = pcall(vim.json.decode, line)
        if not ok or not data or not data.id then return nil end
        local authors = table.concat(data.authors or {}, ', ')
        local tags = table.concat(data.tags or {}, ' ')
        local display = string.format('%s  %s  %s', authors, data.subject or '', tags ~= '' and ('(' .. tags .. ')') or '')
        return {
          value = data,
          display = display,
          ordinal = authors .. ' ' .. (data.subject or ''),
          thread = data.id,
        }
      end,
    }),
    previewer = previewers.new_buffer_previewer({
      title = 'Mail Preview',
      define_preview = function(self, entry)
        if not entry or not entry.thread then return end
        local cmd = 'msgid=$(' .. get_msgid_cmd(entry.thread) .. ') && nm-html-extract "$msgid" | ' .. strip_ansi
        local output = vim.fn.system({ 'sh', '-c', cmd })
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(output, '\n'))
        vim.bo[self.state.bufnr].filetype = 'mail'
      end,
    }),
    sorter = require('telescope.sorters').empty(),
    attach_mappings = function(prompt_bufnr, map)
      -- Enter: open in neomutt
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local entry = action_state.get_selected_entry()
        if entry and entry.thread then
          vim.cmd('terminal neomutt -f "notmuch://?query=thread:' .. entry.thread .. '"')
        end
      end)

      -- Ctrl+o: view in browser (muttlook --action view)
      map({ 'i', 'n' }, '<C-o>', function()
        local entry = action_state.get_selected_entry()
        if entry and entry.thread then
          vim.fn.system({ 'sh', '-c',
            'msgid=$(' .. get_msgid_cmd(entry.thread) .. ') && notmuch show --format=raw "id:$msgid" | muttlook --action view'
          })
        end
      end)

      -- Ctrl+r: reply — muttlook draft → neomutt → nvr
      map({ 'i', 'n' }, '<C-r>', function()
        actions.close(prompt_bufnr)
        local entry = action_state.get_selected_entry()
        if entry and entry.thread then
          vim.fn.system('sh -c \'msgid=$(' .. get_msgid_cmd(entry.thread) .. ') && notmuch show --format=raw "id:$msgid" | muttlook --action draft\'')
          local draft = vim.fn.expand('~/.cache/muttlook/mimelook.html')
          vim.cmd('terminal neomutt -H ' .. vim.fn.shellescape(draft))
        end
      end)

      -- Ctrl+t: tag (GTD actions)
      map({ 'i', 'n' }, '<C-t>', function()
        local entry = action_state.get_selected_entry()
        if entry and entry.thread then
          vim.ui.select(
            { 'archive (-inbox)', 'action (+action -inbox)', 'waiting (+waiting -inbox)', 'defer (+defer -inbox)', 'done (-action -waiting -defer)' },
            { prompt = 'GTD Tag:' },
            function(choice)
              if not choice then return end
              local tags = {
                ['archive (-inbox)'] = '-inbox -action -waiting -defer',
                ['action (+action -inbox)'] = '+action -inbox',
                ['waiting (+waiting -inbox)'] = '+waiting -inbox',
                ['defer (+defer -inbox)'] = '+defer -inbox',
                ['done (-action -waiting -defer)'] = '-action -waiting -defer -inbox',
              }
              local tag_str = tags[choice]
              if tag_str then
                vim.fn.system('notmuch tag ' .. tag_str .. ' -- thread:' .. entry.thread)
                vim.notify('Tagged: ' .. tag_str, vim.log.levels.INFO)
              end
            end
          )
        end
      end)

      -- Ctrl+y: copy message-id
      map({ 'i', 'n' }, '<C-y>', function()
        local entry = action_state.get_selected_entry()
        if entry and entry.thread then
          local msgid = vim.fn.system('sh -c \'' .. get_msgid_cmd(entry.thread) .. '\''):gsub('%s+$', '')
          vim.fn.setreg('+', msgid)
          vim.notify('Copied: ' .. msgid, vim.log.levels.INFO)
        end
      end)

      -- Ctrl+p: open full preview in scrollable split below (with ANSI colors)
      map({ 'i', 'n' }, '<C-p>', function()
        actions.close(prompt_bufnr)
        local entry = action_state.get_selected_entry()
        if entry and entry.thread then
          vim.cmd('below new')
          vim.fn.termopen('sh -c \'msgid=$(' .. get_msgid_cmd(entry.thread) .. ') && nm-html-extract "$msgid"\'')
          vim.bo.swapfile = false
        end
      end)

      return true
    end,
  }):find()
end

M.search = search

return require('telescope').register_extension({
  exports = {
    search = search,
  },
})
