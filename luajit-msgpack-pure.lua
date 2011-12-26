local ffi = require "ffi"
local bit = require "bit"
local math = require "math"

-- standard cdefs

ffi.cdef[[
  void free(void *ptr);
  void *realloc(void *ptr, size_t size);
  void *malloc(size_t size);
]]

-- cache bitops
local bor,band,bxor,rshift = bit.bor,bit.band,bit.bxor,bit.rshift

-- shared ffi data
local t_buf = ffi.new("unsigned char[8]")
local t_buf2 = ffi.new("unsigned char[8]")

-- endianness

local LITTLE_ENDIAN = ffi.abi("le")
local rcopy = function(dst,src,len)
  local n = len-1
  for i=0,n do dst[i] = src[n-i] end
end

-- buffer

local MSGPACK_SBUFFER_INIT_SIZE = 8192

local buffer = {}

local sbuffer_init = function(self)
  self.size = 0
  self.alloc = MSGPACK_SBUFFER_INIT_SIZE
  self.data = ffi.cast("unsigned char *",ffi.C.malloc(MSGPACK_SBUFFER_INIT_SIZE))
end

local sbuffer_destroy = function(self)
  ffi.C.free(buffer.data)
end

local sbuffer_realloc = function(self,len)
  if self.alloc - self.size < len then
    local nsize = self.alloc * 2
    while nsize < self.alloc + len do nsize = nsize * 2 end
    self.data = ffi.cast("unsigned char *",ffi.C.realloc(self.data,nsize))
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

