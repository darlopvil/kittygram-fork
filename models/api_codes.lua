local Model = require("lapis.db.model").Model
local encoding = require("lapis.util.encoding")
local ApiCodes = Model:extend("api_codes")

math.randomseed(os.time())

local function validate_code(code)
    local code = ApiCodes:find {
        code = code,
    }
    if not code then
        return false, "Code not found"
    else
        if code.is_used == 1 then
            return false, "Code already used."
        end
        return true
    end
end

local function mark_code_as_used(code)
    local code = ApiCodes:find {
        code = code,
    }

    if not code then
        return false, "failed to find code"
    end
    code:update {
        is_used = 1,
    }
    return true
end

local function create_code()
    local token = encoding.encode_base64(tostring(math.random()) .. ":" .. tostring(os.time()))
    local code = ApiCodes:create {
        code = token,
        created_at = os.time(),
    }
    return code
end

return { validate_code = validate_code, create_code = create_code, mark_code_as_used = mark_code_as_used }
