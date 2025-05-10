-- History module for language learning plugin
local M = {}

-- Get parent module
local parent = require("languages-assistant")

-- Load history from file
function M.load()
    -- Create an empty history if the module is just starting
    parent.state.history = parent.state.history or {}
    
    -- Try to load history from storage file
    local history_path = parent.config.storage.history_path
    local file = io.open(history_path, "r")
    
    -- If file exists, read the history
    if file then
        local content = file:read("*all")
        file:close()
        
        -- Try to parse JSON
        if content and content ~= "" then
            local ok, decoded = pcall(vim.fn.json_decode, content)
            if ok and decoded then
                parent.state.history = decoded
                return true
            end
        end
    end
    
    -- If we get here, we couldn't load history
    parent.state.history = {}
    return false
end

-- Save history to file
function M.save()
    -- Get history and path
    local history = parent.state.history
    local history_path = parent.config.storage.history_path
    
    -- Try to encode history to JSON
    local ok, encoded = pcall(vim.fn.json_encode, history)
    if not ok or not encoded then
        vim.notify("Failed to encode history", vim.log.levels.ERROR)
        return false
    end
    
    -- Try to open file for writing
    local file = io.open(history_path, "w")
    if not file then
        vim.notify("Failed to open history file for writing", vim.log.levels.ERROR)
        return false
    end
    
    -- Write and close
    file:write(encoded)
    file:close()
    
    return true
end

-- Add entry to history
function M.add_entry(entry)
    -- Insert at beginning
    table.insert(parent.state.history, 1, entry)
    
    -- Auto-save if enabled
    if parent.config.storage.auto_save then
        M.save()
    end
    
    return true
end

-- Export flashcards to file
function M.export_flashcards()
    local history = parent.state.history
    local export_path = parent.config.storage.export_path
    
    -- Check if there's anything to export
    if #history == 0 then
        vim.notify("No history entries to export", vim.log.levels.WARN)
        return false
    end
    
    -- Try to open file for writing
    local file = io.open(export_path, "w")
    if not file then
        vim.notify("Failed to open export file for writing", vim.log.levels.ERROR)
        return false
    end
    
    -- Write header
    file:write("# Anki-compatible flashcard export\n")
    file:write("# Format: front\tback\n\n")
    
    -- Write entries
    local count = 0
    for _, entry in ipairs(history) do
        -- Skip entries without required fields
        if entry.text and entry.result then
            local front = entry.text:gsub("\n", "<br>")
            local back = entry.result:gsub("\n", "<br>")
            
            file:write(front .. "\t" .. back .. "\n")
            count = count + 1
        end
    end
    
    file:close()
    
    -- Notify user
    vim.notify("Exported " .. count .. " flashcards to " .. export_path, vim.log.levels.INFO)
    
    return true
end

-- Clear history
function M.clear_history()
    -- Ask for confirmation
    vim.ui.select(
        { "Yes", "No" },
        { prompt = "Are you sure you want to clear all history?" },
        function(choice)
            if choice == "Yes" then
                -- Clear the history
                parent.state.history = {}
                
                -- Save the empty history to file
                if M.save() then
                    vim.notify("History has been cleared", vim.log.levels.INFO)
                    
                    -- Close any history window that might be open
                    for _, win in ipairs(vim.api.nvim_list_wins()) do
                        local ok, buf = pcall(vim.api.nvim_win_get_buf, win)
                        if ok then
                            local ok, buf_name = pcall(vim.api.nvim_buf_get_name, buf)
                            if ok and buf_name and buf_name:match("Language Learning History") then
                                pcall(vim.api.nvim_win_close, win, true)
                            end
                        end
                    end
                    
                    -- If we can't find a window to close, reopen the history window to show it's empty
                    vim.defer_fn(function()
                        require("languages-assistant").show_history()
                    end, 100)
                else
                    vim.notify("Failed to save cleared history", vim.log.levels.ERROR)
                end
            end
        end
    )
    
    return true
end

return M
