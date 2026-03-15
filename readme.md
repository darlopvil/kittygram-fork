# Kittygram

Kittygram is an anonymous, privacy-friendly, lightweight, and open-source Instagram frontend inspired by [nitter](https://github.com/zedeus/nitter)
.
It offers a clean, fast way to browse Instagram without the usual clutter or tracking.

## Why

The official Instagram web interface is heavy on JavaScript, slow to load, and filled with pop-ups.
Kittygram avoids all of that by serving fully prerendered pages, making it faster and easier to use.  

Kittygram also helps you avoid the heavy tracking instagram does, as all requests are handled by kittygram.   

### Limitations
- As of now, only the first ~20 comments on a post can be fetched.
- Instagram aggresively rate-limits requests coming from servers, which can make running a public instance difficult.  


## Instances

|URL |Description|
|-----|-----------|
|https://kittygr.am | An instance of kittygram operated by [FSKY](https://fsky.io) |
|https://kittygram.irelephant.net | An instance of kittygram run by its creator |




## Installation

> [!NOTE]
> I highly recommend you install kittygram using docker. Luarocks can be finicky a lot of the time.  

### Method 1: Docker

1. Install [docker](https://docs.docker.com/engine/install/).  
2. Clone the project:
```shell
git clone https://codeberg.org/irelephant/kittygram.git
```
3. Move to the projects directory:
```shell
cd kittygram
```
4. Start the container
```shell
sudo docker compose up
```

# Method 2: Running from scratch
1. Clone the project:
```shell
git clone https://codeberg.org/irelephant/kittygram.git
```
2. Install [openresty](https://openresty.org/en/installation.html)
3. Install [redis](https://redis.io/docs/latest/operate/oss_and_stack/install/archive/install-redis/) or [valkey](https://valkey.io/topics/installation/)
4. Install [luarocks](https://luarocks.org/) (likely in your distro's package manager), and run:
```shell
luarocks init --lua-version=5.1 --lua-versions=5.1
CC="gcc -std=gnu99" luarocks build
```
5. Run `lapis migrate`
6. Run `lapis serve production` to run the project.

   
## Contact
Feel free to join the [matrix room](https://matrix.to/#/#kittygram:private.coffee), or email me at [irelephant@disroot.org](mailto:irelephant@disroot.org)

--------
Kittygram is licensed under the AGPL-3.0.  

Icon made by [nulla](https://codeberg.org/nulla).

