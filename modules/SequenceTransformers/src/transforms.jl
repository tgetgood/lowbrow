## map

struct MapXf{F} <: PureXf
  f::F
end

next(xf::MapXf) = (emit, _, _) -> x -> emit(xf.f(x))
map(f) = MapXf(f)
map(f, xs) = map(f)(xs)

## filter

struct FilterXf{P} <: PureXf
  p::P
end


# TODO: Handle errors from `p`
next(xf::FilterXf) = (emit, _, _) -> x -> xf.p(x) ? emit(x) :

filter(p) = FilterXf(p)
# If I define this only once, Base.filter is used instead.
# Probably a bug in julia.
# TODO: Figure that out.
filter(p) = FilterXf(p)

## flatten

struct FlattenXf <: PureXf end

flatten = FlattenXf()

next(xf::FlattenXf) = (emit, _, _) -> x -> foreach(emit, x)

## partition

struct PartitionXf <: StatefulXf
  n::Int
end

initial_state(xf::PartitionXf) = []

function next(xf::PartitionXf)
  function(emit, pass, error)
    function(state, next)
      if length(state) === xf.n
        emit([], state)
      else
        pass(push!(state, next))
      end
    end
  end
end

function flush(xf::PartitionXf)
  function(emit, _, _)
    function(state)
      if length(state) > 0
        emit(state)
      end
    end
  end
end

scan(f, init) = emit -> (state, next) -> f(state, next)

reduce(f, init, coll) = last(transform(scan(f, init), coll))

@info "loaded transforms"
