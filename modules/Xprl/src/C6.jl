module C6

import DataStructures as ds
import ..System as sys
import ..AST as ast

##### Env during compile

struct Context
  env::ds.Map
  mus::ds.Map
end

string(x::Context) = "#Context"

function show(io::IO, mime::MIME"text/plain", s::Context)
  print(io, string(s))
end

context(m::ds.Map) = Context(m, ds.emptymap)

##### Compile

function compile()
end

end # module
