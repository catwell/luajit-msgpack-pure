local ffi = require "ffi"

-- standard cdefs

ffi.cdef[[
  void free(void *ptr);
  void *realloc(void *ptr, size_t size);
  void *malloc(size_t size);
]]

-- cache bitops
local bor,band,rshift = bit.bor,bit.band,bit.rshift

local MSGPACK_SBUFFER_INIT_SIZE = 8192

local buffer = {} -- module buffer - change this?

local sbuffer_init = function(self)
  self.size = 0
  self.alloc = MSGPACK_SBUFFER_INIT_SIZE
  self.data = ffi.cast("char *",ffi.C.malloc(MSGPACK_SBUFFER_INIT_SIZE))
end

local sbuffer_destroy = function(self)
  ffi.C.free(buffer.data)
end

local sbuffer_realloc = function(self,len)
  if self.alloc - self.size < len then
    local nsize = self.alloc * 2
    while nsize < self.alloc + len do nsize = nsize * 2 end
    self.data = ffi.cast("char *",ffi.C.realloc(self.data,nsize))
    self.alloc = nsize
  end
end

local sbuffer_append_str = function(self,buf,len)
  sbuffer_realloc(self,len)
  ffi.copy(self.data+self.size,buf,len)
  self.size = self.size + len
end

local sbuffer_append_tbl = function(self,t)
  local len = #t
  sbuffer_realloc(self,len)
  local p = self.data + self.size -1
  for i=1,len do p[i] = t[i] end
  self.size = self.size + len
end

local sbuffer_append_intx = function(self,n,x,h)
  local t = {h}
  for i=x-8,0,-8 do t[#t+1] = band(rshift(n,i),0xff) end
  sbuffer_append_tbl(self,t)
end

--- packers

local packers = {}

packers.dynamic = function(data)
  return packers[type(data)](data)
end

packers["nil"] = function(data)
  sbuffer_append_tbl(buffer,{0xc0})
end

packers.boolean = function(data)
  if data then -- pack true
    sbuffer_append_tbl(buffer,{0xc3})
  else -- pack false
    sbuffer_append_tbl(buffer,{0xc2})
  end
end

packers.number = function(n)
  if math.floor(n) == n then -- integer
    if n >= 0 then -- positive integer
      if n < 128 then -- positive fixnum
        sbuffer_append_tbl(buffer,{n})
      elseif n < 256 then -- uint8
        sbuffer_append_tbl(buffer,{0xcc,n})
      elseif n < 65536 then -- uint16
        sbuffer_append_intx(buffer,n,16,0xcd)
      elseif n < 4294967296 then -- uint32
        sbuffer_append_intx(buffer,n,32,0xce)
      else -- uint64
        sbuffer_append_intx(buffer,n,64,0xcf)
      end
    else -- negative integer
      if n >= -32 then -- negative fixnum
        sbuffer_append_tbl(buffer,{bor(0xe0,n)})
      elseif n >= -128 then -- int8
        sbuffer_append_tbl(buffer,{0xd0,n})
      elseif n >= -32768 then -- int16
        sbuffer_append_intx(buffer,n,16,0xd1)
      elseif n >= -2147483648 then -- int32
        sbuffer_append_intx(buffer,n,32,0xd2)
      else -- int64
        sbuffer_append_intx(buffer,n,64,0xd3)
      end
    end
  else -- floating point
    local f = ffi.new("double[1]") -- TODO poss. to use floats instead
    f[0] = n
    local _b = ffi.cast("char *",f)
    local b
    if ffi.abi("le") then -- fix endianness
      b = ffi.new("char[8]")
      for i=0,7 do b[i] = _b[7-i] end
    else b = _b end
    sbuffer_append_tbl(buffer,{0xcb})
    sbuffer_append_str(buffer,b,8)
  end
end

packers.string = function(data)
  local n = #data
  if n < 32 then
    sbuffer_append_tbl(buffer,{bor(0xa0,n)})
  elseif n < 65536 then
    sbuffer_append_intx(buffer,n,16,0xda)
  elseif n < 4294967296 then
    sbuffer_append_intx(buffer,n,32,0xdb)
  else
    error("overflow")
  end
  sbuffer_append_str(buffer,data,n)
end

packers["function"] = function(data)
  error("unimplemented")
end

packers.userdata = function(data)
  error("unimplemented")
end

packers.thread = function(data)
  error("unimplemented")
end

packers.table = function(data)
  local is_map,ndata,nmax = false,0,0
  for k,_ in pairs(data) do
    if type(k) == "number" then
      if k > nmax then nmax = k end
    else is_map = true end
    ndata = ndata+1
  end
  if is_map then -- pack as map
    if ndata < 16 then
      sbuffer_append_tbl(buffer,{bor(0x80,ndata)})
    elseif ndata < 65536 then
      sbuffer_append_intx(buffer,ndata,16,0xde)
    elseif ndata < 4294967296 then
      sbuffer_append_intx(buffer,ndata,32,0xdf)
    else
      error("overflow")
    end
    for k,v in pairs(data) do
      packers[type(k)](k)
      packers[type(v)](v)
    end
  else -- pack as array
    if nmax < 16 then
      sbuffer_append_tbl(buffer,{bor(0x90,nmax)})
    elseif nmax < 65536 then
      sbuffer_append_intx(buffer,nmax,16,0xdc)
    elseif nmax < 4294967296 then
      sbuffer_append_intx(buffer,nmax,32,0xdd)
    else
      error("overflow")
    end
    for i=1,nmax do packers[type(data[i])](data[i]) end
  end
end

-- Main functions

local up = require "luajit-msgpack" -- TODO remove

local ljp_pack = function(data)
  sbuffer_init(buffer)
  packers.dynamic(data)
  local s = ffi.string(buffer.data,buffer.size)
  sbuffer_destroy(buffer)
  return s
end

local ljp_unpack = function(s,offset)
  -- TODO implement me for real
  local offset,data = up.unpack(s,offset)
  return offset,data
end

return {
  pack = ljp_pack,
  unpack = ljp_unpack,
}
