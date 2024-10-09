import Xprl as x
import Xprl.AST as ast
import Xprl.AST: inspect
import Xprl.Compiler: compile
import Xprl.Reader as r

import DataStructures as ds

def = x.DefaultEnv.default
core = r.readall(open("./core.xprl"))
# env = reduce(compile, core; init=def)

f = r.readall(open("./test.xprl"))

exec = x.System.executor()

# res = xSystem.start(exec, f[1])
# x.Eval.eval(print, env, f[1])
