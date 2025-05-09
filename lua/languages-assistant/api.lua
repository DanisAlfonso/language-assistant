-- API module for handling requests to AI services
local M = {}

-- Get parent module
local parent = require("languages-assistant")

-- Function to safely get the API key from various sources
local function get_api_key()
    local config = parent.config.api
    
    -- For Gemini API
    if config.provider == "gemini" then
        -- First try environment variable
        if config.gemini.key_source == "env" then
            local env_key = vim.env[config.gemini.env_var_name]
            if env_key and env_key ~= "" then
                return env_key
            end
        end
        
        -- Then try from a local config file
        if config.gemini.key_source == "config_file" then
            local config_path = config.gemini.config_path
            local ok, config_data = pcall(dofile, config_path)
            if ok and config_data and config_data.gemini_api_key and config_data.gemini_api_key ~= "" then
                return config_data.gemini_api_key
            end
        end
        
        -- Finally try from a secrets file in data directory
        if config.gemini.key_source == "data_file" then
            local secrets_path = config.gemini.data_path
            local ok, secrets = pcall(dofile, secrets_path)
            if ok and secrets and secrets.gemini_api_key and secrets.gemini_api_key ~= "" then
                return secrets.gemini_api_key
            end
        end
    end
    
    -- For OpenAI API
    if config.provider == "openai" then
        -- First try environment variable
        if config.openai.key_source == "env" then
            local env_key = vim.env[config.openai.env_var_name]
            if env_key and env_key ~= "" then
                return env_key
            end
        end
        
        -- Add other sources if needed
    end
    
    -- Return empty string if not found
    return ""
end

-- Function to extract the relevant content from API response
local function extract_explanation(response)
    -- Extract content from JSON response
    if not response then
        return "No explanation available"
    end
    
    -- Check for common API error patterns
    if response:match("error") then
        -- Log the full response for debugging
        vim.notify("API Error: " .. response, vim.log.levels.ERROR)
        
        local error_message = "API Error: "
        
        -- Try to extract specific error message
        local error_match = response:match('"message":%s*"([^"]+)"')
        if error_match then
            error_message = error_message .. error_match
        else
            error_message = error_message .. "Unknown error occurred"
        end
        
        return error_message
    end
    
    -- Try to parse the JSON response
    local ok, parsed = pcall(vim.fn.json_decode, response)
    if not ok or not parsed then
        vim.notify("Failed to parse response: " .. response, vim.log.levels.ERROR)
        return "Failed to parse response from AI service"
    end
    
    -- Extract the text content based on provider
    local content = ""
    
    if parent.config.api.provider == "gemini" then
        if parsed.candidates and parsed.candidates[1] and 
           parsed.candidates[1].content and 
           parsed.candidates[1].content.parts then
            for _, part in ipairs(parsed.candidates[1].content.parts) do
                if part.text then
                    content = content .. part.text
                end
            end
        end
    elseif parent.config.api.provider == "openai" then
        if parsed.choices and parsed.choices[1] and parsed.choices[1].message and parsed.choices[1].message.content then
            content = parsed.choices[1].message.content
        end
    end
    
    if content == "" then
        vim.notify("No content found in response", vim.log.levels.WARN)
        return "No explanation found in response"
    end
    
    return content
end

