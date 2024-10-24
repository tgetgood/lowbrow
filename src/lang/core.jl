import Xprl as x
import Xprl.AST as ast
import Xprl.AST: inspect
import Xprl.System as sys
import Xprl.C5 as c
import Xprl.Reader as r

import DataStructures as ds

env = Ref{Any}(x.DefaultEnv.default)

core = r.tostream(open("./core.xprl"))
test = r.tostream(open("./test.xprl"))

function eset(e)
  env[] = e
  nothing
end

o = Ref{Any}()

rc = sys.withcc(
  ds.emptymap,
  :env, eset,
  :return, inspect
)

rcc = sys.withcc(rc, :return, x -> o[] = x)

function readeval(conts, env, stream)
  try
    form = r.read(env, stream)
    if form === nothing
      readeval(conts, env, stream)
    else
      @info "Compiling:" * string(form)
      c.interpret(conts, env, form)
    end
  catch EOFError
    nothing
  end
end

function evalseq(root, envvar, stream)
  function next(x)
    if x !== nothing
      inspect(x)
      evalseq(root, envvar, stream)
    end
  end

  readeval(
    sys.withcc(root, :return, next, :env, x -> envvar[] = x),
    envvar[],
    stream
  )
end

evalseq(rc, env, core)

# f = r.readall(open("./test.xprl"))
