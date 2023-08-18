module shaders

import Vulkan as vk
import DataStructures as ds

function glslc(src, out)
  run(`glslc ../shaders/$src -o $out`)
end

function shader(system, fname)
  (tmp, io) = mktemp()
  close(io)
  glslc(fname, tmp)
  bin = read(tmp)
  vk.unwrap(vk.create_shader_module(get(system, :device), length(bin), bin))
end

export shader
end
