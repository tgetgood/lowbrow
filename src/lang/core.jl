import Xprl as x
import Xprl.AST as ast
import Xprl.AST: inspect
import Xprl.Compiler: compile, compilein
import Xprl.CPSCompiler: entry
import Xprl.Reader as r
import Xprl.Environment as E

import DataStructures as ds

env = x.Environment.create(x.DefaultEnv.default)
core = r.readall(open("./core.xprl"))
# env = reduce(compile, core; init=def)

# for form in core
#   @info "compiling: " * string(form)
#   global env = compilein(env, form)
# end

f = r.readall(open("./test.xprl"))

exec = x.System.executor()

# res = xSystem.start(exec, f[1])
# x.Eval.eval(print, env, f[1])
