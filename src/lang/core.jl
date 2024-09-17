import Xprl as x

import DataStructures as ds

env = x.Env.default

f = x.Reader.readall(env, open("./test.xprl"))

exec = x.System.executor()

res = x.System.start(exec, f[1])
# x.Eval.eval(f[1])
