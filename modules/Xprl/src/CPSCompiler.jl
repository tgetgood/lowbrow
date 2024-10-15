module CPSCompiler

import Base: string, show

import DataStructures as ds
import DataStructures: get, containsp

import ..AST as ast

function runtask(t)
  Threads.@spawn begin
    try
      t()
    catch e
      ds.handleerror(e)
    end
  end
end

function debugruntask(t)
  t()
end

function trysend(c, k, v)
  k = ds.keyword(k)
  if ds.containsp(c, k)
    debugruntask(() -> ds.get(c, k)(v))
  else
    throw("Cannot emit message on unbound channel: " * string(k))
  end
end

function emit(c, kvs...)
  @assert length(kvs) % 2 === 0
  for (k, v) in ds.partition(2, kvs)
    # TODO: Schedule these properly.
    trysend(c, k, v)
  end
end

succeed(c, v) = emit(c, :return, v)
fail(c, env, v) = emit(c, :failure, (env, v))

mutable struct Collector
  @atomic counter::Int
  const vec::Base.Vector
  const next
end

function collector(c, n)
  Collector(0, Vector(undef, n), c)
end

function receive(coll::Collector, i, v)
  coll.vec[i] = v
  @atomic coll.counter += 1

  if coll.counter > length(coll.vec)
    @error "calling too many times!!!"
  end

  if coll.counter == length(coll.vec)
    emit(coll.next, :return, ds.vec(coll.vec))
  end
end

function failcoll(coll)
  function(_)
    # FIXME: this is aweful
    @atomic coll.counter = -1000
    emit(coll.next, :failure, :error)
  end
end

struct Context
  env
  unbound
  cursor
end

string(x::Context) = "#Context"

function show(io::IO, mime::MIME"text/plain", s::Context)
  print(io, string(s))
end

function withcc(m::ds.Map, k, c, kvs...)
  ds.into(
    ds.assoc(m, ds.keyword(string(k)), c),
    ds.partition(2) ∘ ds.map(e -> [ds.keyword(string(e[1])), e[2]]),
    kvs
  )
end

context(m) = Context(m, ds.emptyset, ds.emptyvector)
follow(m::Context, k) = Context(m.env, m.unbound, ds.conj(m.cursor, k))
declare(m::Context, k) = Context(m.env, ds.conj(m.unbound, k), m.cursor)
get(m::Context, k) = ds.get(m.env, k)
get(m::Context, k, default) = ds.get(m.env, k, default)
containsp(m::Context, k) = ds.containsp(m.env, k)
unboundp(m::Context, k) = ds.containsp(m.unbound, k)

function mergeenv(lex::Context, dyn::Context)
  unbound = reduce(ds.disj, ds.keys(lex.env); init=dyn.unbound)
  Context(lex.env, unbound, dyn.cursor)
end

function mergeenv(lex::Context, dyn::ds.EmptyMap)
  lex
end

function lexicalextension(x::ast.EnvNode, env::Context)
  # FIXME: This is probably slow, but I'm sick of manually writing cases.
  env = mergeenv(env, x.env)
  t = typeof(x)
  args::Vector{Any} = [env]
  for name in fieldnames(t)
    if name !== :env
      push!(args, getfield(x, name))
    end
  end

  t(args...)
end

lexicalextension(x, env) = x

function extend(m::Context, k, v)
  if ds.containsp(m.unbound, k)
    Context(ds.assoc(m.env, k, v), ds.disj(m.unbound, k), m.cursor)
  else
    throw("Cannot bind undeclared symbol " * string(k))
  end
end

function createμ(c, env, params, body)
  function next(left)
    if isa(left, ds.Symbol)
      env = declare(env, left)
      next = body -> succeed(c, ast.Mu(env, left, body))
    else
      next = body -> succeed(c, ast.PartialMu(
        env,
        left,
        body
      ))
    end
    compile(withcc(c, :return, next), follow(env, :body), body)
  end
  compile(withcc(c, :return, next), follow(env, :arg), params)
