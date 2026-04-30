for _, hash in ipairs(G.order) do
    if trailer(hash) ~= "state" then
        print(hash)
    end
end
