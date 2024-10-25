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

# function readeval(conts, env, stream)
#   form = r.read(env, stream)
#   if form !== nothing
#     @info "Compiling:" * string(form)
#     c.interpret(conts, env, form)
#   end
# end

# function evalseq(root, envvar, stream)
#   function next(x)
#     if x !== nothing
#       inspect(x)
#       evalseq(root, envvar, stream)
#     else
#       @info "EOF"
#     end
#   end

#   readeval(
#     sys.withcc(root, :return, next, :env, x -> envvar[] = x),
#     envvar[],
#     stream
#   )
# end

# """
# Reads file `fname` and merges it into the given environment.
# """
# function loadfile(envvar, fname)
#   stream = r.tostream(open(fname))

#   evalseq(rc, envvar, stream)
# end

# form = r.read(env[], core)

# res = c.interpret(rc, env[], form)

# loadfile(env, "./core.xprl")
