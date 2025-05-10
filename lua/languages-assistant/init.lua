-- Languages Assistant for Neovim
-- A plugin for language learning and vocabulary building with AI assistance

local M = {}

-- Default configuration
M.default_config = {
    -- API options
    api = {
        provider = "gemini", -- "gemini", "openai", "azure", "offline"
        gemini = {
            endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent",
            key_source = "env", -- "env", "config_file", "data_file"
            env_var_name = "GEMINI_API_KEY",
            config_path = vim.fn.stdpath("config") .. "/languages_assistant_config.lua",
            data_path = vim.fn.stdpath("data") .. "/languages_assistant_secrets.lua"
        },
        openai = {
            endpoint = "https://api.openai.com/v1/chat/completions",
            key_source = "env",
            env_var_name = "OPENAI_API_KEY"
        }
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
            enabled = true,
            loading = "󰔟",
            error = "",
            success = "󰄴",
            warning = ""
        },
        flashcards = {
            card_width = 80,
            card_padding = 2,
            hide_scrollbar = true,
            highlight_current = true,
            highlight_group = "CursorLine",
        }
    },
    
    -- Storage options
    storage = {
        history_path = vim.fn.stdpath("data") .. "/languages_assistant_history.json",
        flashcards_path = vim.fn.stdpath("data") .. "/languages_assistant_flashcards.json",
        export_path = vim.fn.expand("~/languages_assistant_flashcards.txt"),
        auto_save = true
    },
    
    -- Flashcards options (FSRS algorithm)
    flashcards = {
        target_retention = 0.9, -- 90% target retention rate
        maximum_interval = 365, -- maximum interval in days
        learn_ahead_time = 0, -- 0 means only actually due cards are shown
        minimum_cards_per_session = 20, -- minimum cards to show per session (if available)
        fuzzy_intervals = true, -- randomize intervals by ±5% for better retention
        display_retention = true, -- show retention estimate when reviewing
        default_tags = {"language-learning"}, -- default tags for new cards
        review_mode = "spaced", -- "spaced" or "random"
    },
    
    -- Keymappings
    keymaps = {
        enabled = true,
        prefix = "<leader>l",
        explain = "e", -- <leader>le - explain selection
        translate = "t", -- <leader>lt - translate selection
        history = "h", -- <leader>lh - show history
        export = "x", -- <leader>lx - export flashcards
        flashcards = "f", -- <leader>lf - study flashcards
        flashcards_browse = "b", -- <leader>lb - browse all flashcards
        clear = "c", -- <leader>lc - clear history
        location = "p", -- <leader>lp - show file locations
    },
    
    -- Languages
    languages = {
        source = "es", -- Source language (Spanish)
        target = "en", -- Target language (English)
        additional = {}, -- Additional languages to support
        native_speaker = true, -- If user is a native speaker of source language
        learning_focus = "english" -- Focus on English learning
    },
    
    -- Integrations
    integrations = {
        which_key = true, -- integrate with which-key if available
        telescope = true, -- integrate with telescope if available
        copilot = false   -- use copilot for some features if available
    },
    
    -- Offline mode options (when API is not available)
    offline = {
        dictionary_path = vim.fn.stdpath("data") .. "/languages_assistant_dictionary.json"
    }
}

-- User configuration (will be merged with defaults)
M.config = {}

-- Plugin state
M.state = {
    history = {},
    flashcards = {},
    initialized = false
}

-- Core modules (lazy-loaded)
local modules = {
    api = function() return require("languages-assistant.api") end,
    history = function() return require("languages-assistant.history") end,
    ui = function() return require("languages-assistant.ui") end,
    commands = function() return require("languages-assistant.commands") end,
    keymaps = function() return require("languages-assistant.keymaps") end,
    integrations = function() return require("languages-assistant.integrations") end,
    flashcards = function() return require("languages-assistant.flashcards") end,
    flashcards_ui = function() return require("languages-assistant.flashcards-ui") end
}

