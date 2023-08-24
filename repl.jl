ENV["JULIA_DEBUG"] = "all"

function pushonce(path)
  dir = *(@__DIR__, "/", path)
  if indexin(dir, Base.load_path())[1] === nothing
    push!(LOAD_PATH, dir)
  end
end

map(pushonce, ["src", "modules", "src/graphics"])
