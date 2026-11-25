local M = {}

function M.isBed(kind)
    return kind == "bed.queen" or kind == "bed.single"
end

function M.supported(kind)
    return M.isBed(kind) or kind == "sofa.pair"
end

return M
