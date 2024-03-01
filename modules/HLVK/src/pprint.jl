module pprint

import Vulkan as vk
import DataStructures: showrecur, indent, showseq
import DataStructures as ds

function showrecur(io::IO, depth, s::vk.HighLevelStruct)
  print(io, string(typeof(s)) * ": {\n")
  for k in fieldnames(typeof(s))
    indent(io, depth)
    showrecur(io, depth, k)
    print(io, " -> ")
    showrecur(io, depth + 1, getproperty(s, k))
    print(io, "\n")
  end
  indent(io, depth - 1)
  print(io, "}")
end

function showrecur(io::IO, depth, t::Tuple)
  print(io, string(typeof(t)) * ": (\n")
  showseq(io, depth, t)
  print(io, ")")
end


end
