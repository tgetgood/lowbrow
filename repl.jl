ENV["JULIA_DEBUG"] = Main

function pushonce(path)
  dir = *(@__DIR__, "/", path)
  if indexin(dir, Base.load_path())[1] === nothing
    push!(LOAD_PATH, dir)
  end
end

for i in ["src", "modules", "src/graphics"]
  pushonce(i)
end
