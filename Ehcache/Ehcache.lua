--Copyright (c) 2012 Rob Smith (kormoc@gmail.com)
--
--Permission is hereby granted, free of charge, to any person obtaining a copy 
--of this software and associated documentation files (the "Software"), to deal
--in the Software without restriction, including without limitation the rights 
--to use, copy, modify, merge, publish, distribute, sublicense, and/or sell 
--copies of the Software, and to permit persons to whom the Software is 
--furnished to do so, subject to the following conditions:
--
--The above copyright notice and this permission notice shall be included in all
--copies or substantial portions of the Software.
--
--THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
--IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
--FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
--AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
--LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
--OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS 
--IN THE SOFTWARE.

module('Ehcache', package.seeall)

require("string")
require("json")
local http  = require("socket.http")

--- LTN12 Source constructors
-- @class module
-- @name luci.ltn12.source

--- Create a string source.
-- @param s Data
-- @return LTN12 source
function sourceString(s)
    if s then
        local i = 1
        return function()
            local chunk = string.sub(s, i, i+2048-1)
            i = i + 2048
            if chunk ~= "" then return chunk
            else return nil end
        end
    else return nil end
end

--- LTN12 sink constructors
-- @class module
-- @name luci.ltn12.sink

--- Create a sink that stores into a table.
-- @param t output table to store into
-- @return LTN12 sink
function sinkTable(t)
    t = t or {}
    local f = function(chunk, err)
        if chunk then t[#t+1] = chunk end
        return 1
    end
    return f, t
end

function get(cache, id, key)
    local headers = {}
    local body = {}
    headers["Content-Type"] = "application/json"
    b, c, h = http.request {
        method = "GET",
        url = cache.url..'/'..id..'/'..key,
        headers = headers,
        sink = sinkTable(body)
    }
    if c == 200
    then
        return json.decode(body[1])
    end
    if c == 404
    then
        return nil
    end
    
    print( b )
    print( c )
    for k,v in pairs(h) do print(k,v) end
    for k,v in pairs(body) do print(k,v) end
    return nil
end

function set(cache, id, key, value, expiry)
    value = json.encode(value)
    local headers = {}
    local len = string.len(value)
    headers["Content-Type"]             = "application/json"
    headers["content-length"]           = len
    headers["ehcacheTimeToLiveSeconds"] = expiry
    
    b, c, h = http.request {
        method = "PUT",
        url = cache.url..'/'..id..'/'..key,
        source = sourceString(value),
        headers = headers
    }
    if c == 201
    then
        return true
    end
    print( b )
    print( c )
    for k,v in pairs(h) do print(k,v) end
    return false
end

function delete(cache, id, key)
    local headers = {}
    headers["Content-Type"] = "application/json"
    b, c, h = http.request {
        method = "DELETE",
        url = cache.url..'/'..id..'/'..key,
        headers = headers
    }
    if c == 204
    then
        return true
    end
    print( b )
    print( c )
    for k,v in pairs(h) do print(k,v) end
    return false
end

function create(cache, id)
    value = json.encode(value)
    b, c, h = http.request {
        method = "PUT",
        url = cache.url..'/'..id,
    }
    -- Success
    if c == 200
    then
        return true
    end
    -- Already Exists
    if c == 409
    then
        return false
    end
    -- Unknown
    print( b )
    print( c )
    for k,v in pairs(h) do print(k,v) end

    return nil
end

function Connect(url)
    return {
        url     = url,
        id      = nil,
        get     = get,
        set     = set,
        delete  = delete,
        create  = create
    }
end

function New(url)
    return Connect(url)
end
