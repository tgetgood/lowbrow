module Eval

import DataStructures as ds

import ..Forms
import ..System

function aggbind(syms, v::ds.Vector)
  ds.into(syms, map(x -> aggbind(ds.emptyvector, x)) ∘ ds.cat(), v)
end

function aggbind(syms, v::Forms.Symbol)
  ds.conj(syms, v)
end

function uniquep(v)
  s = ds.emptyset
  for e in v
    if ds.containsp(s, e)
      return false
    end
    s = ds.conj(s, e)
  end
  return true
end

function bindings(form)
  temp = aggbind(ds.emptyvector, form)
  if uniquep(temp)
    ds.into(ds.emptyset, temp)
  else
    @error "shadowed symbols in binding."
    throw("no shadow")
  end
end

function destructuringbind(params, args)
end

function apply(cont, env, f::μ, args)

end

function apply(cont, env, f::Function, args)
  f(cont, env, args...)
end

function eval(cont, env, f::Forms.ListForm)
  function next(x)
    apply(cont, env, x, f[2:end])
  end
  eval(next, env, f[1])
end

function eval(cont, env, f::Forms.Symbol)
  # REVIEW: This assertion will be costly. But then we're caching, so probably
  # worth it.
  v = ds.containsp(env, f)

  if v == ds.nil
    @error "asserts are failing silent for some reason."
    throw("Error evaluating undefined symbol.")
  end
  cont(ds.get(env, f))
end

function evalimmediate(cont, context, form::Forms.ImmediateList)
  head = form[1]

end

struct μ
  receiver
  params
  immediates
  body
end

struct NestedContext
  params
  env
end

function createμ(cont, env, params, body)
  params = args[1]
  body = args[2]
  syms = bindings(params)
  context = NestedContext(syms, env)
  mubody = evalimmediate(context, body)
end

end # module
