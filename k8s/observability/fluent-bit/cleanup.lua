function cleanup_log(tag, timestamp, record)
    -- 1. Extract message (standardize on 'message')
    local msg = record["message"]
    if msg == nil then
        if record["msg"] ~= nil then
            msg = record["msg"]
        elseif record["log"] ~= nil then
            msg = record["log"]
        end
    end
    
    -- Strip trailing newlines/carriage returns and trim whitespace
    if msg ~= nil then
        msg = tostring(msg):gsub("\r", ""):gsub("\n", "")
        msg = msg:match("^%s*(.-)%s*$")
    end

    -- 2. Extract timestamp
    local raw_ts = record["log_timestamp"] or record["timestamp"] or record["time"]
    local opensearch_ts = nil
    
    if raw_ts ~= nil then
        local ts = tostring(raw_ts)
        if ts:match("%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d") then
            -- 2026-04-26 14:18:34 -> 2026-04-26T14:18:34.000Z
            opensearch_ts = ts:gsub(" ", "T") .. ".000Z"
        elseif ts:match("%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d") then
            opensearch_ts = ts
        end
    end

    -- Fallback: if no timestamp could be parsed, format the Fluent Bit event timestamp or system time
    if opensearch_ts == nil then
        local sec = nil
        if type(timestamp) == "table" then
            sec = timestamp["sec"] or timestamp[1]
        elseif type(timestamp) == "number" then
            sec = timestamp
        end
        sec = sec or os.time()
        opensearch_ts = os.date("!%Y-%m-%dT%H:%M:%SZ", sec)
    end

    -- 3. Extract environment (default to production if not set)
    local env = record["environment"] or "production"

    -- 4. Extract trace_id and span_id
    local trace_id = record["trace_id"] or record["traceId"]
    local span_id = record["span_id"] or record["spanId"]

    -- 5. Extract container_name for Grafana query filtering
    local container_name = nil
    if record["kubernetes"] ~= nil then
        container_name = record["kubernetes"]["container_name"]
    end
    if container_name == nil then
        container_name = record["container_name"]
    end

    -- Construct the clean record containing ONLY the 5 required columns and container name
    local clean_rec = {}
    clean_rec["@timestamp"] = opensearch_ts
    clean_rec["message"] = msg
    clean_rec["environment"] = env
    
    if trace_id ~= nil and tostring(trace_id) ~= "" and tostring(trace_id) ~= "-" then
        clean_rec["trace_id"] = tostring(trace_id)
    end
    
    if span_id ~= nil and tostring(span_id) ~= "" and tostring(span_id) ~= "-" then
        clean_rec["span_id"] = tostring(span_id)
    end

    if container_name ~= nil then
        clean_rec["kubernetes"] = {
            container_name = container_name
        }
    end

    return 2, timestamp, clean_rec
end
