import Xprl as x
import Xprl.Runtime as rt

import DataStructures as ds

env = x.DefaultEnv.default

f = x.Reader.readall(open("./test.xprl"))

exec = x.System.executor()

# res = xSystem.start(exec, f[1])
# x.Eval.eval(print, env, f[1])

function inspect(form::ds.Pair, level=0)
  print(repeat(" ", level))
  println("P")
  inspect(form.head, level+2)
  inspect(form.tail, level+2)
end

function inspect(form::ds.ArgList, level=0)
  print(repeat(" ", level))
  println("L")
  for e in form.contents
    inspect(e, level+2)
  end
end

function inspect(form::ds.Immediate, level=0)
  print(repeat(" ", level))
  println("I")
  inspect(form.content, level+2)
end

function inspect(form::ds.Symbol, level=0)
  print(repeat(" ", level))
  println("S["*string(form)*"]")
end

function inspect(form::rt.Application, level=0)
  print(repeat(" ", level))
  println("A")
  inspect(form.head, level+2)
  inspect(form.tail, level+2)
end

function inspect(form::rt.Mu, level=0)
  print(repeat(" ", level))
  println("μ")
  inspect(form.argsym, level+2)
  inspect(form.body, level+2)
end

function inspect(form::x.Eval.BuiltIn, level=0)
  print(repeat(" ", level))
  println("F["*string(form)*"]")
end

# function inspect(form::x.Eval.CreateMu, level=0)
#   print(repeat(" ", level))
#   println("F[μ]")
# end

function inspect(form, level=0)
  print(repeat(" ", level))
  println("V["*string(form)*"]")
end

eval(env, form) = x.Eval.eval(env, form)

compile = x.Eval.compile
