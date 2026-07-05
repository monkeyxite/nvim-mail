local snippets = require('nvim-mail.snippets')

describe('mail.snippets', function()
  local fixtures_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h') .. '/fixtures/'

  local function read_fixture(name)
    local lines = {}
    for line in io.lines(fixtures_dir .. name) do
      lines[#lines + 1] = line
    end
    return lines
  end

  before_each(function()
    snippets.config.domains = {
      ['work%.com'] = 'work',
      ['gmail%.com'] = 'personal',
    }
  end)

  describe('detect_context', function()
    it('detects work context from To header', function()
      local lines = read_fixture('draft_work_reply.txt')
      local ctx = snippets.detect_context(lines)
      assert.equals('work', ctx)
    end)

    it('detects personal context', function()
      local lines = read_fixture('draft_personal.txt')
      local ctx = snippets.detect_context(lines)
      assert.equals('personal', ctx)
    end)

    it('defaults to general for unknown recipients', function()
      local lines = read_fixture('draft_no_attach.txt')
      local ctx = snippets.detect_context(lines)
      assert.equals('general', ctx)
    end)
  end)

  describe('load_for_buffer', function()
    local captured = {}
    local ls_stub

    before_each(function()
      captured = {}
      ls_stub = {
        parser = {
          parse_snippet = function(trigger, body)
            return { trigger = trigger, body = body }
          end,
        },
        add_snippets = function(ft, snips, opts)
          captured.ft = ft
          captured.snips = snips
          captured.opts = opts
        end,
      }
      package.loaded['luasnip'] = ls_stub
    end)

    after_each(function()
      package.loaded['luasnip'] = nil
    end)

    it('calls ls.add_snippets with ft=mail and key=nvim-mail-work for work context', function()
      local lines = read_fixture('draft_work_reply.txt')
      snippets.load_for_buffer(lines)
      assert.equals('mail', captured.ft)
      assert.equals('nvim-mail-work', captured.opts and captured.opts.key)
      assert.is_true(#(captured.snips or {}) > 0)
    end)

    it('uses general context for unknown recipients', function()
      local lines = read_fixture('draft_no_attach.txt')
      snippets.load_for_buffer(lines)
      assert.equals('nvim-mail-general', captured.opts and captured.opts.key)
    end)

    it('does nothing when luasnip is unavailable', function()
      package.loaded['luasnip'] = nil
      -- make require fail by temporarily breaking the path
      local orig = package.preload['luasnip']
      package.preload['luasnip'] = function() error('not installed') end
      local ok = pcall(snippets.load_for_buffer, read_fixture('draft_work_reply.txt'))
      assert.is_true(ok)  -- must not raise
      package.preload['luasnip'] = orig
    end)
  end)

  describe('get_snippets', function()
    it('returns table of snippets for context', function()
      local snips = snippets.get_snippets('work')
      assert.is_table(snips)
      assert.is_true(#snips > 0)
    end)

    it('returns general snippets for unknown context', function()
      local snips = snippets.get_snippets('general')
      assert.is_table(snips)
      assert.is_true(#snips > 0)
    end)

    it('substitutes configured name in body', function()
      snippets.config.name = 'Jonny'
      local snips = snippets.get_snippets('work')
      local mbr = vim.tbl_filter(function(s) return s.trigger == 'mbr' end, snips)[1]
      assert.is_truthy(mbr and mbr.body:find('Jonny'))
    end)
  end)
end)
