FROM docker.io/openresty/openresty:alpine-fat AS builder

RUN apk add --no-cache openssl-dev sqlite-dev

RUN /usr/local/openresty/luajit/bin/luarocks install lapis && \
    /usr/local/openresty/luajit/bin/luarocks install lua-resty-http && \
    /usr/local/openresty/luajit/bin/luarocks install lua-cjson && \
    /usr/local/openresty/luajit/bin/luarocks install htmlparser && \
    /usr/local/openresty/luajit/bin/luarocks install lua-resty-openssl && \
    /usr/local/openresty/luajit/bin/luarocks install lua-resty-redis && \
    /usr/local/openresty/luajit/bin/luarocks install lapis-redis && \
    /usr/local/openresty/luajit/bin/luarocks install lsqlite3 && \
    /usr/local/openresty/luajit/bin/luarocks install luautf8

RUN echo 'return require("lua-utf8")' > /usr/local/openresty/luajit/share/lua/5.1/utf8.lua

FROM docker.io/openresty/openresty:alpine

WORKDIR /app

RUN apk add --no-cache openssl sqlite sqlite-libs

COPY --from=builder /usr/local/openresty/luajit/share/lua/ /usr/local/openresty/luajit/share/lua/
COPY --from=builder /usr/local/openresty/luajit/lib/ /usr/local/openresty/luajit/lib/
COPY --from=builder /usr/local/openresty/luajit/bin/lapis /usr/local/openresty/luajit/bin/lapis

COPY . .

COPY config.example.lua config.lua
COPY nginx.example.conf nginx.conf

RUN /usr/local/openresty/luajit/bin/lapis migrate
RUN chown -R nobody:nobody /app

EXPOSE 80

CMD ["/usr/local/openresty/luajit/bin/lapis", "serve", "docker"]
