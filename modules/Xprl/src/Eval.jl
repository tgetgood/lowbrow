module Eval

import DataStructures as ds

import ..System
import ..Receivers as rec
import ..Runtime as rt

abstract type BuiltIn end
"""
Primitive functions expect their arguments to be literal values. They should
normally be wrapped to make sure args are evaluated.
"""
struct PrimitiveFunction <: BuiltIn
  f::Function
end

"""
Primitive macros operate directly on the AST of the program. They also receive
the lexical envronment when invoked.
"""
struct PrimitiveMacro <: BuiltIn
  f::Function
end

# FIXME: This can be expensive to compute. We need a flag of some sort so as not
# to do it more than once for a given value.
valuep(x::Int) = true
valuep(x::String) = true
valuep(x::Bool) = true
valuep(x::ds.Vector) = ds.every(valuep, x)
valuep(x::ds.Map) = ds.every(e -> valuep(ds.key(e)) && valuep(ds.val(e)), x)
valuep(x) = false

function invoke(env, x)
  if valuep(x)
    x
  else
   ds.Immediate(compile(env, x))
  end
end

function invoke(env, x::ds.Immediate)
  ds.Immediate(invoke(env, x.content))
end

function invoke(env, x::ds.Symbol)
  if ds.containsp(env, x)
    ds.get(env, x)
  else
    throw("Unresolved symbol: " * string(x))
  end
end

function invoke(env, x::ds.Pair)
  rt.Application(ds.Immediate(x.head), x.tail)
end

function treereduce(form)
  res = ds.postwalk(cwalk, form)
  if res == form
    res
  else
    treereduce(res)
  end
end

"""
Returns true iff the form cannot be further reduced and contains no immediate
evaluation. (Immediate evaluation just means reductions that cannot be done yet
but must eventually be performed).
"""
reduced(form) = true
reduced(form::ds.Immediate) = false
reduced(form::rt.Application) = false
reduced(form::ds.Pair) = reduced(form.head) && reduced(form.tail)
reduced(form::rt.Mu) = reduced(form.argsym) && reduced(form.body)
reduced(form::ds.ArgList) = ds.every(identity, map(reduced, form.contents))

function apply(env, f, args)
  rt.Application(f, args)
end

function apply(env, f::PrimitiveFunction, args)
  if ds.every(identity, map(reduced, args.contents))
    f.f(args...)
  else
    rt.Application(f, args)
  end
end

function apply(env, f::PrimitiveMacro, args)
  f.f(env, args...)
end

function compile(env, form)
  form
end

function compile(env, form::ds.ArgList)
  ds.arglist(map(x -> compile(env, x), form.contents))
end

function compile(env, form::ds.Immediate)
  invoke(env, form.content)
end

function compile(env, form::ds.Pair)
  ds.Pair(compile(env, form.head), compile(env, form.tail))
end

function compile(env, form::rt.Application)
  apply(env, compile(env, form.head), form.tail)
end

function compile(env, form::rt.Mu)
  rt.Mu(compile(env, form.argsym), compile(env, form.body))
end

function eval(env, form)
  compile(env, ds.Immediate(form))
end

end # module
