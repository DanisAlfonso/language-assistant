# Setup Guide for Neovim Languages Assistant

This guide will walk you through completing the setup of your new Neovim Languages Assistant plugin.

## Step 1: Complete the Missing Module Files

Some module files were created but left empty. You need to implement them:

1. **UI Module** (`lua/languages-assistant/ui.lua`):
   - Implement the UI functions referenced in the main module like `create_floating_window`, `set_loading_content`, `update_content`, etc.
   - Create visual elements to display explanations, translations, and history

2. **History Module** (`lua/languages-assistant/history.lua`):
   - Implement functions to save/load history
   - Add functions for exporting to Anki format
   - Add functions to add entries and manage history

3. **Integrations Module** (`lua/languages-assistant/integrations.lua`):
   - Implement which-key integration
   - Add Telescope integration if desired

## Step 2: Create a GitHub Repository

1. Create a new GitHub repository named `nvim-languages-assistant`
2. Push your local repository to GitHub:

```bash
cd /Users/danny/PJ/Lua/nvim-languages-assistant
git remote add origin https://github.com/DanisAlfonso/nvim-languages-assistant.git
git push -u origin main
```

## Step 3: Update Your Lazy.nvim Configuration

Once your repository is on GitHub, update your Lazy plugin spec:

```lua
-- In ~/.config/nvim/lua/danny/plugins/languages-assistant.lua
return {
  -- Change from local path to GitHub URL
  "DanisAlfonso/nvim-languages-assistant",
  -- Rest of the configuration remains the same
  ...
}
```

## Step 4: Set Up API Key

1. Get your Google Gemini API key from [Google AI Studio](https://aistudio.google.com/app/apikey)
2. Add it to your shell configuration:

```bash
# Add to ~/.zshrc or ~/.bashrc
export GEMINI_API_KEY="your-api-key-here"
```

3. Reload your shell configuration:

```bash
source ~/.zshrc  # or source ~/.bashrc
```

## Step 5: Test the Plugin

1. Restart Neovim
2. Use `:LanguageTest` to test the API connection
3. Try explaining a word by selecting text in visual mode and using `:LanguageExplain`

## Additional Development Tasks

As you continue developing your plugin, consider:

1. Adding screenshots to `screenshots/` directory (create it first)
2. Writing documentation in `doc/` directory
3. Adding Telescope integration for viewing history
4. Implementing offline dictionary mode as a fallback
5. Adding support for more languages and translation directions

## Publishing Your Plugin

Once you're satisfied with your plugin:

1. Add it to the [Neovim Awesome](https://github.com/rockerBOO/awesome-neovim) list
2. Share it on the Neovim subreddit
3. Consider publishing it to [LuaRocks](https://luarocks.org/) for easy installation

## Troubleshooting

If you encounter issues:

- Check the Neovim logs (`:checkhealth`)
- Verify your API key is set correctly
- Make sure all required dependencies are installed
- Check the API response files for error messages 