-- Commands module for language learning plugin
local M = {}

-- Get parent module
local parent = require("languages-assistant")

-- Setup function to create user commands
function M.setup()
    -- Main explanation command
    vim.api.nvim_create_user_command("LanguageExplain", function()
        parent.explain_selection()
    end, { 
        desc = "Explain selected text in the target language",
        range = true 
    })
    
    -- Translation command
    vim.api.nvim_create_user_command("LanguageTranslate", function()
        parent.translate_text()
    end, { 
        desc = "Translate selected text to the target language",
        range = true 
    })
    
    -- History command
    vim.api.nvim_create_user_command("LanguageHistory", function()
        parent.show_history()
    end, { 
        desc = "Show language learning history" 
    })
    
    -- Export flashcards command
    vim.api.nvim_create_user_command("LanguageExport", function()
        parent.export_flashcards()
    end, { 
        desc = "Export language learning flashcards" 
    })
    
    -- Configuration info command
    vim.api.nvim_create_user_command("LanguageInfo", function()
        M.show_configuration_info()
    end, { 
        desc = "Show plugin configuration information" 
    })
    
    -- Test API connection command
    vim.api.nvim_create_user_command("LanguageTest", function()
        require("languages-assistant.api").test_connection(false)
    end, { 
        desc = "Test AI service API connection" 
    })
    
    -- Create completion commands with shortened aliases
    if parent.config.commands and parent.config.commands.short_aliases then
        vim.api.nvim_create_user_command("LExplain", function()
            parent.explain_selection()
        end, { desc = "Short alias for LanguageExplain", range = true })
        
        vim.api.nvim_create_user_command("LTranslate", function()
            parent.translate_text()
        end, { desc = "Short alias for LanguageTranslate", range = true })
    end
end

-- Show configuration information
function M.show_configuration_info()
    local cfg = parent.config
    
    -- Create buffer for the info
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
    vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
    
    -- Prepare content
    local lines = {
        "Languages Assistant Plugin Configuration",
        "=====================================",
        "",
        "API Configuration:",
        "  Provider: " .. cfg.api.provider,
        "  API Key Source: " .. (cfg.api[cfg.api.provider] and cfg.api[cfg.api.provider].key_source or "unknown"),
        "",
        "Language Settings:",
        "  Source Language: " .. cfg.languages.source,
        "  Target Language: " .. cfg.languages.target,
        "",
        "Storage:",
        "  History Path: " .. cfg.storage.history_path,
        "  Auto Save: " .. (cfg.storage.auto_save and "Yes" or "No"),
        "",
        "Keymaps:",
        "  Enabled: " .. (cfg.keymaps.enabled and "Yes" or "No"),
        "  Prefix: " .. cfg.keymaps.prefix,
        "",
        "Commands:",
        "  :LanguageExplain - Explain selected text",
        "  :LanguageTranslate - Translate selected text",
        "  :LanguageHistory - Show learning history",
        "  :LanguageExport - Export flashcards",
        "  :LanguageInfo - Show this information",
        "  :LanguageTest - Test API connection",
    }
    
    -- Set buffer content
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    
    -- Open in a floating window
    local width = math.min(80, vim.o.columns - 4)
    local height = math.min(30, #lines + 2, vim.o.lines - 4)
    local row = (vim.o.lines - height) / 2
    local col = (vim.o.columns - width) / 2
    
    local opts = {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded"
    }
    
    local win = vim.api.nvim_open_win(buf, true, opts)
    
    -- Set buffer options for better readability
    vim.api.nvim_win_set_option(win, "conceallevel", 0)
    vim.api.nvim_win_set_option(win, "foldenable", false)
    vim.api.nvim_buf_set_option(buf, "modifiable", false)
    
    -- Set syntax highlighting if possible
    vim.cmd("syntax match Title /^Languages Assistant Plugin Configuration$/")
    vim.cmd("syntax match Type /^[A-Za-z ]*:$/")
    vim.cmd("syntax match Identifier /^  [A-Za-z ]*:/")
    
    -- Add keybinding to close the window
    local opts = { noremap = true, silent = true, buffer = buf }
    vim.keymap.set("n", "q", "<cmd>q<CR>", opts)
    vim.keymap.set("n", "<Esc>", "<cmd>q<CR>", opts)
end

return M
