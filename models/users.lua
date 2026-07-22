local Model = require("lapis.db.model").Model
local Users = Model:extend("user_ids", {primary_key = "username"})

local function save_user(user_dict)
    if not user_dict.username or not user_dict.id then
        ngx.log(ngx.ERR, "Error saving user: Required field not present.")
        return nil
    end

    local verification_num = 0
    if user_dict.is_verified then
        verification_num = 1
    end

    local user = Users:find(string.lower(user_dict.username))

    if user == nil then
        local new_user = Users:create({
            username = string.lower(user_dict.username),
            user_id = user_dict.id,
            profile_picture = user_dict.profile_pic_url,
            is_verified = verification_num
        })
    else
        user:update({
            username = string.lower(user_dict.username),
            user_id = user_dict.id,
            profile_picture = user_dict.profile_pic_url,
            is_verified = verification_num
        })
    end
end

local function get_user(username)
    local user = Users:find(string.lower(username))
    local verification_status
    if user.is_verified == 1 then
        verification_status = true
    else
        verification_status = false
    end

    if user then
        return {
            username = user.username,
            id = user.user_id,
            is_verified = verification_status
        }
    end
end

return {save_user = save_user, get_user = get_user}
