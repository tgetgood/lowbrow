module C4

import DataStructures as ds
import ..System as sys

##### Context of Interpretation
##
## Storing the context (lexical + dynamic environments) of each form in band is
## proving to be a logistical fiasco. So let's try out of band encoding.

struct Context
  env
  unbound
  form
  children
end

string(x::Context) = "#Context"

function show(io::IO, mime::MIME"text/plain", s::Context)
  print(io, string(s))
end

context(m, f) = Context(m, ds.emptyset, f, )
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

# REVIEW: We're going to pass around a pair of (env, form) as we build the tree
# and see how that goes.
succeed(c, e, f) = sys.emit(c, :return, (e, f))

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

"""
Interprets `form` in the lexical environment `env` as if the form were read from
that environment. `c` is the bundle of channels to which messages may be emitted
during interpretation.
"""
function interpret(c, env, form)
  compile(c, context(env), ast.immediate(form))
end

end
