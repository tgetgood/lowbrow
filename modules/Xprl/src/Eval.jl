module Eval

import DataStructures as ds

import ..Forms
import ..System

struct μ
  env
  params
  immediates
  body
end

function apply(f::μ, args)
  env = extend(f.env, destructuring-bind(f.params, args))

end

# Eval is fairly trivial here. All of the magic happens in send/receive. Well,
# those are kind of trivial as well.
#
# invocation syntax (f x) means send [x] literally as a message to (eval f). f
# will decide whether or not to evaluate x itself. We don't need to specify or
# send an environment because x contains the environment in which it was
# defined.
function eval(f::Forms.ListForm)
  eval(f.env, f)
end

function eval(env, f::Forms.ListForm)
  rec = eval(env, f.head)
  Receivers.receive(rec, f.tail)
end

function eval(f::Forms.Symbol)
  # REVIEW: This assertion will be costly. But then we're caching, so probably
  # worth it.
  v = ds.containsp(f.env, f.name)
  @assert v != ds.nil "Error evaluating undefined symbol."
  eval(v)
end

function evalwithevaledargs(f::Forms.ListForm)
  # ???
end

function mapeval(collector, exprs)
end

end # module
