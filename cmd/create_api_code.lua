
local api_model = require("models.api_codes")

function create_code()
    local code = api_model.create_code()
    return code
end


local code = create_code()
print("Code created:\t" .. code.code)
