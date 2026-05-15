# nvim-mail

Neovim Lua plugin for mail compose enhancements. Designed for neomutt + nvr workflow.

## Features

- **Attachment awareness** — warns on save if body mentions "attach/enclosed/PFA" but no actual attachment marker found
- **Muttlook marker visibility** — shows `↩ replying to: <msgid>` as virtual text over the raw `[//]: # (muttlook-reply-to:...)` line

## Install

lazy.nvim (local path):
```lua
{ dir = '~/codebase/tools/nvim-mail', ft = 'mail' }
```

Or from GitHub:
```lua
{ 'monkeyxite/nvim-mail', ft = 'mail' }
```

## Usage

The plugin auto-loads via `ftplugin/mail.lua`. Or call manually:

```lua
require('nvim-mail').setup()
```

## Tests

```bash
cd ~/codebase/tools/nvim-mail
nvim --headless --clean -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/mail/ {minimal_init = 'tests/minimal_init.lua'}"
```

## Roadmap

- [ ] Thread context split (`<leader>mt` — notmuch thread in vsplit)
- [ ] Contact autocomplete (nvim-cmp source for khard/LDAP)
- [ ] Smart snippets (context-aware by recipient)
- [ ] Auto-signature selection
- [ ] Inline markdown preview
