module eventsystem

mutable struct EventStream
  listeners::Vector
end

const click = Channel(64)
const move = Channel(typemax(Int))
const scroll = EventStream([])

function mousepositionupdate(x::Float64, y::Float64)
  put!(move, (x, y))
end

function mouseclickupdate(event)
  put!(click, event)
end

function mousescrollupdate(x::Float64, y::Float64)
end

function register(stream, n = 0)
  ch = Channel(n)
  push!(stream.listeners, ch)
  return ch
end

function jitreduce(f, acc, streams...)
  vals = NTuple{length{streams}, Any}(undef)

  channels = map(register, streams)


end

end
