require('luarocks.require')
require('md5')
require('Memcached')
local memcache = Memcached.Connect()
cache_hits = 0
cache_misses = 0
cache_timeout = 30
function is_query(packet)
    return packet:byte() == proxy.COM_QUERY
end

function is_cacheable(query)
    return query:sub(1,6):lower() == 'select'
end

function to_hash(query)
    return md5.sumhexa(query)
end

function cache_get(query)
    local result = deserialize(memcache:get(to_hash(query)))
    if result then
        print('HIT: '..to_hash(query)..' ('..query..')')
        cache_hits = cache_hits + 1
    else
        print('MISS: '..to_hash(query)..' ('..query..')')
        cache_misses = cache_misses + 1
    end

    print('Cache hit ratio: '..cache_hits..'/'..cache_misses..' = '..cache_hits/cache_misses)

    return result
end

function cache_set(result_packet)
    local resultset_is_needed = false
    local query = result_packet.query:sub(2)
    local field_count = 1
    local fields = result_packet.resultset.fields
    local resultset = {rows={}, fields={}}

    print('SET: '..to_hash(query)..' ('..query..')')

    while fields[field_count] do
        local field = fields[field_count]
	--added third option, expiry time.
        table.insert(resultset.fields, {type=field.type, name=field.name} )
        field_count = field_count + 1
    end

    for row in result_packet.resultset.rows do
        table.insert(resultset.rows, row)
    end

    memcache:set(to_hash(query), serialize(resultset), cache_timeout)
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

        if is_cacheable(query) then
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

