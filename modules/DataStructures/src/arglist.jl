struct ArgList <: Sequential
  contents::Vector
end

function arglist(xs)
  ArgList(into(emptyvector, xs))
end

function count(x::ArgList)
  count(x.contents)
end

function iterate(x::ArgList)
  iterate(x.contents)
end

function eltype(x::ArgList)
  eltype(x.contents)
end

function first(x::ArgList)
  first(x.contents)
end

function rest(x::ArgList)
  rest(x.contents)
end

function ireduce(x::ArgList)
  ireduce(x.contents)
end

function Base.:(==)(x::ArgList, y::ArgList)
  x.contents == y.contents
end

const arglistbasehash = hash("#ArgList")

function hash(x::ArgList)
  xor(arglistbasehash, hash(x.contents))
end

function string(x::ArgList)
  "#"*string(x.contents)
end
