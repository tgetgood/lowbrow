import Xprl as x
import Xprl.AST as ast
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

function inspect(form::ast.Pair, level=0)
  print(repeat(" ", level))
  println("P")
  inspect(form.head, level+2)
  inspect(form.tail, level+2)
end

function inspect(form::ast.ArgList, level=0)
  print(repeat(" ", level))
  println("L")
  for e in form.args
    inspect(e, level+2)
  end
end

function inspect(form::ast.Immediate, level=0)
  print(repeat(" ", level))
  println("I")
  inspect(form.form, level+2)
end

function inspect(form::ds.Symbol, level=0)
  print(repeat(" ", level))
  println("S["*string(form)*"]")
end

function inspect(form::ast.Application, level=0)
  print(repeat(" ", level))
  println("A")
  inspect(form.head, level+2)
  inspect(form.tail, level+2)
end

function inspect(form::ast.Mu, level=0)
  print(repeat(" ", level))
  println("μ")
  inspect(form.arg, level+2)
  inspect(form.body, level+2)
end

function inspect(form::ast.BuiltIn, level=0)
  print(repeat(" ", level))
  println("F["*string(form)*"]")
end

function inspect(form, level=0)
  print(repeat(" ", level))
  println("V["*string(form)*"]")
end
