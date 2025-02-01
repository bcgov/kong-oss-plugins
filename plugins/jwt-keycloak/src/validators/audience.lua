local function validate_audience(allowed_audience, jwt_claims)
    if allowed_audience == nil then
        return true
    end
    if jwt_claims.aud == nil then
        return nil, "Missing audience claim"
    end

    if (type(jwt_claims.aud) == "table") then
        for _, curr_aud in pairs(jwt_claims.aud) do
            if curr_aud == allowed_audience or string.match(allowed_audience, curr_aud) ~= nil then
                return true
            end
        end
    else
        if jwt_claims.aud == allowed_audience or string.match(allowed_audience, jwt_claims.aud) ~= nil then
            return true
        end
    end
    return nil, "Token audience not allowed"
end

return {
    validate_audience = validate_audience
}
