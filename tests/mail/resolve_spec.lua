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

  describe('build_candidates', function()

    describe('pattern variants (two-part name)', function()
      it('first.last', function()
        local c = resolve.build_candidates('Anders Jansson', 'first.last', {})
        assert.is_truthy(vim.tbl_contains(c, 'anders.jansson'))
      end)

      it('flast', function()
        local c = resolve.build_candidates('Anders Jansson', 'flast', {})
        assert.is_truthy(vim.tbl_contains(c, 'ajansson'))
      end)

      it('first_last', function()
        local c = resolve.build_candidates('Anders Jansson', 'first_last', {})
        assert.is_truthy(vim.tbl_contains(c, 'anders_jansson'))
      end)

      it('firstlast', function()
        local c = resolve.build_candidates('Anders Jansson', 'firstlast', {})
        assert.is_truthy(vim.tbl_contains(c, 'andersjansson'))
      end)

      it('last.first', function()
        local c = resolve.build_candidates('Anders Jansson', 'last.first', {})
        assert.is_truthy(vim.tbl_contains(c, 'jansson.anders'))
      end)
    end)

    describe('transliterate', function()
      it('transliterate=true converts umlauts', function()
        local c = resolve.build_candidates('Andreas Björk', 'first.last', { transliterate = true })
        assert.is_truthy(vim.tbl_contains(c, 'andreas.bjork'))
      end)

      it('transliterate=false preserves unicode in prefix', function()
        local c = resolve.build_candidates('Andreas Björk', 'first.last', { transliterate = false })
        -- raw unicode is kept as-is when transliterate is off
        local found = false
        for _, v in ipairs(c) do
          if v:find('bj') then found = true; break end
        end
        assert.is_true(found)
        assert.is_false(vim.tbl_contains(c, 'andreas.bjork'))
      end)

      it('flast with transliterate=true', function()
        local c = resolve.build_candidates('Andreas Björk', 'flast', { transliterate = true })
        assert.is_truthy(vim.tbl_contains(c, 'abjork'))
      end)
    end)

    describe('normalize_suffixes', function()
      it('normalize_suffixes=true strips single uppercase suffix', function()
        local c = resolve.build_candidates('Kevin Li K', 'first.last', { normalize_suffixes = true })
        assert.is_truthy(vim.tbl_contains(c, 'kevin.li'))
        assert.is_false(vim.tbl_contains(c, 'kevin.k'))
      end)

      it('normalize_suffixes=true strips double uppercase suffix', function()
        local c = resolve.build_candidates('Magnus Lundgren XX', 'first.last', { normalize_suffixes = true })
        assert.is_truthy(vim.tbl_contains(c, 'magnus.lundgren'))
      end)

      it('normalize_suffixes=false treats suffix as last name', function()
        -- 'Kevin Li K' with no stripping → three parts, last = 'k'
        local c = resolve.build_candidates('Kevin Li K', 'first.last', { normalize_suffixes = false })
        assert.is_truthy(vim.tbl_contains(c, 'kevin.k'))
      end)

      it('normalize_suffixes=false with flast uses raw last part', function()
        local c = resolve.build_candidates('Kevin Li K', 'flast', { normalize_suffixes = false })
        assert.is_truthy(vim.tbl_contains(c, 'kk'))
      end)
    end)

    describe('multi-part name handling (first.last pattern)', function()
      it('three-part name generates mid variants', function()
        local c = resolve.build_candidates('Kevin K Li', 'first.last', {})
        assert.is_truthy(vim.tbl_contains(c, 'kevin.k.li'))
        assert.is_truthy(vim.tbl_contains(c, 'kevin.li.k'))
        assert.is_truthy(vim.tbl_contains(c, 'kevin.li'))
      end)

      it('four-plus-part name uses only first and last', function()
        -- parts > 3: only first.last generated (no mid logic)
        local c = resolve.build_candidates('Anna Maria Von Berg', 'first.last', {})
        assert.is_truthy(vim.tbl_contains(c, 'anna.berg'))
      end)

      it('flast three-part name uses first initial and last', function()
        local c = resolve.build_candidates('Kevin K Li', 'flast', {})
        assert.is_truthy(vim.tbl_contains(c, 'kli'))
      end)
    end)

    describe('unicode / non-ASCII names', function()
      it('åäö with transliterate=true all map to ascii', function()
        local c = resolve.build_candidates('Åke Öhlund', 'first.last', { transliterate = true })
        assert.is_truthy(vim.tbl_contains(c, 'ake.ohlund'))
      end)

      it('mixed accents with first_last pattern', function()
        local c = resolve.build_candidates('Søren Müller', 'first_last', { transliterate = true })
        assert.is_truthy(vim.tbl_contains(c, 'soren_muller'))
      end)

      it('æ ligature transliterates to ae', function()
        local c = resolve.build_candidates('Jæger Hansen', 'first.last', { transliterate = true })
        assert.is_truthy(vim.tbl_contains(c, 'jaeger.hansen'))
      end)
    end)

    it('returns empty for single-word name', function()
      local c = resolve.build_candidates('Jonny', 'first.last', {})
      assert.equals(0, #c)
    end)

  end) -- build_candidates

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
