module brow

function __init__()
  # Add local submodules to the load path
  include @__DIR__ * "../repl.jl"
 end

end
