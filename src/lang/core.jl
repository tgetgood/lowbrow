import Xprl as x

import DataStructures as ds

env = x.DefaultEnv.default

f = x.Reader.readall(open("./test.xprl"))

exec = x.System.executor()

# res = xSystem.start(exec, f[1])
x.Eval.eval(env, f[1])
