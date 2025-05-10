-- Keymaps module for language learning plugin
local M = {}

-- Get parent module
local parent = require("languages-assistant")

-- Setup function to register keymaps
function M.setup()
    local cfg = parent.config.keymaps
    
    -- Define prefix and mappings
    local prefix = cfg.prefix
    local keymaps = {
        -- Format: { mode, key, command, description }
        { "v", prefix .. cfg.explain, ":<C-u>LanguageExplain<CR>", "Explain selected text" },
        { "v", prefix .. cfg.translate, ":<C-u>LanguageTranslate<CR>", "Translate selected text" },
        { "n", prefix .. cfg.history, ":LanguageHistory<CR>", "Show language learning history" },
        { "n", prefix .. cfg.export, ":LanguageExport<CR>", "Export flashcards" },
        { "n", prefix .. cfg.flashcards, ":LanguageFlashcards<CR>", "Study due flashcards" },
        { "n", prefix .. cfg.flashcards_browse, ":LanguageFlashcardsBrowse<CR>", "Browse all flashcards" },
        { "n", prefix .. "a", ":LanguageHistoryToFlashcards<CR>", "Convert history to flashcards" },
        { "n", prefix .. cfg.clear, ":LanguageClear<CR>", "Clear history" },
        { "n", prefix .. cfg.location, ":LanguageInfo<CR>", "Show configuration info" },
        { "n", prefix .. "d", ":LanguageToggleDirection<CR>", "Toggle translation direction" },
    }
    
    -- Register keymaps
    for _, keymap in ipairs(keymaps) do
        local mode, key, cmd, desc = unpack(keymap)
        vim.keymap.set(mode, key, cmd, { noremap = true, silent = true, desc = desc })
    end

    -- Register with which-key if available
    if parent.config.integrations.which_key then
        pcall(function()
            local ok, which_key = pcall(require, "which-key")
            if ok then
                -- Try to register both the old and new format since different versions
                -- of which-key use different formats
                
                -- Modern format (preferred)
                pcall(function()
                    which_key.add({
                        { prefix, group = "Language Learning" }
                    })
                end)
                
                -- Legacy format as fallback
                pcall(function()
                    which_key.register({
                        [prefix] = { name = "Language Learning" }
                    })
                end)
            end
        end)
    end
    
    -- Register flashcard-specific keybindings
    M.setup_flashcard_keybindings()
end

-- Set up keybindings specifically for flashcard review UI
function M.setup_flashcard_keybindings()
    -- These will be applied to flashcard buffers when created by the UI module
    M.flashcard_keybindings = {
        -- Navigation
        { "n", "j", "Next Card" },
        { "n", "k", "Previous Card" },
        { "n", "n", "Next Card" },
        { "n", "p", "Previous Card" },
        -- Rating
        { "n", "1", "Again (1)" },
        { "n", "2", "Hard (2)" },
        { "n", "3", "Good (3)" },
        { "n", "4", "Easy (4)" },
        -- Actions
        { "n", "<space>", "Flip Card" },
        { "n", "<CR>", "Flip Card" },
        { "n", "f", "Flip Card" },
        { "n", "e", "Edit Card" },
        { "n", "d", "Delete Card" },
        { "n", "t", "Add Tag" },
        { "n", "s", "Mark Suspended" },
        -- Closing
        { "n", "q", "Quit" },
        { "n", "<Esc>", "Quit" },
    }
end

return M
