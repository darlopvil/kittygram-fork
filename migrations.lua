local schema = require("lapis.db.schema")
local types = schema.types

return {
    [1] = function()
    schema.create_table("user_ids", {
        { "id", types.id },
        { "username", types.varchar },
        { "user_id", types.varchar },
        "PRIMARY KEY (username)"
    })
    end,
    [1779735501] = function()
    schema.create_table("api_codes", {
        { "id", types.id },
        { "code", types.varchar },
        { "is_used", types.integer{ default = 0 } },
        { "created_at", types.integer },
    })
    end
}





