local http = require("resty.http")
local html = require("htmlparser")
local json = require("cjson")
local helpers = require("lib.helpers")
local config = require("lapis.config").get()
local errors = require("lib.helpers").create_error

local totally_human_headers = {
    ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    ["Sec-Fetch-Mode"] = "navigate"
}



-- function to get an id from a user's profile page.
-- heavily ratelimited.
local function get_user_id(username)
    local httpc = http.new()

    local request_opts = {
        headers = totally_human_headers,
    }

    if config.proxies["user_page"] then
        request_opts.proxy_opts = {
            https_proxy = config.proxies["user_page"]
        }
    end

    local user_request, err = httpc:request_uri("https://www.instagram.com/" .. username .. "/", request_opts)

    if not user_request then
        ngx.log(ngx.ERR, "Request failed: " .. err)
    end

    if user_request.status == 429 then
        return errors.ratelimited{
            message = "Instagram returned 429 on profile page."
        }
    elseif user_request.status == 302 then
        return errors.blocked{
            message = "Kittygram has been blocked from accessing user pages. This means that private users and users without posts are currently unreachable."
        }
    else
        -- very fragile pattern, may break in future.
        local id = user_request.body:match([["profile_id"%s*:%s*"(%d+)"]])
        return id
    end
end
return get_user_id


