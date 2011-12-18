# luajit-msgpack-pure

## Presentation

This is yet another implementation of MessagePack for LuaJIT.
However, unlike [luajit-msgpack](https://github.com/catwell/luajit-msgpack),
luajit-msgpack-pure does not depend on the MessagePack C library.
Everything is re-implemented in LuaJIT code (using the FFI but only to
manipulate data structures).

## Status

Packing is implemented, unpacking is proxied to luajit-msgpack for now.
This means you probably don't want to use this in your projects yet.

I will not care about speed until it has the same coverage as luajit-msgpack.

## Usage

See tests/test.lua for usage.
