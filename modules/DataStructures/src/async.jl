mutable struct Atom
  @atomic value
end

function deref(a::Atom)
  getfield(a, :value, :monotonic)
end

"""
Doesn't necessarily set the atom. Check the return value.
"""
function trycas!(a::Atom, current, next)
  replacefield!(a, :value, current, next, :monotonic)
end

"""
Atomically set `a`'s value to f(deref(a), args...).

Spins if `a` is changed while `f` is being computed (cas semantics).

N.B.: this could get ugly if lots of threads are changing `a` simultaneously,
but if contention is low and `f` is fast, it can be very efficient.

Also note that `f` will, in general, be invoked multiple times, so it should be
pure.
"""
function swap!(a::Atom, f, args...)
  i = 0
  # REVIEW: is 2^16 too many tries before failing? Probably.
  # TODO: backoff
  while i < 2^16
    i += 1
    current = deref(a)
    next = f(current, args...)
    res = trycas!(a, current, next)
    if res.success
      return next
    end
  end
  throw("Too much contention in atom, aborting to avoid deadlock.")
end

function reset!(a::Atom, value)
  setfield!(a, :value, value, :monotonic)
end

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

function ireduce(f, init, ch::Channel)
  try
    ireduce(f, f(init, take!(ch)), ch)
  catch e
    if e isa InvalidStateException && ch.state === :closed
      init
    else
      throw(errorchain(e))
    end
  end
end

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

##### Streams pub/sub, and integrations with transduction.

abstract type SubStream <: Stream end

struct TailSubStream <: SubStream
  ch::Channel
end

function take!(s::TailSubStream)
  take!(s.ch)
end

function put!(s::TailSubStream, x)
  lock(s.ch) do
    if s.ch.n_avail_items === s.ch.sz_max
      take!(s.ch)
    end

    put!(s.ch, x)
  end
end

function close(s::TailSubStream)
  close(s.ch)
end

function sub(; buffer = 32, drop=:oldest)
  if drop === :oldest
    TailSubStream(Channel(buffer))
  else
    throw("not implemented")
  end
end

struct PubStream <: Stream
  state::Atom
end

closedp(s::Channel) = s.state === :closed
closedp(s::SubStream) = s.ch.state === :closed
closedp(s::PubStream) = get(deref(s.state), :state) === :closed

function pub()
  PubStream(Atom(hashmap(:state, :open, :subscribers, emptyset)))
end

function put!(s::PubStream, x)
  v = deref(s.state)
  cleanup = false
  if get(v, :state) === :open
    reduce((_, c) -> begin
        if closedp(c)
           cleanup = true
        else
          put!(c, x)
        end
      end,
      0, get(v, :subscribers)
    )

    if cleanup
      swap!(s.state, update, :subscribers, subs -> remove(closedp, subs))
    end
    return nothing
  else
    throw(InvalidStateException("channel is closed.", get(v, :state)))
  end
end

function subscribe(p::PubStream; buffer = 32, drop = :oldest)
  s = sub(;buffer, drop)
  swap!(p.state, update, :subscribers, conj, s)
  return s
end

function close(s::PubStream)
  v = swap!(s.state, assoc, :state, :closed)
  map(close, get(v, :subscribers))
end

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

ChannelLike = Union{Channel, PubStream, SubStream}

# Helpers to treat all these channellikes the same.
listener(ch::Channel) = ch
listener(s::SubStream) = s.ch
listener(p::PubStream) = subscribe(p)

function stream(xform, streams::PubStream...)
  output = pub()

  inputs = map(subscribe, streams)

  t = Threads.@spawn begin
    try
      transduce(xform ∘ tap(output), lastarg, 0, inputs...)
    catch e
      handleerror(e)
    end
  end

  # How does one implement `bind` for custom channel like types?
  # bind(output, t)

  return output
end

function ireduce(f, init, s::PubStream)
  ireduce(f, init, subscribe(s))
end

function ireduce(f, init, ss::PubStream...)
  ireduce(f, init, map(x -> subscribe(x).ch, ss)...)
end

function ireduce(f, init, s::SubStream)
  ireduce(f, init, s.ch)
end

function ireduce(f, init, s::SubStream...)
  ireduce(f, init, map(x -> x.ch, s)...)
end
