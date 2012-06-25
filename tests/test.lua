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
  {[0]=17,21,27},
  {[-6]=17,21,27},
  {[-1]=4,1,nil,3},
  {[1]=17,[99999999]=21},
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

-- Integer tests

printf("Integer tests ")

local nb_test = function(n,sz)
  offset,res = mp.unpack(mp.pack(n))
  assert(offset,"decoding failed")
  if not res == n then
    assert(false,string.format("wrong value %g, expected %g",res,n))
  end
  assert(offset == sz,string.format(
    "wrong size %d for number %g (expected %d)",
    offset,n,sz
  ))
end

printf(".")
for n=0,127 do -- positive fixnum
  nb_test(n,1)
end

printf(".")
for n=128,255 do -- uint8
  nb_test(n,2)
end

printf(".")
for n=256,65535 do -- uint16
  nb_test(n,3)
end

 -- uint32
printf(".")
for n=65536,65536+100 do
  nb_test(n,5)
end
for n=4294967295-100,4294967295 do
  nb_test(n,5)
end

printf(".")
for n=4294967296,4294967296+100 do -- uint64
  nb_test(n,9)
end

printf(".")
for n=-1,-32,-1 do -- negative fixnum
  nb_test(n,1)
end

printf(".")
for n=-33,-128,-1 do -- int8
  nb_test(n,2)
end

printf(".")
for n=-129,-32768,-1 do -- int16
  nb_test(n,3)
end

-- int32
printf(".")
for n=-32769,-32769-100,-1 do
  nb_test(n,5)
end
for n=-2147483648+100,-2147483648,-1 do
  nb_test(n,5)
end

printf(".")
for n=-2147483649,-2147483649-100,-1 do -- int64
  nb_test(n,9)
end

print(" OK")

-- Floating point tests
printf("Floating point tests ")

printf(".") -- default is double
for i=1,100 do
  local n = math.random()*200-100
  nb_test(n,9)
end

printf(".")
mp.set_fp_type("float")
for i=1,100 do
  local n = math.random()*200-100
  nb_test(n,5)
end

printf(".")
mp.set_fp_type("double")
for i=1,100 do
  local n = math.random()*200-100
  nb_test(n,9)
end

print(" OK")

-- Raw tests

printf("Raw tests ")

local rand_raw = function(len)
  local t = {}
  for i=1,len do t[i] = string.char(math.random(0,255)) end
  return table.concat(t)
end

local raw_test = function(raw,overhead)
  offset,res = mp.unpack(mp.pack(raw))
  assert(offset,"decoding failed")
  if not res == raw then
    assert(false,string.format("wrong raw (len %d - %d)",#res,#raw))
  end
  assert(offset-#raw == overhead,string.format(
    "wrong overhead %d for #raw %d (expected %d)",
    offset-#raw,#raw,overhead
  ))
end

printf(".")
for n=0,31 do -- fixraw
  raw_test(rand_raw(n),1)
end

-- raw16
printf(".")
for n=32,32+100 do
  raw_test(rand_raw(n),3)
end
for n=65535-100,65535 do
  raw_test(rand_raw(n),3)
end

 -- raw32
printf(".")
for n=65536,65536+100 do
  raw_test(rand_raw(n),5)
end
-- below: too slow
-- for n=4294967295-100,4294967295 do
--   raw_test(rand_raw(n),5)
-- end

print(" OK")

-- Table tests

printf("Table tests ")
print(" TODO")

-- Floating point tests
printf("Map tests ")
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
