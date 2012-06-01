# luajit-msgpack-pure

## Presentation

This is yet another implementation of MessagePack for LuaJIT.
However, unlike [luajit-msgpack](https://github.com/catwell/luajit-msgpack),
luajit-msgpack-pure does not depend on the MessagePack C library.
Everything is re-implemented in LuaJIT code (using the FFI but only to
manipulate data structures).

## TODO

- Missing datatype tests
- Comparison tests vs. luajit-msgpack

## Usage

See tests/test.lua for usage.
