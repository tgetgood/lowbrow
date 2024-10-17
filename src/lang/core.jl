import Xprl as x
import Xprl.AST as ast
import Xprl.AST: inspect
import Xprl.System as sys
import Xprl.C4 as c
import Xprl.Reader as r

import DataStructures as ds

env = Ref{Any}(x.DefaultEnv.default)
core = r.readall(open("./core.xprl"))

function eset(e)
  env[] = e
  nothing
end

rc = sys.withcc(
  ds.emptymap,
  :env, eset,
  :return, inspect
)

for form in core
  @info "compiling: " * string(form)
  c.interpret(rc, env[], form)
end

f = r.readall(open("./test.xprl"))