local sbuffer_append_intx
if LITTLE_ENDIAN then
  sbuffer_append_intx = function(self,n,x,h)
    local t = {h}
    for i=x-8,0,-8 do t[#t+1] = band(rshift(n,i),0xff) end
    sbuffer_append_tbl(self,t)
  end
else
  sbuffer_append_intx = function(self,n,x,h)
    local t = {h}
    for i=0,x-8,8 do t[#t+1] = band(rshift(n,i),0xff) end
    sbuffer_append_tbl(self,t)
  end
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
    -- TODO poss. to use floats instead
    if LITTLE_ENDIAN then
      ffi.cast("double *",t_buf2)[0] = n
      rcopy(t_buf,t_buf2,8)
    else
      ffi.cast("double *",t_buf)[0] = n
    end
    sbuffer_append_tbl(buffer,{0xcb})
    sbuffer_append_str(buffer,t_buf,8)
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

-- types decoding

local types_map = {
    [0xc0] = "nil",
    [0xc2] = "false",
    [0xc3] = "true",
    [0xca] = "float",
    [0xcb] = "double",
    [0xcc] = "uint8",
    [0xcd] = "uint16",
    [0xce] = "uint32",
    [0xcf] = "uint64",
    [0xd0] = "int8",
    [0xd1] = "int16",
    [0xd2] = "int32",
    [0xd3] = "int64",
    [0xda] = "raw16",
    [0xdb] = "raw32",
    [0xdc] = "array16",
    [0xdd] = "array32",
    [0xde] = "map16",
    [0xdf] = "map32",
  }

local type_for = function(n)
  if types_map[n] then return types_map[n]
  elseif n < 0xc0 then
    if n < 0x80 then return "fixnum_pos"
    elseif n < 0x90 then return "fixmap"
    elseif n < 0xa0 then return "fixarray"
    else return "fixraw" end
  elseif n > 0xdf then return "fixnum_neg"
  else return "undefined" end
end

local types_len_map = {
  uint16 = 2, uint32 = 4, uint64 = 8,
  int16 = 2, int32 = 4, int64 = 8,
  float = 4, double = 8,
}

--- unpackers

local unpackers = {}

local unpack_number
if LITTLE_ENDIAN then
  unpack_number = function(buf,offset,ntype,nlen)
    rcopy(t_buf,buf.data+offset+1,nlen)
    return tonumber(ffi.cast(ntype,t_buf)[0])
  end
else
  unpack_number = function(buf,offset,ntype,nlen)
    return tonumber(ffi.cast(ntype,buf.data+offset+1)[0])
  end
end

local unpacker_number = function(buf,offset)
  local obj_type = type_for(buf.data[offset])
  local nlen = types_len_map[obj_type]
  local ntype
  if (obj_type == "float") or (obj_type == "double") then
    ntype = obj_type .. " *"
  else ntype = obj_type .. "_t *" end
  return offset+nlen+1,unpack_number(buf,offset,ntype,nlen)
end

local unpack_map = function(buf,offset,n)
  local r = {}
  local k,v
  for i=1,n do
    offset,k = unpackers.dynamic(buf,offset)
    offset,v = unpackers.dynamic(buf,offset)
    r[k] = v
  end
  return offset,r
end

local unpack_array = function(buf,offset,n)
  local r = {}
  for i=1,n do offset,r[i] = unpackers.dynamic(buf,offset) end
  return offset,r
end

unpackers.dynamic = function(buf,offset)
  if offset >= buf.size then return nil,nil end
  local obj_type = type_for(buf.data[offset])
  return unpackers[obj_type](buf,offset)
end

unpackers.undefined = function(buf,offset)
  error("unimplemented")
end

unpackers["nil"] = function(buf,offset)
  return offset+1,nil
end

unpackers["false"] = function(buf,offset)
  return offset+1,false
end

unpackers["true"] = function(buf,offset)
  return offset+1,true
end

unpackers.fixnum_pos = function(buf,offset)
  return offset+1,buf.data[offset]
end

unpackers.uint8 = function(buf,offset)
  return offset+2,buf.data[offset+1]
end

unpackers.uint16 = unpacker_number
unpackers.uint32 = unpacker_number
unpackers.uint64 = unpacker_number

unpackers.fixnum_neg = function(buf,offset)
  -- alternative to cast below:
  -- return offset+1,-band(bxor(buf.data[offset],0x1f),0x1f)-1
  return offset+1,ffi.cast("int8_t *",buf.data)[offset]
end

unpackers.int8 = function(buf,offset)
  return offset+2,ffi.cast("int8_t *",buf.data+offset+1)[0]
end

unpackers.int16 = unpacker_number
unpackers.int32 = unpacker_number
unpackers.int64 = unpacker_number

unpackers.float = unpacker_number
unpackers.double = unpacker_number

unpackers.fixraw = function(buf,offset)
  local n = band(buf.data[offset],0x1f)
  return offset+n+1,ffi.string(buf.data+offset+1,n)
end

unpackers.raw16 = function(buf,offset)
  local n = unpack_number(buf,offset,"uint16_t *",2)
  return offset+n+3,ffi.string(buf.data+offset+3,n)
end

unpackers.raw32 = function(buf,offset)
  local n = unpack_number(buf,offset,"uint32_t *",4)
  return offset+n+5,ffi.string(buf.data+offset+5,n)
end

unpackers.fixarray = function(buf,offset)
  return unpack_array(buf,offset+1,band(buf.data[offset],0x0f))
end

unpackers.array16 = function(buf,offset)
  return unpack_array(buf,offset+3,unpack_number(buf,offset,"uint16_t *",2))
end

unpackers.array32 = function(buf,offset)
  return unpack_array(buf,offset+5,unpack_number(buf,offset,"uint32_t *",4))
end

unpackers.fixmap = function(buf,offset)
  return unpack_map(buf,offset+1,band(buf.data[offset],0x0f))
end

unpackers.map16 = function(buf,offset)
  return unpack_map(buf,offset+3,unpack_number(buf,offset,"uint16_t *",2))
end

unpackers.map32 = function(buf,offset)
  return unpack_map(buf,offset+5,unpack_number(buf,offset,"uint32_t *",4))
end

-- Main functions

local ljp_pack = function(data)
  sbuffer_init(buffer)
  packers.dynamic(data)
  local s = ffi.string(buffer.data,buffer.size)
  sbuffer_destroy(buffer)
  return s
end

local ljp_unpack = function(s,offset)
  if offset == nil then offset = 0 end
  if type(s) ~= "string" then return false,"invalid argument" end
  sbuffer_init(buffer)
  sbuffer_append_str(buffer,s,#s)
  local data
  offset,data = unpackers.dynamic(buffer,offset)
  sbuffer_destroy(buffer)
  return offset,data
end

return {
  pack = ljp_pack,
  unpack = ljp_unpack,
}
