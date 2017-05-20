local ffi = require'ffi'

ffi.cdef[[
int RAND_bytes(unsigned char *buf, int num);
]]

local t = ffi.typeof'uint8_t[?]'

local function random_string(len)
    local s = ffi.new(t, len)
    assert(ffi.C.RAND_bytes(s, len) == 1) --1 means strong random
    return ffi.string(s, len)
end

return random_string
