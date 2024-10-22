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

function inspect(x::Context, level=0)
  print("*")
  inspect(x.form, level)
end

string(x::Context) = string(x.form)

function show(io::IO, mime::MIME"text/plain", s::Context)
  print(io, string(s))
end

function walk(inner, outer, m::Context)
  outer(Context(m.env, m.unbound, inner(m.form)))
end

context(m::ds.Map, f) = Context(m, ds.emptyset, f)
context(m::Context, f) = Context(m.env, m.unbound, f)

"""
Embeds a form recursively in a fixed lexical environment.
"""
contextualise(m ,f) = ds.postwalk(x -> context(m, x), f)
function decontextualise(f)
  walker(x) = x
  walker(x::Context) = x.form
  ds.prewalk(walker, f)
end

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
  exwalk(inner, outer, f) = ds.walk(inner, outer, f)

  function exwalk(inner, outer, f::Context{ast.Mu})
    if f.form.arg == k
      outer(f)
    else
      ds.walk(inner, outer, f)
    end
  end

  ex(m::Context) = Context(ds.assoc(m.env, k, v), ds.disj(m.unbound, k), m.form)
  ex(f) = f

  prewalk(f, form) = exwalk(x -> prewalk(f, x), identity, f(form))
  prewalk(ex, m)
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

##### Sub eval

function subeval(c, env, f::ds.Vector)
  compile(c, context(env, ds.into(
    ds.emptyvector,
    map(x -> context(env, ast.Immediate(x))),
    f
  )))
end

##### Eval

function eval(c, f::Context{ds.Symbol})
  if unboundp(f)
    sys.succeed(c, context(f, ast.Immediate(f)))
    return nothing
  end

  v = get(f.env, f.form, :notfound)
  if v === :notfound
    @info f.env
    throw("Cannot evaluate unbound symbol: " * string(f.form))
  else
    compile(c, v)
    # sys.succeed(c, v)
  end
end

function eval(c, f::Context{ast.Immediate})
  function next(x::Context{ast.Immediate})
    sys.succeed(c, context(x, ast.Immediate(x)))
  end
  function next(x)
    eval(c, x)
  end
  eval(sys.withcc(c, :return, next), f.form.form)
end

function eval(c, f::Context{ast.Application})
  next(x::Context{ast.Application}) = context(x, ast.Immediate(x))
  next(x) = eval(c, x)
  compile(sys.withcc(c, :return, next), f.form)
end

function eval(c, f::Context{ast.Pair})
  compile(c, context(f, ast.Application(
    context(f, ast.immediate(f.form.head)),
    f.form.tail
  )))
end

function eval(c, f::Context)
  subeval(c, f, f.form)
end

function eval(c, f)
  sys.succeed(c, f)
end

##### Apply

function apply(c, f::Context{ast.Application}, t)
  function next(a::Context{ast.Application})
    sys.succeed(c, context(f, ast.Application(f, t)))
  end
  function next(a)
    apply(c, a, t)
  end
  apply(sys.withcc(c, :return, next), f.form.head, f.form.tail)
end

function apply(c, f::Context{ast.Mu}, t)
  e = extend(f.form.body, f.form.arg, t)
  @info string(ds.keys(e.env)), string(e.unbound)
  compile(c, e)
end

function apply(c, f::Context{ast.PartialMu}, t)
  # REVIEW: I don't like this: I know that the context of an application doesn't
  # matter. So why am I tracking it?
  sys.succeed(c, context(f, ast.Application(f, t)))
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

function apply(c, f::Context{ast.Immediate}, t)
  sys.succeed(c, context(f, ast.Application(f, t)))
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

subcompile(c, env, f) = sys.succeed(c, f)
subcompile(c, env, f::ds.Symbol) = sys.succeed(c, context(env, f))

function subcompile(c, ctx, f::ds.Vector)
  next(v) = sys.succeed(c, context(ctx, v))
  coll = sys.collector(sys.withcc(c, :return, next), ds.count(f))

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

function compile(c, f::ast.TopLevel)
  env = get(f.meta, ds.keyword("env"))
  compile(c, context(env, f.form.form))
end

function compile(c, f::Context{ast.Mu})
  next(x) = sys.succeed(c, context(x, ast.Mu(f.form.arg, x)))
  compile(sys.withcc(c, :return, next), f.form.body)
end

function compile(c, f::Context{ast.PartialMu})
  sys.succeed(c, f)
end

function compile(c, f::Context)
  subcompile(c, f, f.form)
end

function compile(c, f)
  @info f
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
