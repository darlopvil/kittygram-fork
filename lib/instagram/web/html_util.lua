local json = require("cjson")

local function extract_preloaders(data)
    local preloaders = {}
    if data["CometPlatformRootClient"] then
        for _, item in ipairs(data["CometPlatformRootClient"]) do
            if item[1] and item[1].expectedPreloaders and item[1].expectedPreloaders ~= json.null then
                for _, preloader in ipairs(item[1].expectedPreloaders) do
                    table.insert(preloaders, {
                        id = preloader.preloaderID,
                        query_name = preloader.queryName
                    })
                end
            end
        end
    end

    local preloaded_data = {}
    if data["RelayPrefetchedStreamCache"] then
        for _, item in ipairs(data["RelayPrefetchedStreamCache"]) do
            local preloader_id = item[1]
            local preloader_data = item[2]

            for _, preloader in ipairs(preloaders) do
                if preloader.id == preloader_id then
                    preloaded_data[preloader.query_name] = preloader_data.__bbox or preloader_data
                end
            end
        end
    end

    return preloaded_data
end

-- this function filters initial html data into what's actually needed.
local function pare_initial_data(data)
    local filtered = {}
    if data["LSD"] then
        for _, item in ipairs(data["LSD"]) do
            if item.token and type(item.token) == "string" then
                filtered.lsd = item.token
            end
        end
    end

    if data["SiteData"] then
        for _, item in ipairs(data["SiteData"]) do
            -- if these fields don't exist, they'll be nil, so they shouldn't show in the table
            filtered.hsi = item.hsi
            filtered.comet_env = item.comet_env
            filtered.haste_session = item.haste_session
            filtered.spin_b = item.__spin_b
            filtered.spin_r = item.__spin_r
            filtered.spin_t = item.__spin_t
            filtered.revision = item.client_revision
        end
    end

    if data["WebConnectionClassServerGuess"] then
        for _, item in ipairs(data["WebConnectionClassServerGuess"]) do
            if item.connectionClass then
                filtered.connection_class = item.connectionClass
            end
        end
    end

    if data["InstagramSecurityConfig"] then
        for _, item in ipairs(data["InstagramSecurityConfig"]) do
            if item.csrf_token then
                filtered.csrf_token = item.csrf_token
            end
        end
    end

    if data["RelayAPIConfigDefaults"] then
        for _, item in ipairs(data["RelayAPIConfigDefaults"]) do
            filtered.graphql_uri = item.graphql_uri
            filtered.actor_id = item.actorID
        end
    end

    if data["WebBloksVersioningID"] then
        for _, item in ipairs(data["WebBloksVersioningID"]) do
            filtered.bloks_version_id = item.versioningID
        end
    end

    if data["CometPlatformRootClient"] then
        for _, item in ipairs(data["CometPlatformRootClient"]) do
            if item[1] and item[1].initialRouteInfo and item[1].initialRouteInfo ~= ngx.null and item[1].initialRouteInfo.route then
                local route = item[1].initialRouteInfo.route
                if route ~= ngx.null then
                    if route.rootView and route.rootView ~= ngx.null then
                        if route.rootView.props and route.rootView.props ~= ngx.null then
                            filtered.user_id = route.rootView.props.id
                        end
                    end
                    filtered.canonical_route_name = route.canonicalRouteName
                end
            end
        end
    end

    local preloaders = extract_preloaders(data)
    filtered.preloaders = preloaders
    return filtered
end

return {
    pare_initial_data = pare_initial_data
}
