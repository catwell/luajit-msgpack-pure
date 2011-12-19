#!/usr/bin/env luajit

local pathx = require "pl.path"
local pretty = require "pl.pretty"
local tablex = require "pl.tablex"
require "pl.strict"

local mp = require "luajit-msgpack-pure"

local display = function(m,x)
  local _t = type(x)
  io.stdout:write(string.format("\n%s: %s ",m,_t))
  if _t == "table" then pretty.dump(x) else print(x) end
end

local printf = function(p,...)
  io.stdout:write(string.format(p,...)); io.stdout:flush()
end

local msgpack_cases = {
  false,true,nil,0,0,0,0,0,0,0,0,0,-1,-1,-1,-1,-1,127,127,255,65535,
  4294967295,-32,-32,-128,-32768,-2147483648,0.0,-0.0,1.0,-1.0,
  "a","a","a","","","",
  {0},{0},{0},{},{},{},{},{},{},{a=97},{a=97},{a=97},{{}},{{"a"}},
}

local data = {
  true,
  false,
  42,
  -42,
  0.79,
  "Hello world!",
  {},
  {true,false,42,-42,0.79,"Hello","World!"},
  {{"multi","level",{"lists","used",45,{{"trees"}}},"work",{}},"too"},
  {foo="bar",spam="eggs"},
  {nested={maps={"work","too"}}},
  {"we","can",{"mix","integer"},{keys="and"},{2,{maps="as well"}}},
  msgpack_cases,
}

local offset,res

-- Custom tests
printf("Custom tests ")
for i=0,#data do -- 0 tests nil!
  printf(".")
  offset,res = mp.unpack(mp.pack(data[i]))
  assert(offset,"decoding failed")
  if not tablex.deepcompare(res,data[i]) then
    display("expected",data[i])
    display("found",res)
    assert(false,string.format("wrong value %d",i))
  end
end
print(" OK")

-- Number tests

printf("Number tests ")

local nb_test = function(n)
  offset,res = mp.unpack(mp.pack(n))
  assert(offset,"decoding failed")
  if not res == n then
    assert(false,string.format("wrong value %d, expected %d",res,n))
  end
end

printf(".")
for n=0,127 do -- positive fixnum
  nb_test(n)
end

printf(".")
for n=128,255 do -- uint8
  nb_test(n)
end

printf(".")
for n=255,65535 do -- uint16
  nb_test(n)
end

 -- uint32
printf(".")
for n=65536,65536+100 do
  nb_test(n)
end
for n=4294967295-100,4294967295 do
  nb_test(n)
end

printf(".")
for n=4294967296,4294967296+100 do -- uint64
  nb_test(n)
end

printf(".")
for n=-1,-32,-1 do -- negative fixnum
  nb_test(n)
end

printf(".")
for n=-33,-128,-1 do -- int8
  nb_test(n)
end

printf(".")
for n=-129,-32768,-1 do -- int16
  nb_test(n)
end

-- int32
printf(".")
for n=-32769,-32769-100,-1 do
  nb_test(n)
end
for n=-2147483648+100,-2147483648,-1 do
  nb_test(n)
end

printf(".")
for n=-2147483649,-2147483649-100,-1 do -- int64
  nb_test(n)
end

print(" OK")

-- String tests

printf("String tests ")
print(" TODO")

-- Table tests

printf("Table tests ")
print(" TODO")

-- From MessagePack test suite
local cases_dir = pathx.abspath(pathx.dirname(arg[0]))
local case_files = {
  standard = pathx.join(cases_dir,"cases.mpac"),
  compact = pathx.join(cases_dir,"cases_compact.mpac"),
}
local i,f,bindata,decoded
local ncases = #msgpack_cases
for case_name,case_file in pairs(case_files) do
  printf("MsgPack %s tests ",case_name)
  f = assert(io.open(case_file,'rb'))
  bindata = f:read("*all")
  f:close()
  offset,i = 0,0
  while true do
    i = i+1
    printf(".")
    offset,res = mp.unpack(bindata,offset)
    if not offset then break end
    if not tablex.deepcompare(res,msgpack_cases[i]) then
      display("expected",msgpack_cases[i])
      display("found",res)
      assert(false,string.format("wrong value %d",i))
    end
  end
  assert(
    i-1 == ncases,
    string.format("decoded %d values instead of %d",i-1,ncases)
  )
  print(" OK")
end
