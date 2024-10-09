module Compiler

import DataStructures as ds

import ..System
import ..Receivers as rec
import ..AST as ast

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
   rt.Immediate(env, compile(x))
  end
end

function invoke(env, x::ds.Immediate)
  ds.Immediate(env, invoke(env, x.form))
end

function invoke(env::rt.Context, x::ds.Symbol)
  if ds.containsp(env, x)
    compile(ds.get(env, x))
  elseif rt.unboundp(env, x)
    rt.Immediate(env, x)
  else
    throw("Unresolved symbol: " * string(x))
  end
end

function invoke(env, x::ds.Pair)
  compile(rt.Application(env, rt.Immediate(env, x.head), x.tail))
end

function apply(env, f::PrimitiveFunction, args)
  if ast.reduced(args)
    f.f(args...)
  else
    rt.Application(f, args)
  end
end

function apply(env, f::PrimitiveMacro, args)
  f.f(env, args...)
end

function apply(env, f::rt.ClosedMu, arg)
  compile(ds.assoc(env, f.arg, arg), f.body)
end

function apply(env, f::OpenMu, arg)
  rt.Application(f, compile(env, arg))
end

function compile(form)
  form
end

function compile(form::ds.ArgList)
  rt.arglist(map(x -> compile(env, x), form.contents))
end

function compile(form::ds.Immediate)
  invoke(form.env, form.form)
end

function compile(env, form::ds.Pair)
  ds.Pair(compile(env, form.head), compile(env, form.tail))
end

function compile(form::rt.Application)
  apply(form.env, compile(form.head), compile(form.tail))
end

function compile(form::rt.TopLevelForm)
  compile(rt.immediate(rt.RootContext(form.env), form.form))
end

end # module
