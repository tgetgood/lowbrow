module pipeline

import Vulkan as vk
import DataStructures: getin

function glslc(src, out)
  run(`glslc ../../shaders/$src -o $out`)
end

function shader(system, fname)
  (tmp, io) = mktemp()
  close(io)
  glslc(fname, tmp)
  bin = read(tmp)
  vk.unwrap(vk.create_shader_module(get(system, :device), length(bin), bin))
end

function create(config, system)
  vert = vk.PipelineShaderStageCreateInfo(
    vk.SHADER_STAGE_VERTEX_BIT,
    shader(system, getin(config, [:shaders, :vert])),
    "vert"
  )
  frag = vk.PipelineShaderStageCreateInfo(
    vk.SHADER_STAGE_FRAGMENT_BIT,
    shader(system, getin(config, [:shaders, :frag])),
    "frag"
  )
  dyn = vk.PipelineDynamicStateCreateInfo([
    vk.DYNAMIC_STATE_SCISSOR,
    vk.DYNAMIC_STATE_VIEWPORT
  ])


end

end
