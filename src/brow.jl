module brow

function __init__()
    # Add local submodules to the load path
    push!(LOAD_PATH, "./")
    push!(LOAD_PATH, "../modules")
end

end
