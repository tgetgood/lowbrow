import Xprl as x
import Xprl.AST as ast
import Xprl.AST: inspect
import Xprl.CPSCompiler: entry, withcc, compile, context
import Xprl.Reader as r

import DataStructures as ds

env = Ref{Any}(x.DefaultEnv.default)
core = r.readall(open("./core.xprl"))
# env = reduce(compile, core; init=def)

function eset(e)
  env[] = e
  nothing
end

replchannels = withcc(
  ds.emptymap,
  :env, eset,
  :return, inspect
)

function evallist(env, list, i=1)
  if i == length(list)
    nothing
  else
    function next(f)
      evalist(env, list, i+1)
    end
    form = list[i]
    @info "compiling: " * string(form)
    entry(withcc(replchannels, :return, next), env[], form)
  end
end

# evallist(env, core)

for form in core
  @info "compiling: " * string(form)
  entry(replchannels, env[], form)
end

f = r.readall(open("./test.xprl"))

exec = x.System.executor()

# res = xSystem.start(exec, f[1])
# x.Eval.eval(print, env, f[1])
