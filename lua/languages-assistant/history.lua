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

return M
