# Neovim Languages Assistant

A Neovim plugin for language learners to look up vocabulary, translate text, and build personalized flashcard collections using AI.

## Features

- 📚 **Vocabulary Lookup**: Get detailed explanations of words and phrases with examples
- 🔄 **Translation**: Translate text between languages (default: English to Spanish)
- 📝 **History Tracking**: Keep a record of all your vocabulary lookups
- 📋 **Flashcard Export**: Export your vocabulary history to Anki-compatible flashcards
- 🔌 **AI Integration**: Uses Google Gemini API or OpenAI for high-quality definitions and translations

## Screenshots

![Vocabulary Lookup](https://raw.githubusercontent.com/DanisAlfonso/nvim-languages-assistant/main/screenshots/vocabulary.png)
![Translation](https://raw.githubusercontent.com/DanisAlfonso/nvim-languages-assistant/main/screenshots/translation.png)

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "DanisAlfonso/nvim-languages-assistant",
  dependencies = { "nvim-lua/plenary.nvim" },
  lazy = true, -- Load on demand for faster startup
  cmd = {
    "LanguageExplain",
    "LanguageTranslate",
    "LanguageHistory",
    "LanguageExport"
  },
  keys = {
    { "<leader>le", mode = "v", desc = "Explain selection" },
    { "<leader>lt", mode = "v", desc = "Translate selection" },
    { "<leader>lh", desc = "Show language history" },
    { "<leader>lx", desc = "Export flashcards" },
  },
  config = function()
    require("languages-assistant").setup({
      -- Your configuration here (see Configuration section)
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'DanisAlfonso/nvim-languages-assistant',
  requires = { 'nvim-lua/plenary.nvim' },
  config = function()
    require('languages-assistant').setup()
  end
}
```

## API Key Setup

This plugin uses AI services which require API keys. You can choose between Google Gemini and OpenAI:

### Google Gemini API (Default)

1. Get a free API key from [Google AI Studio](https://aistudio.google.com/app/apikey)

2. Choose one of these methods to configure your API key:

   **Option A: Environment Variable (Recommended)**
   ```bash
   # Add to your shell configuration (.bashrc, .zshrc, etc.)
   export GEMINI_API_KEY="your-api-key-here"
   ```

   **Option B: Local Configuration File**
   Create a file `~/.config/nvim/languages_assistant_config.lua`:
   ```lua
   return {
     gemini_api_key = "your-api-key-here"
   }
   ```

   **Option C: Data Directory File**
   Create a file `~/.local/share/nvim/languages_assistant_secrets.lua`:
   ```lua
   return {
     gemini_api_key = "your-api-key-here"
   }
   ```

### OpenAI API

If you prefer using OpenAI:

1. Get an API key from [OpenAI Platform](https://platform.openai.com/api-keys)

2. Set your OpenAI API key using one of the methods above (environment variable is recommended)
   ```bash
   export OPENAI_API_KEY="your-openai-api-key-here"
   ```

3. Configure the plugin to use OpenAI:
   ```lua
   require("languages-assistant").setup({
     api = {
       provider = "openai",
     }
   })
   ```

## Usage

| Command | Keybinding | Description |
|---------|------------|-------------|
| `:LanguageExplain` | `<leader>le` (visual mode) | Explain selected word/phrase |
| `:LanguageTranslate` | `<leader>lt` (visual mode) | Translate selected text |
| `:LanguageHistory` | `<leader>lh` | Show lookup history |
| `:LanguageExport` | `<leader>lx` | Export to Anki flashcards |
| `:LanguageInfo` | `<leader>lf` | Show configuration information |
| `:LanguageTest` | - | Test API connection |

## Configuration

The plugin comes with sensible defaults, but you can customize it:

```lua
require("languages-assistant").setup({
  -- API configuration
  api = {
    provider = "gemini", -- "gemini", "openai", "offline"
    gemini = {
      key_source = "env", -- "env", "config_file", "data_file"
      env_var_name = "GEMINI_API_KEY",
      -- Override default endpoints if needed
      endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent",
    },
    openai = {
      key_source = "env",
      env_var_name = "OPENAI_API_KEY",
    }
  },
  
  -- Languages
  languages = {
    source = "en", -- Source language
    target = "es", -- Target language for translations
  },
  
  -- UI options
  ui = {
    window = {
      width = 80,
      height = 20,
      border = "rounded",
      position = "center" -- "center", "top", "bottom", "left", "right"
    },
    icons = {
      enabled = true, -- Set to false if you don't have a Nerd Font
    }
  },
  
  -- Custom keymaps
  keymaps = {
    enabled = true,
    prefix = "<leader>l",
    explain = "e",   -- <leader>le
    translate = "t", -- <leader>lt
    history = "h",   -- <leader>lh
    export = "x",    -- <leader>lx
    clear = "c",     -- <leader>lc
    location = "f",  -- <leader>lf
  },
  
  -- Storage options
  storage = {
    history_path = vim.fn.stdpath("data") .. "/languages_assistant_history.json",
    export_path = vim.fn.expand("~/languages_assistant_flashcards.txt"),
    auto_save = true,
  },
  
  -- Integration with other plugins
  integrations = {
    which_key = true,
    telescope = true,
  },
  
  -- Command options
  commands = {
    short_aliases = false, -- Set to true to enable shorter command aliases like :LExplain
  }
})
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT

---

**Note**: This plugin requires an active internet connection and API key to access the language services. An offline dictionary mode is planned for future versions.
