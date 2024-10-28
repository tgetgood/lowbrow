import Xprl as x
import Xprl.AST as ast
import Xprl.AST: inspect
import Xprl.System as sys
import Xprl.C6 as c
import Xprl.Reader as r

import DataStructures as ds

env = Ref{Any}(x.DefaultEnv.default)

core = r.readall(open("./core.xprl"))
test = r.readall(open("./test.xprl"))

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

function evalseq(root, envvar, forms)
  function next(x)
    if x !== nothing
      inspect(x)
      if ds.count(forms) > 1
        evalseq(root, envvar, ds.rest(forms))
      end
    else
      @info "EOF"
    end
  end

  @info "compiling: " * string(first(forms))

  c.interpret(
    sys.withcc(root, :return, next, :env, x -> envvar[] = x),
    envvar[],
    first(forms)
  )
end

"""
Reads file `fname` and merges it into the given environment.
"""
function loadfile(envvar, fname)
  forms = r.readall(open(fname))

  evalseq(rc, envvar, forms)
end

# form = r.read(env[], core)

# res = c.interpret(rc, env[], form)

loadfile(env, "./core.xprl")
