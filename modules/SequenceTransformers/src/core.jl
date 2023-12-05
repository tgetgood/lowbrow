abstract type Stream end

abstract type Xf end

abstract type StatefulXf <: Xf end
abstract type PureXf <: Xf end

struct PureCompositeXf <: PureXf
  outer::S where S <: PureXf
  inner::T where T <: PureXf
end

∘(f::PureXf, g::PureXf) = PureCompositeXf(f, g)

struct NoEmission end

none = NoEmission()

abstract type XfIterator end

struct PureXfIterator{F, I} <: XfIterator
  xf::F
  input::I
end

struct MultiEmissionWrapper{T, S}
  vals::Base.Vector{T}
  innerstate::S
end

# function length(i::PureXfIterator)
#   length(i.input)
# end

Base.IteratorSize(::PureXfIterator) = Base.SizeUnknown()

"""
Process one input and possibly get an output.
"""
function step(iter, val)
  out = []
  next(iter.xf)((x -> push!(out, x)), throw, throw)(val)
  return out
end

simpleiter(x, y) = iterate(x, y)
simpleiter(x, _::NoEmission) = iterate(x)

function iterate(iter::PureXfIterator, inputstate=none)
  state = inputstate
  out = []
  while isempty(out)
    inner = simpleiter(iter.input, state)
    if inner === nothing
      return nothing
    else
      v, state = inner
      out = step(iter, v)
    end
  end
  if length(out) === 1
    return out[1], state
  else
    return out[1], (MultiEmissionWrapper(out, state), 2)
  end
end

function iterate(iter::PureXfIterator, wrapped::Tuple{MultiEmissionWrapper, Int})
  state, i = wrapped
  if i > length(state.vals)
    iterate(iter, state.innerstate)
  else
    state.vals[i], (state, i+1)
  end
end

function (x::PureXf)(iter)
  PureXfIterator(x, iter)
end

function into(to, xform, from)
end

function transform(xform, stream)
end

@info "loaded core"
