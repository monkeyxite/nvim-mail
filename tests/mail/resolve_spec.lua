local resolve = require('nvim-mail.resolve')
local calendar = require('nvim-mail.calendar')

describe('mail.resolve', function()

  describe('normalize_name', function()
    it('strips single uppercase suffix', function()
      assert.equals('Kevin Li', resolve.normalize_name('Kevin Li K'))
    end)

    it('strips double uppercase suffix', function()
      assert.equals('Ove Sirkka', resolve.normalize_name('Ove Sirkka XX'))
    end)

    it('strips roman numeral suffix', function()
      assert.equals('Rock Zhang', resolve.normalize_name('Rock Zhang I'))
    end)

    it('leaves normal names unchanged', function()
      assert.equals('Anders Ulin', resolve.normalize_name('Anders Ulin'))
    end)

    it('trims whitespace', function()
      assert.equals('Hans Hogberg', resolve.normalize_name('  Hans Hogberg  '))
    end)
  end)

  describe('tr (transliteration)', function()
    it('transliterates Swedish ä→a', function()
      assert.equals('bjork', resolve.tr('björk'))
    end)

    it('transliterates ö→o', function()
      assert.equals('sjogren', resolve.tr('sjögren'))
    end)

    it('transliterates å→a', function()
      assert.equals('aberg', resolve.tr('åberg'))
    end)

    it('transliterates é→e', function()
      assert.equals('lepisto', resolve.tr('lepistö'))
    end)

    it('leaves ASCII unchanged', function()
      assert.equals('jonny', resolve.tr('jonny'))
    end)
  end)

  describe('ericsson_candidates', function()
    it('generates first.last for two-part name', function()
      local c = resolve.ericsson_candidates('Anders Jansson')
      assert.is_truthy(vim.tbl_contains(c, 'anders.jansson'))
    end)

    it('generates middle-name variants for three-part name', function()
      local c = resolve.ericsson_candidates('Kevin K Li')
      assert.is_truthy(vim.tbl_contains(c, 'kevin.k.li'))
      assert.is_truthy(vim.tbl_contains(c, 'kevin.li.k'))
      assert.is_truthy(vim.tbl_contains(c, 'kevin.li'))
    end)

    it('handles suffix-stripped name', function()
      local c = resolve.ericsson_candidates('Magnus Lundgren X')
      assert.is_truthy(vim.tbl_contains(c, 'magnus.lundgren'))
    end)

    it('transliterates Swedish chars', function()
      local c = resolve.ericsson_candidates('Andreas Björk')
      assert.is_truthy(vim.tbl_contains(c, 'andreas.bjork'))
    end)

    it('returns empty for single-word name', function()
      local c = resolve.ericsson_candidates('Jonny')
      assert.equals(0, #c)
    end)
  end)

  describe('validate_notmuch_match', function()
    it('accepts matching display name', function()
      assert.is_true(resolve.validate_notmuch_match('Anders Jansson', 'Anders Jansson'))
    end)

    it('accepts name with suffix stripped', function()
      assert.is_true(resolve.validate_notmuch_match('Magnus Lundgren', 'Magnus Lundgren X'))
    end)

    it('rejects partial match missing last name', function()
      assert.is_false(resolve.validate_notmuch_match('Anders Smith', 'Anders Jansson'))
    end)

    it('rejects partial match missing first name', function()
      assert.is_false(resolve.validate_notmuch_match('Bob Jansson', 'Anders Jansson'))
    end)

    it('handles transliterated Swedish names', function()
      assert.is_true(resolve.validate_notmuch_match('Andreas Bjork', 'Andreas Björk'))
    end)
  end)

  describe('parse_khard', function()
    it('extracts email from parsable output', function()
      local email = resolve.parse_khard('jonny.hou@gmail.com\tJonny Hou\thome\n')
      assert.equals('jonny.hou@gmail.com', email)
    end)

    it('returns nil for empty output', function()
      assert.is_nil(resolve.parse_khard(''))
    end)

    it('returns nil for non-email first field', function()
      assert.is_nil(resolve.parse_khard('not-an-email\tSome Name\n'))
    end)

    it('handles multiple lines, uses first', function()
      local email = resolve.parse_khard('first@example.com\tFirst\nhome\nsecond@example.com\tSecond\n')
      assert.equals('first@example.com', email)
    end)
  end)

end)

describe('mail.calendar (new)', function()

  describe('clean_notes', function()
    it('strips mailto links', function()
      local out = calendar._clean_notes('Hello @Alice<mailto:alice@work.com>')
      assert.is_falsy(out:find('mailto:'))
      assert.is_truthy(out:find('Hello @Alice'))
    end)

    it('strips Teams meeting boilerplate', function()
      local out = calendar._clean_notes('Agenda\n___\nMicrosoft Teams meeting\nJoin here')
      assert.is_falsy(out:find('Teams'))
      assert.is_truthy(out:find('Agenda'))
    end)

    it('strips angle-bracket URLs', function()
      local out = calendar._clean_notes('See <https://teams.microsoft.com/l/meetup> for details')
      assert.is_falsy(out:find('https://'))
    end)

    it('normalizes CRLF to LF', function()
      local out = calendar._clean_notes('line1\r\nline2')
      assert.is_falsy(out:find('\r'))
      assert.is_truthy(out:find('line1\nline2'))
    end)

    it('collapses excessive blank lines', function()
      local out = calendar._clean_notes('a\n\n\n\n\nb')
      assert.is_falsy(out:find('\n\n\n'))
    end)

    it('returns empty string for nil', function()
      assert.equals('', calendar._clean_notes(nil))
    end)
  end)

  describe('format_entry', function()
    it('formats time range and title', function()
      local event = {
        sctime = '2026-05-16 09:00:00',
        ectime = '2026-05-16 09:30:00',
        title  = 'Standup',
      }
      local s = calendar._format_entry(event)
      assert.is_truthy(s:find('09:00'))
      assert.is_truthy(s:find('09:30'))
      assert.is_truthy(s:find('Standup'))
    end)

    it('handles missing times gracefully', function()
      local event = { title = 'No time' }
      local s = calendar._format_entry(event)
      assert.is_truthy(s:find('No time'))
    end)
  end)

end)
