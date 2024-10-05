import Xprl as x
import Xprl.Runtime as rt

import DataStructures as ds

env = x.DefaultEnv.default

f = x.Reader.readall(open("./test.xprl"))

exec = x.System.executor()

# res = xSystem.start(exec, f[1])
x.Eval.eval(print, env, f[1])

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

function inspect(form, level=0)
  print(repeat(" ", level))
  println("V["*string(form)*"]")
end

cwalk(x) = x
cwalk(x::ds.Immediate) = invoke(x.content)

valtype(x::Int) = true
valtype(x::String) = true
valtype(x::Bool) = true
valtype(x::ds.Vector) = ds.every(valtype, x)
valtype(x) = false

function invoke(x)
  if valtype(x)
    x
  else
   ds.Immediate(x)
  end
end

function invoke(x::ds.Pair)
  rt.Application(ds.Immediate(x.head), x.tail)
end

function treereduce(form)
  res = ds.postwalk(cwalk, form)
  if res == form
    res
  else
    treereduce(res)
  end
end
