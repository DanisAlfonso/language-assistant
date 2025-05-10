-- API module for handling requests to AI services
local M = {}

-- Get parent module
local parent = require("languages-assistant")

-- Cache for API key to avoid retrieving it multiple times
local api_key_cache = nil

-- Function to safely get the API key from various sources
local function get_api_key()
    -- Return cached key if available
    if api_key_cache then
        return api_key_cache
    end
    
    local config = parent.config.api
    
    -- For Gemini API
    if config.provider == "gemini" then
        -- First try environment variable
        if config.gemini.key_source == "env" then
            -- Use pcall to catch errors if this happens in a fast event context
            local ok, env_key = pcall(function() return vim.env[config.gemini.env_var_name] end)
            if ok and env_key and env_key ~= "" then
                api_key_cache = env_key
                return env_key
            end
        end
        
        -- Then try from a local config file
        if config.gemini.key_source == "config_file" then
            local config_path = config.gemini.config_path
            local ok, config_data = pcall(dofile, config_path)
            if ok and config_data and config_data.gemini_api_key and config_data.gemini_api_key ~= "" then
                api_key_cache = config_data.gemini_api_key
                return config_data.gemini_api_key
            end
        end
        
        -- Finally try from a secrets file in data directory
        if config.gemini.key_source == "data_file" then
            local secrets_path = config.gemini.data_path
            local ok, secrets = pcall(dofile, secrets_path)
            if ok and secrets and secrets.gemini_api_key and secrets.gemini_api_key ~= "" then
                api_key_cache = secrets.gemini_api_key
                return secrets.gemini_api_key
            end
        end
    end
    
    -- For OpenAI API
    if config.provider == "openai" then
        -- First try environment variable
        if config.openai.key_source == "env" then
            -- Use pcall to catch errors if this happens in a fast event context
            local ok, env_key = pcall(function() return vim.env[config.openai.env_var_name] end)
            if ok and env_key and env_key ~= "" then
                api_key_cache = env_key
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
        vim.notify("Empty response received from API", vim.log.levels.ERROR)
        return "No explanation available: Empty response"
    end
    
    -- Log raw response for debugging - include the full response for now
    vim.notify("Raw API response: " .. response, vim.log.levels.DEBUG)
    
    -- Check for common API error patterns
    if response:match('"error"') then
        -- Log the full response for debugging
        vim.notify("API Error detected in response", vim.log.levels.ERROR)
        
        local error_message = "API Error: "
        
        -- Try to extract specific error message
        local error_match = response:match('"message":%s*"([^"]+)"')
        if error_match then
            error_message = error_message .. error_match
            vim.notify("Extracted error message: " .. error_match, vim.log.levels.ERROR)
        else
            error_message = error_message .. "Unknown error occurred"
            vim.notify("Could not extract specific error message", vim.log.levels.ERROR)
        end
        
        return error_message
    end
    
    -- Try to parse the JSON response
    local ok, parsed = pcall(vim.fn.json_decode, response)
    if not ok or not parsed then
        vim.notify("Failed to parse JSON response: " .. response, vim.log.levels.ERROR)
        return "Failed to parse response from AI service"
    end
    
    -- Extract the text content based on provider
    local content = ""
    
    if parent.config.api.provider == "gemini" then
        vim.notify("Parsing Gemini API response: " .. vim.inspect(parsed), vim.log.levels.DEBUG)
        
        if parsed.candidates and parsed.candidates[1] and 
           parsed.candidates[1].content and 
           parsed.candidates[1].content.parts then
            for _, part in ipairs(parsed.candidates[1].content.parts) do
                if part.text then
                    content = content .. part.text
                    vim.notify("Extracted text content: " .. part.text:sub(1, 100), vim.log.levels.DEBUG)
                end
            end
            vim.notify("Successfully extracted Gemini API response content", vim.log.levels.DEBUG)
        else
            vim.notify("Invalid Gemini API response structure", vim.log.levels.WARN)
            if parsed.error then
                vim.notify("Gemini API error: " .. vim.inspect(parsed.error), vim.log.levels.ERROR)
                return "API Error: " .. (parsed.error.message or "Unknown error")
            end
        end
    elseif parent.config.api.provider == "openai" then
        if parsed.choices and parsed.choices[1] and parsed.choices[1].message and parsed.choices[1].message.content then
            content = parsed.choices[1].message.content
            vim.notify("Successfully extracted OpenAI response content", vim.log.levels.DEBUG)
        else
            vim.notify("Invalid OpenAI API response structure", vim.log.levels.WARN)
            if parsed.error then
                vim.notify("OpenAI API error: " .. vim.inspect(parsed.error), vim.log.levels.ERROR)
                return "API Error: " .. (parsed.error.message or "Unknown error")
            end
        end
    end
    
    if content == "" then
        vim.notify("No content found in response: " .. vim.inspect(parsed), vim.log.levels.WARN)
        return "No explanation found in response. Check console logs for details."
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
        vim.notify("Using Gemini API endpoint: " .. API_ENDPOINT, vim.log.levels.DEBUG)
    elseif config.provider == "openai" then
        API_ENDPOINT = config.openai.endpoint
        vim.notify("Using OpenAI API endpoint: " .. API_ENDPOINT, vim.log.levels.DEBUG)
    end
    
    -- Check if API key is available
    if API_KEY == "" then
        callback("No API key found. Please set an API key through environment variables or configuration files.")
        vim.notify("Missing API key. See documentation for setup instructions.", vim.log.levels.ERROR)
        return
    else
        -- Log partial key for debugging (showing only first few characters for security)
        local masked_key = API_KEY:sub(1, 6) .. "..." .. API_KEY:sub(-4)
        vim.notify("Using API key (masked): " .. masked_key, vim.log.levels.DEBUG)
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
    vim.notify("Using temp file for response: " .. temp_file, vim.log.levels.DEBUG)
    
    -- Log the prompt (truncated for privacy/brevity)
    local truncated_prompt = prompt:sub(1, 50) .. (prompt:len() > 50 and "..." or "")
    vim.notify("Sending prompt (truncated): " .. truncated_prompt, vim.log.levels.DEBUG)
    
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
        
        -- Log the request body for debugging
        vim.notify("Gemini request body: " .. request_body, vim.log.levels.DEBUG)
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
        
        -- Also try a direct curl command similar to our working example
        vim.notify("Executing curl for Gemini API", vim.log.levels.DEBUG)
        
        -- Create a special test command for the API output
        local testcmd = string.format(
            "curl -s -X POST '%s?key=%s' " ..
            "-H 'Content-Type: application/json' " ..
            "-d '%s'",
            API_ENDPOINT,
            API_KEY,
            request_body:gsub("'", "\\''") -- Escape single quotes
        )
        vim.notify("Full curl command (sanitized): " .. testcmd:gsub(API_KEY, "***KEY***"), vim.log.levels.DEBUG)
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
    -- Format the prompt differently based on learning focus
    local formatted_prompt = ""
    
    if parent.config.languages.learning_focus == "english" then
        -- Format the message to get a structured response for English vocabulary
        formatted_prompt = string.format([[
I'm a native Spanish speaker learning English and I need a detailed explanation of this English word/phrase: %s

Please respond with this exact format:
EXPLANATION:
[Clear definition of the word/phrase]

PRONUNCIATION:
[IPA pronunciation]

EXAMPLES:
1. [First example sentence showing usage in context]
2. [Second example with perhaps a different context or meaning]
3. [Third example showing common usage or an idiom if applicable]

GRAMMAR AND USAGE:
- Word type: [noun/verb/adjective/etc. and any irregular forms]
- Register: [formal/informal/slang/technical]
- Collocations: [words commonly used with this term]
- Similar words: [synonyms and their subtle differences]

SPANISH CONNECTION:
[Brief note about Spanish equivalents or false friends]
]], text)
    else
        -- Default explanation format
        formatted_prompt = string.format([[
I'm learning English and I need help understanding the following word or phrase: %s

Please respond with this exact format:
EXPLANATION:
[Clear definition of the word/phrase]

PRONUNCIATION:
[IPA pronunciation]

EXAMPLES:
1. [First example sentence showing usage]
2. [Second example with perhaps a different context]
3. [Third example showing common usage]

NOTES:
- Related terms: [similar words or synonyms]
- Origin: [brief etymology if relevant]
- Common mistakes: [how people often misuse this term, if applicable]
]], text)
    end
    
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
    -- Customize prompt based on language direction
    local formatted_prompt = ""
    
    -- Check if we're translating from Spanish to English (for language learning)
    if parent.config.languages.source == "es" and target_language == "en" then
        formatted_prompt = string.format([[
Translate the following Spanish text into English:

"%s"

Please respond with this exact format:
TRANSLATION:
[Your translation]

PRONUNCIATION GUIDE:
[Include the International Phonetic Alphabet (IPA) pronunciation for the English translation]

NOTES:
- Usage context: How and when this phrase/word is commonly used in English
- Register: Is this formal, informal, slang, technical, etc.
- Collocations: Common word combinations with this term
- Similar expressions: Related phrases or synonyms in English
]], text)
    
    -- Check if we're translating from English to Spanish (for understanding)
    elseif parent.config.languages.source == "en" and target_language == "es" then
        formatted_prompt = string.format([[
Translate the following English text into Spanish:

"%s"

Please respond with this exact format:
TRANSLATION:
[Your translation]

NOTES:
- Any cultural context important for understanding
- Regional variations if relevant
]], text)
    
    -- Default format for other language combinations
    else
        formatted_prompt = string.format([[
Translate the following text from %s into %s:

"%s"

Please respond with this exact format:
TRANSLATION:
[Your translation]

PRONUNCIATION GUIDE:
[Brief pronunciation help using International Phonetic Alphabet (IPA)]

NOTES:
- Usage context and common expressions
- Any cultural context important for understanding
]], parent.config.languages.source, target_language, text)
    end
    
    -- Show a notification that we're requesting
    vim.notify("Translating to " .. target_language .. ": " .. text, vim.log.levels.INFO)
    
    -- First try the standard API method
    make_api_request(formatted_prompt, function(response)
        -- Add more detailed logging for debugging
        vim.notify("Received API response of length: " .. #response, vim.log.levels.DEBUG)
        
        -- Check if response indicates an error
        if response:match("Failed to") or response:match("API Error") or response:match("failed with exit code") then
            -- Log the error response for debugging
            vim.notify("Translation API error, trying direct method as fallback", vim.log.levels.WARN)
            
            -- Use vim.schedule to ensure safety when using direct method
            vim.schedule(function()
                -- Try the direct method as a fallback
                M.direct_test_translation(text, target_language, function(direct_result)
                    callback(direct_result)
                end)
            end)
        else
            -- Log success but with truncated response for brevity
            local truncated = response:sub(1, 100) .. (response:len() > 100 and "..." or "")
            vim.notify("Translation successful: " .. truncated, vim.log.levels.DEBUG)
            callback(response)
        end
    end)
end

-- Test the API connection
function M.test_connection(silent)
    silent = silent or false
    local test_query = "Hello, this is a test query to verify API connectivity."
    
    -- Use vim.schedule to ensure we're in a safe context
    vim.schedule(function()
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
    end)
end

-- Function to directly test translation with an optimized curl command
function M.direct_test_translation(text, target_language, callback)
    -- Use vim.schedule to ensure we're not in a fast event context
    vim.schedule(function()
        -- Try to get API key from cache first
        local API_KEY = get_api_key()
        if API_KEY == "" then
            callback("No API key found")
            return
        end
        
        -- Customize prompt based on language direction
        local formatted_prompt = ""
        
        -- Check if we're translating from Spanish to English (for language learning)
        if parent.config.languages.source == "es" and target_language == "en" then
            formatted_prompt = string.format([[
Translate the following Spanish text into English:

"%s"

Please respond with this exact format:
TRANSLATION:
[Your translation]

PRONUNCIATION GUIDE:
[Include the International Phonetic Alphabet (IPA) pronunciation for the English translation]

NOTES:
- Usage context: How and when this phrase/word is commonly used in English
- Register: Is this formal, informal, slang, technical, etc.
- Collocations: Common word combinations with this term
- Similar expressions: Related phrases or synonyms in English
]], text)
        
        -- Check if we're translating from English to Spanish (for understanding)
        elseif parent.config.languages.source == "en" and target_language == "es" then
            formatted_prompt = string.format([[
Translate the following English text into Spanish:

"%s"

Please respond with this exact format:
TRANSLATION:
[Your translation]

NOTES:
- Any cultural context important for understanding
- Regional variations if relevant
]], text)
        
        -- Default format for other language combinations
        else
            formatted_prompt = string.format([[
Translate the following text from %s into %s:

"%s"

Please respond with this exact format:
TRANSLATION:
[Your translation]

PRONUNCIATION GUIDE:
[Brief pronunciation help using International Phonetic Alphabet (IPA)]

NOTES:
- Usage context and common expressions
- Any cultural context important for understanding
]], parent.config.languages.source, target_language, text)
        end
        
        -- Create request body JSON
        local request_body = vim.fn.json_encode({
            contents = {
                {
                    parts = {
                        { text = formatted_prompt }
                    }
                }
            }
        })
        
        -- Create a temp file for the response
        local temp_file = vim.fn.tempname()
        
        -- Build the curl command
        local cmd = string.format(
            "curl -s -X POST 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=%s' -H 'Content-Type: application/json' -d '%s' > %s",
            API_KEY,
            request_body:gsub("'", "\\'"),
            temp_file
        )
        
        -- Log the command for debugging (with API key masked)
        local masked_cmd = cmd:gsub(API_KEY, "***API_KEY***")
        vim.notify("Direct test command: " .. masked_cmd, vim.log.levels.DEBUG)
        
        -- Run the curl command directly
        vim.fn.system(cmd)
        
        -- Read the response
        local file = io.open(temp_file, "r")
        if not file then
            callback("Failed to read response file")
            return
        end
        
        local response = file:read("*all")
        file:close()
        os.remove(temp_file)
        
        -- Try to parse the response
        local ok, parsed = pcall(vim.fn.json_decode, response)
        if not ok or not parsed then
            callback("Failed to parse response: " .. response)
            return
        end
        
        -- Extract the translation
        local translation = ""
        if parsed.candidates and parsed.candidates[1] and 
           parsed.candidates[1].content and 
           parsed.candidates[1].content.parts then
            for _, part in ipairs(parsed.candidates[1].content.parts) do
                if part.text then
                    translation = translation .. part.text
                end
            end
        end
        
        if translation == "" then
            callback("No translation found in response: " .. response)
        else
            callback(translation)
        end
    end)
end

-- Update the commands module to use this direct test
local function update_commands_module()
    local ok, commands = pcall(require, "languages-assistant.commands")
    if ok then
        -- Don't do anything here - we'll update the commands separately
    end
end

-- Try to update immediately
update_commands_module()

return M
