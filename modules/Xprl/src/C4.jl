module C4

import Base: get, string, show

import DataStructures as ds
import DataStructures: walk
import ..System as sys
import ..AST as ast
import ..AST: inspect, reduced

##### Context of Interpretation
##
## Storing the context (lexical + dynamic environments) of each form in band is
## proving to be a logistical fiasco. So let's try out of band encoding.

struct Context{T}
  env::ds.Map
  unbound::ds.Set
  form::T
end

reduced(x::Context) = reduced(x.form)
inspect(x::Context, level=0) = inspect(x.form, level)

string(x::Context) = string(x.form)

function show(io::IO, mime::MIME"text/plain", s::Context)
  print(io, string(s))
end

function walk(inner, outer, m::Context)
  outer(Context(m.env, m.unbound, inner(m.form)))
end

context(m, f) = Context(m, ds.emptyset, f)

"""
Embeds a form recursively in a fixed lexical environment.
"""
contextualise(m ,f) = ds.postwalk(x -> context(m, x), f)
decontextualise(f) = ds.prewalk(x -> x.form, f)

function declare(m::Context, k)
  dec1(m::Context) = Context(m.env, ds.conj(m.unbound, k), m.form)
  dec1(x) = x
  ds.postwalk(dec1, m)
end

get(m::Context, k) = ds.get(m.env, k)
get(m::Context, k, default) = ds.get(m.env, k, default)
containsp(m::Context, k) = ds.containsp(m.env, k)
unboundp(m::Context, k) = ds.containsp(m.unbound, k)
unboundp(m::Context{ds.Symbol}) = unboundp(m, m.form)

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

function eval(c, f::Context{ds.Symbol})
  if unboundp(f)
    sys.succeed(c, context(f.env, ast.Immediate(f)))
    return nothing
  end

  v = get(f.env, f.form, :notfound)
  if v === :notfound
    throw("Cannot evaluate unbound symbol: " * string(f.form))
  else
    compile(c, v)
    # sys.succeed(c, v)
  end
end

function eval(c, f::Context{ast.Immediate})
  function next(x::Context{ast.Immediate})
    sys.succeed(c, context(x.env, ast.Immediate(x)))
  end
  function next(x)
    eval(c, x)
  end
  eval(sys.withcc(c, :return, next), f.form.form)
end

function eval(c, f::Context{ast.Application})
  next(x::Context{ast.Application}) = context(x.env, ast.Immediate(x))
  next(x) = eval(c, x)
  compile(sys.withcc(c, :return, next), f.form)
end

function eval(c, f::Context{ast.Pair})
  compile(c, context(f.env, ast.Application(
    context(f.env, ast.immediate(f.form.head)),
    f.form.tail
  )))
end

function eval(c, f)
  sys.succeed(c, f)
end

##### Apply

function apply(c, f::Context{ast.Application}, t)
  function next(a::Context{ast.Application})
    sys.succeed(c, context(ds.emptymap, ast.Application, f, t))
  end
  function next(a)
    apply(c, a, t)
  end
  apply(withcc(c, :return, next), f.form.head, f.form.tail)
end

function apply(c, f::ast.PrimitiveMacro, t)
  f.f(c, t)
end

function apply(c, f::ast.PrimitiveFunction, t)
  function next(t)
    if ast.reduced(t)
      sys.succeed(c, f.f(decontextualise(t)...))
    else
      sys.succeed(c, context(ds.emptymap, ast.Application(f, t)))
    end
  end

  compile(sys.withcc(c, :return, next), t)
end

function apply(c, f, t)
  @info "failed application: " * string(typeof(f))
  sys.succeed(c, context(ds.emptymap, ast.Application(f, t)))
end

##### sub compile
##
## Julia's polymorphism has some sharp corners. Reasons aside, you can't
## dispatch on a parametrised type (say Context{ds.Vector}) if the type
## parameter itself could be parametrised (a Context{Vector{T}} is not a
## Context{Vector}). Thus this indirection.

subcompile(c, env, f) = throw("Compiling invalid expression")
subcompile(c, env, f::ds.Symbol) = sys.succeed(c, context(env, f))

function subcompile(c, _, f::ds.Vector)
  coll = sys.collector(c, ds.count(f))
  runner((i, f)) = compile(sys.withcc(c, :return, x -> sys.receive(coll, i, x)), f)
  tasks = ds.into(
    ds.emptyvector,
    ds.interleave(),
    ds.repeat(:run),
    ds.mapindexed(tuple, f)
  )
  sys.emit(sys.withcc(c, :run, runner), tasks...)
end

function subcompile(c, _, f::ds.Map)
  throw("Can't compile maps yet")
end

##### Compile

function compile(c, f::Context{ast.Immediate})
  eval(c, f.form.form)
end

function compile(c, f::Context{ast.Application})
  next(head) = apply(c, head, f.form.tail)
  compile(sys.withcc(c, :return, next), f.form.head)
end

function compile(c, f::Context{ast.TopLevel})
  compile(c, f.form.form)
end

function compile(c, f::Context)
  subcompile(c, f.env, f.form)
end

function compile(c, f)
  sys.succeed(c, f)
end


##### Top level entry point

"""
Interprets `form` in the lexical environment `env` as if the form were read from
that environment. `c` is the bundle of channels to which messages may be emitted
during interpretation.
"""
function interpret(c, env, form)
  compile(c, contextualise(env, ast.Immediate(form)))
end

end
