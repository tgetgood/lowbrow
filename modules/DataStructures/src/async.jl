# TODO: mock up clojure's atom and use that to avoid locks in the pub/sub queues
# below..

##### Julia Channels
#
## N.B.: These are not threadsafe in the sense that if you reduce on a channel
## multiple times concurrently the different reductions will get different
## subsets of the value stream and there's no way to tell who will get what.
#
## That might be okay in your use case, but probably isn't.
#
## Also, when reading from multiple channels it waits for a message from each in
## the order they're listed. Since progress can't be made until we have a
## message from each, this isn't so bad.

# TODO: Some sort of subscription system where everybody who is interested in
# the values on a channel gets all the values.
#
# The problem here though: what if one of the consumers is being sluggish? We
# can't buffer indefinitely, and in the case of input streams we can't apply
# back pressure (stuff is happening whether we're ready or not). One option is
# to require all input streams themselves to have buffer and drop policies and
# let backpressure fallback to those.
#
# But that would let one slow consumer limit its peers, and worse, potentially
# prevent them from seeing events that they wouldn't have dropped.

# So it looks like each subscriber needs a dropping policy.

function ireduce(f, init, chs::Channel...)
  try
    vs = [take!(ch) for ch in chs]
    ireduce(f, f(init, vs...), chs...)
  catch e
    if e isa InvalidStateException && !every(x -> x.state === :open, chs)
      init
    else
      throw(e)
    end
  end
end

##### Computed Values
#
# Essentially cells in a spreadsheet, but implemented via transduction

# REVIEW: Do I actually want/need these?

mutable struct ReactiveValue
  @atomic value::Ref{Any}
  @atomic listeners::Ref{Vector}
end

function rv()
  ReactiveValue(Ref(undef))
end

function set!(r::ReactiveValue, v)
  swapfield!(r, :x, v, :monotonic)
  r
end

function deref(r::ReactiveValue)
  getfield(r, :x, :monotonic)
end

##### Streams pub/sub, and integrations with transduction.

abstract type SubStream <: Stream end

struct TailSubStream
  buffer::Base.Vector
end

mutable struct PubStream <: Stream
  @atomic state::Symbol
  @atomic subscriptions::ds.Set
  const lock::ReentrantLock
end

function subscribe(s::PubStream)
  try
    lock(s.lock)
    if s.state === :open
      s.subscriptions = ds.conj(s.subscriptions,
    end
  finally
    unlock(s.lock)
  end
end

end

function close(s::PubStream)
  try
    lock(s.lock)
    s.state = :closed
    map(close, s.subscriptions)
  finally
    unlock(s.lock)
  end
end


# struct Stream
#   buffer::Vector
#   tail::Channel
# end

function tap(ch)
  function(emit)
    function inner()
      v = emit()
      put!(ch, v)
      return v
    end
    function inner(result)
      v = emit(result)
      put!(ch, v)
      close(ch)
      return v
    end
    function inner(result, next...)
      v = emit(result, next...)
      put!(ch, v)
      return v
    end
  end
end

function stream(xform, inputs...; n=32, overflow=:drop_old)
  ch = Channel(n)

end
