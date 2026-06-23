package = "kittygram"
version = "dev-1"
source = {
   url = "git+ssh://git@codeberg.org/irelephant/kittygram.git"
}
description = {
   homepage = "https://kittygram.irelephant.net",
   license = "AGPL-3.0"
}
dependencies = {
   "lua = 5.1",
   "lapis",
   "lua-resty-http",
   "lua-resty-openssl",
   "lua-resty-redis",
   "lapis-redis",
   "htmlparser",
   "lua-cjson",
   "lsqlite3",
   "luautf8"
}
build = {
   type = "none"
}
