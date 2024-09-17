module Eval

import DataStructures as ds

import ..Forms
import ..System

struct μ
  params
  immediates
  body
end

function destructuringbind(params, args)
end

function apply(env, f::μ, args)
  env = extend(env, destructuringbind(f.params, args))
  instantiate(f, env)
end

function apply(env, f::Function, args)
  # N.B.: builtins ignore the env. What would they do with it?
  f(args...)
end

function createμ(params::Forms.Form, body::Forms.Form)

end

function instantiate(f::μ, env)

end

function eval(env, f::Forms.ListForm)
  apply(env, eval(env, f.head), f.tail)
end

function eval(env, f::Forms.Symbol)
  # REVIEW: This assertion will be costly. But then we're caching, so probably
  # worth it.
  v = ds.containsp(env, f)
  @assert v != ds.nil "Error evaluating undefined symbol."
  ds.get(env, f)
end

end # module
