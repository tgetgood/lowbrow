module C4

import DataStructures as ds
import ..System as sys

struct Context
  env
  unbound
end

string(x::Context) = "#Context"

function show(io::IO, mime::MIME"text/plain", s::Context)
  print(io, string(s))
end

context(m) = Context(m, ds.emptyset)
declare(m::Context, k) = Context(m.env, ds.conj(m.unbound, k))
get(m::Context, k) = ds.get(m.env, k)
get(m::Context, k, default) = ds.get(m.env, k, default)
containsp(m::Context, k) = ds.containsp(m.env, k)
unboundp(m::Context, k) = ds.containsp(m.unbound, k)

function extend(m::Context, k, v)
  if ds.containsp(m.unbound, k)
    Context(ds.assoc(m.env, k, v), ds.disj(m.unbound, k), m.cursor)
  else
    throw("Cannot bind undeclared symbol " * string(k))
  end
end

################################################################################
##### The compiler is basically a state machine that can be in one state of
##### three: compile, eval, apply.
#####
##### This is not a typical metacircular interpreter since you can compile code
##### that cannot be executed and eval/apply are really part of the compiler.
#####
##### Compiler isn't really a good name for it since what we're really doing is
##### running the code as far as we can given what we know now, which we will do
##### again every time we know more. So it's more like a step function. But the
##### first step seems like it will be the biggest, and so it is kind of like
##### compiling.
#####
##### I don't really know what to call this.
##### Sufficiently late binding, maybe.
################################################################################

##### Eval

##### Apply

##### Compile

##### Top level entry point


function entry(c, env, form)
end

end