end

function eval(c, env, form::ds.Symbol)
  if unboundp(env, form)
    fail(c, env, form)
    return nothing
  end

  v = get(env, form, :notfound)
  if v === :notfound
    # FIXME: There's something wrong with my bookkeeping here.
    fail(c, env, form)
    # throw("Symbol not defined: " * string(form))
  else
    # succeed(c, lexicalextension(v, env))
    # TODO: I don't think the loaded code can ever depend on the loading
    # context, but I need to prove it.
    succeed(c, v)
  end
end

function eval(c, env, form::ast.Pair)
  compile(c, env, ast.Application(
    env,
    ast.immediate(follow(env, :head), form.head),
    form.tail
  ))
end

function eval(c, env, form::ast.Immediate)
  next = f -> eval(c, env, f)
  eval(withcc(c, :return, next), env, form.form)
end

function eval(c, env, x)
  succeed(c, lexicalextension(x, env))
end

function apply(c, env, f::ast.PrimitiveMacro, tail)
  f.f(c, env, tail...)
end

function apply(c, env, f::ast.PrimitiveFunction, tail)
  if ast.reduced(tail)
    succeed(c, f.f(tail...))
  else
    fail(c, env, tail)
  end
end

function apply(c, env, f::ast.Mu, tail)
  compile(c, extend(f.env, f.arg, tail), f.body)
end

function apply(c, env, f::ast.TopLevel, tail)
  apply(c, env, f.compiled, tail)
end

function apply(c, env, f::ast.Application, tail)
  function next(inner)
    apply(c, env, inner, tail)
  end
  compile(withcc(c, :return, next), f.env, f)
end

function apply(c, env, f, xs)
  @warn "failed apply: " * string(typeof(f))
  fail(c, env, f)
end

function compile(c, env, form)
  succeed(c, lexicalextension(form, env))
end

function compile(c, env, form::ast.ArgList)
  failure(env, v) = succeed(c, form)
  next(coll) = succeed(c, ast.arglist(coll))
  coll = collector(withcc(c, :return, next, :failure, failure), ds.count(form))
  run((i, form)) = compile(withcc(c, :faliure, failcoll(coll), :return, x -> receive(coll, i, x)), env, form)

  cmds = ds.into!([], ds.mapindexed((i, v) -> (:run, (i, v))) ∘ ds.cat(), form.args)

  emit(withcc(c, :run, run), cmds...)
end

function compile(c, env, form::ast.Pair)
  failure(_) = succeed(c, form)
  function next(coll)
    p = ast.Pair(env, coll[1], coll[2])
    succeed(c, p)
  end
  coll = collector(withcc(c, :return, next, :failure, failure), 2)

  cc((i, form)) = compile(withcc(c, :failure, failcoll(coll), :return, x -> receive(coll, i, x)), env, form)

  emit(withcc(c, :run, cc), :run, (1, form.head), :run, (2, form.tail))
end

function compile(c, env, form::ast.TopLevel)
  succeed(c, form.compiled)
end

function compile(c, env, form::ast.Application)
  function failhead((e, v))
    succeed(c, lexicalextension(form, e))
  end
  function next(head)
    function failure((e, v))
      succeed(c, ast.Application(mergeenv(e, form.env), head, form.tail))
    end
    nextnext(tail) = apply(c, env, head, tail)
    compile(
      withcc(c, :return, nextnext, :failure, failure),
      follow(env, :tail),
      form.tail
    )
  end

  compile(
    withcc(c, :return, next, :failure, failhead),
    follow(env, :head),
    form.head
  )
end

function compile(c, env, form::ast.Immediate)
  failure((e, v)) = succeed(c, lexicalextension(form, e))
  eval(c, follow(env, :form), form.form)
end

function entry(c, env, form)
  compile(
    c,
    context(env),
    ast.immediate(env, form)
  )
end

end # module
