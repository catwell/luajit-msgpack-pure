#!/usr/bin/env luajit

local ffi = require "ffi"

local display = function(m,x)
  local _t = type(x)
  io.stdout:write(string.format("\n%s: %s ",m,_t))
  if _t == "table" then pretty.dump(x) else print(x) end
end

local printf = function(p,...)
  io.stdout:write(string.format(p,...)); io.stdout:flush()
end

local mp = require "luajit-msgpack-pure"

local offset,res
local float_val = 0xffff000000000

local nb_test2 = function(n,sz)
  offset,res = mp.unpack(mp.pack(n))
  assert(offset,"decoding failed")
  if res ~= n then
    assert(false,string.format("wrong value %g, expected %g",res,n))
  end
  assert(offset == sz,string.format(
    "wrong size %d for number %g (expected %d)",
    offset,n,sz
  ))
end

printf(".")
for _=0,1000 do
  for n=0,50 do
    local v = float_val + n
    nb_test2(float_val + n, 9)
  end
end
