-- Telescope extension for notmuch mail search (uses nm-livesearch)
-- Usage: require('telescope').extensions.nvim_mail.search()
local M = {}

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
    previewer = previewers.new_termopen_previewer({
      get_command = function(entry)
        if not entry or not entry.thread then return { 'echo', 'No thread' } end
        return { 'sh', '-c',
          'msgid=$(notmuch search --output=messages --limit=1 thread:' .. entry.thread .. ' | sed "s/^id://") && nm-html-extract "$msgid"'
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local entry = action_state.get_selected_entry()
        if entry and entry.thread then
          vim.cmd('terminal neomutt -f "notmuch://?query=thread:' .. entry.thread .. '"')
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
