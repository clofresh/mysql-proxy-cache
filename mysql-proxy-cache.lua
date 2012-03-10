require('luarocks.require')
require('md5')
require('sha1')
require('Memcached')

cache_hits = 0
cache_misses = 0

-- Change this to your memcached server(s)
local memcache = Memcached.Connect('127.0.0.1', 11211)

function is_query(packet)
    return packet:byte() == proxy.COM_QUERY
end

function get_cache_ttl(query)
    -- Are we instructed to cache this query?
    local ttl = string.match(query, '/%* CACHE: %d+ %*/')
    if not ttl
    then
        return nil
    end
    
    ttl = string.match( ttl, '%d+')
    return ttl
end

function HexDumpString(str,spacer)
    return (
        string.gsub(str,"(.)",
            function (c)
                return string.format("%02X%s",string.byte(c), spacer or "")
            end)
        )
end

function to_hash(query)
    local hash = proxy.connection.client.default_db..'-'
    -- Remove comments from the query to allow different commands
    -- to hash to the same value
    query = (string.gsub(query, '/%* .- %*/', ''))
    -- Trim whitespace
    query = (string.gsub(query, "^%s*(.-)%s*$", "%1"))
    
    hash = hash..string.len(query)..'-'..sha1(query)..'-'..HexDumpString(query)
    hash = string.sub(hash, 1, 250)
    
    return hash
end

function cache_get(query)
    local result = deserialize(memcache:get(to_hash(query)))
--    if result then
--        print('HIT: '..to_hash(query)..' ('..query..')')
--        cache_hits = cache_hits + 1
--    else
--        print('MISS: '..to_hash(query)..' ('..query..')')
--        cache_misses = cache_misses + 1
--    end
--
--    print('Cache hit ratio: '..cache_hits..'/'..cache_misses..' = '..cache_hits/cache_misses)

    return result
end

function cache_set(result_packet)
    local query = result_packet.query:sub(2)
    local ttl = get_cache_ttl(query)
    local field_count = 1
    local fields = result_packet.resultset.fields
    local resultset = {rows={}, fields={}}

    while fields[field_count] do
        local field = fields[field_count]
	--added third option, expiry time.
        table.insert(resultset.fields, {type=field.type, name=field.name} )
        field_count = field_count + 1
    end

    for row in result_packet.resultset.rows do
        table.insert(resultset.rows, row)
    end

    memcache:set(to_hash(query), serialize(resultset), ttl)
end

function serialize(o)
    local result = {}
    local o_type = type(o)

    if o_type == "number" then
        table.insert(result, o)

    elseif o_type == "string" then
        table.insert(result, string.format("%q", o))

    elseif o_type == "table" then
        table.insert(result, "{")
        for key, value in pairs(o) do
            for i, str in pairs({"[", serialize(key), "]=",
                                serialize(value), ","}) do
                table.insert(result, str)
            end
        end
        table.insert(result, "}")

    elseif o_type == "nil" then
        table.insert(result, "nil")

    else
        error("cannot serialize a " .. o_type)
    end

    return table.concat(result, '')
end

function deserialize(s)
    if s then
        return loadstring('return '..s)()
    else
        return nil
    end
end

function read_query( packet )
    if is_query(packet) then
        local query = packet:sub(2)
        local ttl = get_cache_ttl(query)
        
        -- Expire the cache if we are instructed to
        if string.match(query, '/%* FLUSH %*/')
            then
            memcache:delete(to_hash(query))
            proxy.response.type = proxy.MYSQLD_PACKET_OK
            proxy.response.resultset = {
                fields = {
                        { type = proxy.MYSQL_TYPE_LONG, name = "FLUSH", },
                },
                rows = { { 'Successful' } }
            }
            return proxy.PROXY_SEND_RESULT
        end

        if ttl then
            local resultset = cache_get(query)
            if resultset then
                -- Cache hit
                proxy.response.type = proxy.MYSQLD_PACKET_OK
                proxy.response.resultset = resultset

                return proxy.PROXY_SEND_RESULT
            else
                -- Cache miss
                proxy.queries:append(1, packet,{resultset_is_needed = true})

                return proxy.PROXY_SEND_QUERY
            end
    end
    end
end

function read_query_result(result_packet)
    -- This only gets called if the proxy.queries queue is modified
    cache_set(result_packet)
end

