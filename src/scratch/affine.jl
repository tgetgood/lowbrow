module affine
function rotateX(a)
  c = cos(a)
  s = sin(a)

  return [
    1 0 0 0
    0 c -s 0
    0 s c 0
    0 0 0 1
  ]
end

function rotateY(a)
  c = cos(a)
  s = sin(a)

  return [
    c 0 s 0
    0 1 0 0
   -s 0 c 0
    0 0 0 1
  ]
end

function rotateZ(a)
  c = cos(a)
  s = sin(a)

  return [
    c -s 0 0
    s c 0 0
    0 0 1 0
    0 0 0 1
  ]
end

function translate(v)
  [
    1 0 0 v[1]
    0 1 0 v[2]
    0 0 1 v[3]
    0 0 0 1
  ]
end

function scale(x::Real)
  [
    1 0 0 0
    0 1 0 0
    0 0 1 0
    0 0 0 1/x
  ]
end

end
