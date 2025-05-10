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
end

return M
