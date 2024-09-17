module System

import ..Receivers
import ..Forms

import DataStructures as ds

abstract type Emission end

struct Delivery <: Emission
  receiver
  message
end

struct EmissionList <: Emission
  xs::Vector{Delivery}
end

function emit(rec::Receivers.Receiver, msg)
  Delivery(rec, msg)
end

function emit(r1::Receivers.Receiver, m1, r2::Receivers.Receiver, m2)
  [Delivery(r1, m1), Delivery(r2, m2)]
end

function emit(m::ds.Map)
  throw("not implemented")
end

struct Executor
  stack::Vector
end

function go!(m::Delivery)
  Receivers.receive(m.receiver, m.message)
end

function pushngo!(exec::Executor, m::Delivery)
  # If there's only one emission, step into it directly.
  go!(m)
end

function pushngo!(exec::Executor, ms::EmissionList)
  m = popfirst!(ms)
  append!(exec.stack)
  go!(m)
end

function pushngo!(exec::Executor, m::Any)
  go!(exec.stack.pop!())
end

function start(exec, receiver, msg)
  emissions = Receivers.receive(receiver, msg)
  pushngo!(exec, emissions)
end

function start(exec::Executor, f::Forms.ListForm)
  start(exec, f.head, f.tail)
end

function executor()
  Executor([])
end

end # module
