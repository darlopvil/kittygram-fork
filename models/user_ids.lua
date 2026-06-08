local Model = require("lapis.db.model").Model
local Users = Model:extend("user_ids", {primary_key = "username"})

local function save_user_id(username, user_id)
    local user = Users:find(string.lower(username))
    if user == nil then
        local new_user = Users:create({username = string.lower(username), user_id = user_id})
    end
end

local function get_user_id(username)
    local user = Users:find(string.lower(username))
    if user then
        return user.user_id
    else
        return nil
    end
end

return {save_user_id = save_user_id, get_user_id = get_user_id}
