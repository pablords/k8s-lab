function cleanup_log(tag, timestamp, record)
    -- Normalize and trim level to uppercase
    if record["level"] ~= nil then
        local lvl = tostring(record["level"])
        record["level"] = lvl:gsub("%s+", ""):upper()
    end
    
    -- Ensure uniform message field (use 'message' as standard)
    if record["message"] == nil then
        if record["msg"] ~= nil then
            record["message"] = record["msg"]
        elseif record["log"] ~= nil then
            record["message"] = record["log"]
        end
    end
    
    -- Normalize timestamp for OpenSearch (replace space with T if needed)
    -- Try both 'log_timestamp' (from plain text regex) and 'timestamp' (from JSON)
    local raw_ts = record["log_timestamp"] or record["timestamp"]
    
    if raw_ts ~= nil then
        local ts = tostring(raw_ts)
        if ts:match("%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d") then
            -- Plain text format: 2026-04-26 14:18:34 -> 2026-04-26T14:18:34.000Z
            record["@timestamp"] = ts:gsub(" ", "T") .. ".000Z"
        elseif ts:match("%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d") then
            -- Already ISO, but ensure it's valid for OpenSearch
            record["@timestamp"] = ts
        end
    end

    -- Normalize trace_id and span_id
    if record["trace_id"] == nil and record["traceId"] ~= nil then
        record["trace_id"] = record["traceId"]
    end
    if record["span_id"] == nil and record["spanId"] ~= nil then
        record["span_id"] = record["spanId"]
    end
    
    return 2, timestamp, record
end