-- Make HTTP request to AI service API
local function make_api_request(prompt, callback)
    local config = parent.config.api
    local API_KEY = get_api_key()
    local API_ENDPOINT = ""
    
    -- Set endpoint based on provider
    if config.provider == "gemini" then
        API_ENDPOINT = config.gemini.endpoint
    elseif config.provider == "openai" then
        API_ENDPOINT = config.openai.endpoint
    end
    
    -- Check if API key is available
    if API_KEY == "" then
        callback("No API key found. Please set an API key through environment variables or configuration files.")
        vim.notify("Missing API key. See documentation for setup instructions.", vim.log.levels.ERROR)
        return
    end

    -- Check if curl is available
    if vim.fn.executable("curl") ~= 1 then
        callback("curl executable not found. Please install curl.")
        vim.notify("curl is required for API requests", vim.log.levels.ERROR)
        return
    end

    -- Prepare temporary file for the response
    local temp_file = vim.fn.tempname()
    local error_file = vim.fn.tempname()
    
    -- Prepare the request body based on provider
    local request_body = ""
    
    if config.provider == "gemini" then
        request_body = vim.fn.json_encode({
            contents = {
                {
                    parts = {
                        { text = prompt }
                    }
                }
            },
            generationConfig = {
                temperature = 0.2,
                topK = 40,
                topP = 0.95,
                maxOutputTokens = 1000,
            }
        })
    elseif config.provider == "openai" then
        request_body = vim.fn.json_encode({
            model = "gpt-3.5-turbo",
            messages = {
                { role = "system", content = "You are a helpful assistant focused on language learning." },
                { role = "user", content = prompt }
            },
            temperature = 0.3,
            max_tokens = 1000
        })
    end
    
    -- Create a temporary JSON file for the request body to avoid shell escaping issues
    local request_file = vim.fn.tempname() .. ".json"
    local req_file = io.open(request_file, "w")
    if req_file then
        req_file:write(request_body)
        req_file:close()
    else
        callback("Failed to create request file")
        return
    end
    
    -- Build the curl command with error handling
    local cmd = ""
    
    if config.provider == "gemini" then
        cmd = string.format(
            "curl -s -X POST '%s?key=%s' " ..
            "-H 'Content-Type: application/json' " ..
            "-d @%s " ..
            "-o %s " ..
            "2>%s",
            API_ENDPOINT,
            API_KEY,
            request_file,
            temp_file,
            error_file
        )
    elseif config.provider == "openai" then
        cmd = string.format(
            "curl -s -X POST '%s' " ..
            "-H 'Content-Type: application/json' " ..
            "-H 'Authorization: Bearer %s' " ..
            "-d @%s " ..
            "-o %s " ..
            "2>%s",
            API_ENDPOINT,
            API_KEY,
            request_file,
            temp_file,
            error_file
        )
    end
    
    -- Execute the command asynchronously if plenary.job is available
    local has_plenary, Job = pcall(require, "plenary.job")
    
    if has_plenary then
        -- Use plenary.job for better async handling
        Job:new({
            command = "curl",
            args = vim.split(cmd:gsub("^curl%s+", ""), " "),
            on_exit = function(j, exit_code)
                -- Clean up the request file
                os.remove(request_file)
                
                if exit_code ~= 0 then
                    -- Read the error output
                    local err_file = io.open(error_file, "r")
                    local error_msg = "API request failed with exit code: " .. exit_code
                    if err_file then
                        local err_content = err_file:read("*all")
                        err_file:close()
                        if err_content and err_content ~= "" then
                            error_msg = error_msg .. "\nError: " .. err_content
                        end
                    end
                    os.remove(error_file)
                    
                    -- Show detailed error in log
                    vim.notify(error_msg, vim.log.levels.ERROR)
                    
                    callback("Failed to get explanation from AI service. Please check the logs.")
                    return
                end
                
                -- Read the response from temp file
                local file = io.open(temp_file, "r")
                if not file then
                    callback("Failed to read API response")
                    os.remove(error_file)
                    return
                end
                
                local response = file:read("*all")
                file:close()
                
                -- Clean up temp files
                os.remove(temp_file)
                os.remove(error_file)
                
                -- Process the response
                local explanation = extract_explanation(response)
                callback(explanation)
            end,
        }):start()
    else
        -- Fallback to vim.fn.jobstart
        vim.fn.jobstart(cmd, {
            on_exit = function(_, exit_code)
                -- Clean up the request file
                os.remove(request_file)
                
                if exit_code ~= 0 then
                    -- Read the error output
                    local err_file = io.open(error_file, "r")
                    local error_msg = "API request failed with exit code: " .. exit_code
                    if err_file then
                        local err_content = err_file:read("*all")
                        err_file:close()
                        if err_content and err_content ~= "" then
                            error_msg = error_msg .. "\nError: " .. err_content
                        end
                    end
                    os.remove(error_file)
                    
                    -- Show detailed error in log
                    vim.notify(error_msg, vim.log.levels.ERROR)
                    
                    callback("Failed to get explanation from AI service. Please check the logs.")
                    return
                end
                
                -- Read the response from temp file
                local file = io.open(temp_file, "r")
                if not file then
                    callback("Failed to read API response")
                    os.remove(error_file)
                    return
                end
                
                local response = file:read("*all")
                file:close()
                
                -- Clean up temp files
                os.remove(temp_file)
                os.remove(error_file)
                
                -- Process the response
                local explanation = extract_explanation(response)
                callback(explanation)
            end
        })
    end
