local function get_id_embed(username)
    local httpc = http.new()
    local request_opts = {
        headers = totally_human_headers,
    }

    if config.proxies["user_page"] then
        request_opts.proxy_opts = {
            https_proxy = config.proxies["user_page"],
        }
    end

    local request, err = httpc:request_uri("https://www.instagram.com/" .. username .. "/embed/", request_opts)

    local user_match = ngx.re.match(request.body, [[contextJSON":"([^"\\]*(?:\\.[^"\\]*)*)"]])

    if user_match and user_match[1] then
        local escaped = user_match[1]
        local unescaped = escaped:gsub('\\"', '"'):gsub("\\\\", "\\"):gsub("\\n", "\n"):gsub("\\t", "\t")
        local decoded = json.decode(unescaped)
        return decoded.context
    end
end
