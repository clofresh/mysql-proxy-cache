require('luarocks.require')
require('string')
require('Utils')
require('Ehcache')

-- Change this to your ecache server
local cache = Ehcache.Connect('http://127.0.0.1:8080/ehcache/rest')

function get_cache_ttl(query)    
    -- Are we instructed to cache this query?
    if Utils.string.starts(query, '/* CACHE: ')
    then
        return string.match(query, '/%* CACHE: (%d+) %*/')
    end
    if Utils.string.starts(query, '/* REFRESH: ')
    then
        return string.match(query, '/%* REFRESH: (%d+) %*/')
    end
    return nil
end

function get_cache_id()
    if string.len(proxy.connection.client.default_db) == 0
    then
        return 'DEFAULT'
    end
    return proxy.connection.client.default_db
end

function to_hash(query)
    -- Remove comments from the query to allow different commands
    -- to hash to the same value
    query = (string.gsub(query, '/%* .- %*/', ''))
    -- Trim whitespace
    query = Utils.string.trim(query)
    
    return Utils.string.hex(query)
end

function cache_set(result_packet)
    local query         = result_packet.query:sub(2)
    local ttl           = get_cache_ttl(query)
    local field_count   = 1
    local fields        = result_packet.resultset.fields
    local resultset     = {rows={}, fields={}}

    while fields[field_count] do
        local field = fields[field_count]
        table.insert(resultset.fields, {type=field.type, name=field.name} )
        field_count = field_count + 1
    end

    for row in result_packet.resultset.rows do
        table.insert(resultset.rows, row)
    end

    cache:create(get_cache_id())
    cache:set(get_cache_id(), to_hash(query), resultset, ttl)
end

function read_query( packet )
    if packet:byte() == proxy.COM_QUERY then
        local query = packet:sub(2)
        
    -- Embedded command?
        if not Utils.string.starts(query, '/* ')
        then
            return
        end
        
    -- Refresh?
        if Utils.string.starts(query, '/* REFRESH: ')
        then
            cache:delete(get_cache_id(), to_hash(query))
        end
        
        local ttl   = get_cache_ttl(query)

        if ttl then
            local resultset = cache:get(get_cache_id(), to_hash(query))
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
        
        -- Expire the cache if we are instructed to
        if Utils.string.starts(query, '/* FLUSH */')
        then
            cache:delete(get_cache_id(), to_hash(query))
            proxy.response.type = proxy.MYSQLD_PACKET_OK
            proxy.response.resultset = {
                fields = {
                        { type = proxy.MYSQL_TYPE_LONG, name = "FLUSH", },
                },
                rows = { { 'Successful' } }
            }
            return proxy.PROXY_SEND_RESULT
        end
        
        -- Look up the hash value
        if Utils.string.starts(query, '/* HASH */')
        then
            proxy.response.type = proxy.MYSQLD_PACKET_OK
            proxy.response.resultset = {
                fields = {
                        { type = proxy.MYSQL_TYPE_LONG, name = "HASH", },
                },
                rows = { { to_hash(query) } }
            }
            return proxy.PROXY_SEND_RESULT
        end
        
    end
end

function read_query_result(result_packet)
    -- This only gets called if the proxy.queries queue is modified
    cache_set(result_packet)
end

