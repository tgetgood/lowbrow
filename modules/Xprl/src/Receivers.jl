module Receivers

abstract type Receiver end

mutable struct Collector <: Receiver
  const r::Function
  const lock::Threads.SpinLock
  count::Int
  const xs::Vector
end

struct DirectReceiver <: Receiver
  f::Function
end

struct CubbyWrite{T}
  index::Int
  value::T
end

function collector(n, cont)
  Collector(cont, Threads.SpinLock(), 0, Vector(undef, n))
end

function receive(c::Collector, m::CubbyWrite)
  go = false
  try
    lock(c.lock)
    c.xs[m.index] = m.value
    c.count += 1
    if c.count == length(c.xs)
      go = true
    end
  finally
    unlock(c.lock)
  end

  if go
    receive(c.r, c.xs)
  end
end

function receive(r::DirectReceiver, m)
  r.f(m)
end

# simple invocation. Wait for message and apply message as args to f
function simpleinv(f::Function)
  Indirection(f)
end

function receive(f::Function, m)
  f(m)
end


end # module
