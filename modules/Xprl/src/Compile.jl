# Reading and compiling should be completely independent modules.
#
# That way when the result of reading an expression depends on the history of
# compiling previous expressions, we have a clean dovetailing and not a ball of
# mud. That's the hope, anyway.
module Compile

import ..Forms

function compile(f::Forms.Form)
  receiver = compile(f.head)
end

end # module
