local util = require("lapis.util")
local json = require("cjson")

local function check_nested_field(tbl, ...)
    local current = tbl
    for _, key in ipairs({...}) do
        if type(current) ~= "table" then
            return nil
        end
        current = current[key]
    end
    return current
end

local proxy_url = function(url)
    return "/mediaproxy?url=" .. util.escape(url)
end

local create_error = {
    not_found = function(args)
        return {
            has_errors = true,
            error_type = "not_found",
            error_info = {
                message = args.message or "The requested content was not found.",
                blob = json.encode(args.blob)
            }
        }
    end,
    ratelimited = function(args)
        return {
            has_errors = true,
            error_type = "ratelimited",
            error_info = {
                message = args.message or "This instance may be rate-limited. Try again in a minute.",
                blob = json.encode(args.blob)
            }
        }
    end,
    blocked = function(args)
        return {
            has_errors = true,
            error_type = "blocked",
            error_info = {
                message = args.message or "This instance has been blocked from accessing that content. This may be permanent",
                blob = json.encode(args.blob)
            }
        }
    end,
    network_error = function(args)
        return {
            has_errors = true,
            error_type = "network_error",
            error_info = {
                message = args.message or "A network error occurred when trying to fetch this item. This is likely temporary.",
                blob = json.encode(args.blob)
            }
        }
    end,
    null_content = function(args)
        return {
            has_errors = true,
            error_type = "null_content",
            error_info = {
                message = args.message or "This post is unavailable.",
                blob = json.encode(args.blob)
            }
        }
    end,
    unknown = function(args)
        return {
            has_errors = true,
            error_type = "unknown",
            error_info = {
                message = args.message or "An unknown error occurred.",
                blob = json.encode(args.blob)
            }
        }
    end
}

return {
    check_nested_field = check_nested_field,
    proxy_url = proxy_url,
    create_error = create_error
}
