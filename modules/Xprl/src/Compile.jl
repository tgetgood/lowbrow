# Reading and compiling should be completely independent modules.
#
# That way when the result of reading an expression depends on the history of
# compiling previous expressions, we have a clean dovetailing and not a ball of
# mud. That's the hope, anyway.
module Compile

import DataStructures as ds
import ..Forms

abstract type Form end

struct SendingForm <: Form
  form::Forms.Form
  receiver
  msg
end

function compile(f::Forms.Pair)
  receiver = compile(f.head)
end

function compile(s::Forms.Symbol)
  compile(ds.get(s.env), s.name)
end

function eval(f::Forms.Pair)
  System.exec(compile(f))
end

end # module