-- Setup function with configuration
function M.setup(opts)
    -- Merge user config with defaults
    M.config = vim.tbl_deep_extend("force", {}, M.default_config, opts or {})
    
    -- Initialize history
    modules.history().load()
    
    -- Initialize flashcards
    modules.flashcards().load()
    
    -- Set up commands
    modules.commands().setup()
    
    -- Set up keymaps if enabled
    if M.config.keymaps.enabled then
        modules.keymaps().setup()
    end
    
    -- Set up integrations
    if M.config.integrations.which_key then
        pcall(modules.integrations().setup_which_key)
    end
    
    -- Mark as initialized
    M.state.initialized = true
    
    return M
end

-- Main functionality: Explain selected text
function M.explain_selection()
    -- Get visual selection
    local text = M.get_visual_selection()
    if not text or text == "" then
        vim.notify("No text selected", vim.log.levels.WARN)
        return
    end
    
    -- Show loading UI
    local buf, win = modules.ui().create_floating_window("Explanation: " .. text)
    modules.ui().set_loading_content(buf, text)
    
    -- Request explanation via API
    modules.api().get_explanation(text, function(explanation)
        -- Update UI with result - use vim.schedule to defer to a safe context
        vim.schedule(function()
            if vim.api.nvim_buf_is_valid(buf) then
                modules.ui().update_content(buf, explanation)
                
                -- Add to history
                modules.history().add_entry({
                    type = "explanation",
                    text = text,
                    result = explanation,
                    timestamp = os.date("%Y-%m-%d %H:%M:%S"),
                    context = vim.fn.expand("%:p")
                })
            end
        end)
    end)
end

-- Translate selected text
function M.translate_text()
    -- Get visual selection
    local text = M.get_visual_selection()
    if not text or text == "" then
        vim.notify("No text selected", vim.log.levels.WARN)
        return
    end
    
    -- Show loading UI
    local buf, win = modules.ui().create_floating_window("Translation: " .. text)
    modules.ui().set_loading_content(buf, text)
    
    -- Request translation via API
    modules.api().translate_text(text, M.config.languages.target, function(translation)
        -- Update UI with result - use vim.schedule to defer to a safe context
        vim.schedule(function()
            if vim.api.nvim_buf_is_valid(buf) then
                modules.ui().update_content(buf, translation, function() 
                    -- Add option to convert to flashcard
                    if vim.api.nvim_buf_is_valid(buf) then
                        vim.api.nvim_buf_set_lines(buf, -1, -1, false, {
                            "",
                            "Press 'f' to add to flashcards or 'q' to close"
                        })
                        
                        -- Add keymapping to create flashcard
                        vim.api.nvim_buf_set_keymap(buf, 'n', 'f', '', {
                            noremap = true,
                            silent = true,
                            callback = function()
                                -- Add as flashcard
                                modules.flashcards().add_card({
                                    front = text,
                                    back = translation,
                                    type = "translation",
                                    source_lang = M.config.languages.source,
                                    target_lang = M.config.languages.target,
                                    created_at = os.date("%Y-%m-%d %H:%M:%S")
                                })
                                vim.api.nvim_buf_set_lines(buf, -2, -1, false, {
                                    "",
                                    "Added to flashcards successfully! Press 'q' to close."
                                })
                            end
                        })
                    end
                end)
                
                -- Add to history
                modules.history().add_entry({
                    type = "translation",
                    text = text,
                    result = translation,
                    timestamp = os.date("%Y-%m-%d %H:%M:%S"),
                    source_lang = M.config.languages.source,
                    target_lang = M.config.languages.target
                })
            end
        end)
    end)
end

-- Show history in a floating window
function M.show_history()
    modules.ui().show_history_window()
end

-- Export flashcards in Anki format
function M.export_flashcards()
    modules.flashcards().export_flashcards()
end

-- Utility function to get visual selection
function M.get_visual_selection()
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    local start_line, start_col = start_pos[2], start_pos[3]
    local end_line, end_col = end_pos[2], end_pos[3]
    
    local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
    if #lines == 0 then return "" end
    
    if #lines > 1 then
        lines[1] = string.sub(lines[1], start_col)
        lines[#lines] = string.sub(lines[#lines], 1, end_col)
    else
        lines[1] = string.sub(lines[1], start_col, end_col)
    end
    
    return table.concat(lines, " ")
end

return M