end

-- Function to get explanation for a word or phrase
function M.get_explanation(text, callback)
    -- Format the message to get a structured response for vocabulary
    local formatted_prompt = string.format([[
I'm learning English and I need help understanding the following word or phrase: %s

Please respond with this exact format:
EXPLANATION:
[Clear definition of the word/phrase]

EXAMPLES:
1. [First example sentence showing usage]
2. [Second example with perhaps a different context]
3. [Third example showing common usage]

NOTES:
- Related terms: [similar words or synonyms]
- Origin: [brief etymology if relevant]
- Common mistakes: [how people often misuse this term, if applicable]
]], text)
    
    -- Show a notification that we're requesting
    vim.notify("Requesting explanation for: " .. text, vim.log.levels.INFO)
    
    -- Make the API request with fallback
    make_api_request(formatted_prompt, function(response)
        -- Check if response indicates an error
        if response:match("Failed to") or response:match("API Error") or response:match("failed with exit code") then
            -- Provide a fallback dictionary definition
            vim.notify("API request failed, using fallback dictionary function", vim.log.levels.WARN)
            
            -- Create a fallback definition
            local fallback = string.format([[
EXPLANATION:
For the word/phrase "%s", I couldn't retrieve an AI-generated explanation due to API issues.

ALTERNATIVES TO LOOK UP THIS WORD:
1. Try an offline dictionary if available
2. Look up this word later when the API is working
3. Use a browser to search for: "%s definition"

NOTES:
- The API request failed. This could be due to:
  - API key issues
  - Network connectivity problems
  - Rate limiting
  - Service availability
]], text, text)
            
            callback(fallback)
        else
            callback(response)
        end
    end)
end

-- Function to translate text to target language
function M.translate_text(text, target_language, callback)
    -- Format the prompt for translation
    local formatted_prompt = string.format([[
Translate the following text from %s into %s:

"%s"

Please respond with this exact format:
TRANSLATION:
[Your translation]

PRONUNCIATION GUIDE:
[Brief pronunciation help if needed]

NOTES:
- Alternative translations (if applicable)
- Any cultural context important for understanding
]], parent.config.languages.source, target_language, text)
    
    -- Show a notification that we're requesting
    vim.notify("Translating to " .. target_language .. ": " .. text, vim.log.levels.INFO)
    
    -- Make the API request
    make_api_request(formatted_prompt, function(response)
        -- Check if response indicates an error
        if response:match("Failed to") or response:match("API Error") or response:match("failed with exit code") then
            callback("Translation failed. Please try again later.")
        else
            callback(response)
        end
    end)
end

-- Test the API connection
function M.test_connection(silent)
    silent = silent or false
    local test_query = "Hello, this is a test query to verify API connectivity."
    
    -- Make a minimal request to test connection
    make_api_request(test_query, function(response)
        if response:match("Failed to") or response:match("API Error") or response:match("failed with exit code") then
            if not silent then
                vim.notify("API connection test failed: " .. response, vim.log.levels.ERROR)
            end
            return false
        else
            if not silent then
                vim.notify("API connection test successful", vim.log.levels.INFO)
            end
            return true
        end
    end)
end

return M
