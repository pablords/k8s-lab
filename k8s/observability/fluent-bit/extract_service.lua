-- Extrai o nome do serviço a partir da tag Docker
-- Tag format: "docker.marketplace-catalog-service" → service_name = "catalog-service"
-- Tag format: "docker.marketplace-api-gateway"     → service_name = "api-gateway"
function extract_service_name(tag, timestamp, record)
    if tag then
        -- Remove prefixo "docker.marketplace-"
        local service = tag:gsub("^docker%.marketplace%-", "")
        if service and service ~= "" then
            record["service_name"] = service
        end
    end
    return 2, timestamp, record
end
