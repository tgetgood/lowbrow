import DataStructures as ds
import uniform
import model
import textures
import resources as rd
import framework as fw
import graphics

import Vulkan as vk

##### Projection Uniform Buffer Object

struct MVP
  model::NTuple{16,Float32}
  view::NTuple{16,Float32}
  projection::NTuple{16,Float32}
end

function ubo(x)
  MVP(
    tuple(get(x, :model)...),
    tuple(get(x, :view)...),
    tuple(get(x, :projection)...)
  )
end

function configureprojection(config)
  ds.update(config, :ubo, ubo)
end

function timerotate(u)
  t = time() / 2
  c = cos(t)
  s = sin(t)

  p::Matrix{Float32} = [
    c 0 s 0
    0 1 0 0
    -s 0 c 0.6
    0 0 0 1
  ]

  MVP(u.model, u.view, tuple(p...))
end

function load(config)
  merge(
    ds.update(config, :ubo, ubo),
    model.load(config),
    ds.hashmap(:vertex_input_state, rd.vertex_input_state(model.Vertex))
  )
end

##### Main definition

x = pi/3

"""
Static description of the program to be run. Pure data. Shouldn't invoke
anything.
"""
prog = ds.hashmap(
  :model_file, *(@__DIR__, "/../../assets/viking_room.obj"),
  :texture_file, *(@__DIR__, "/../../assets/viking_room.png"),
  :shaders, ds.hashmap(
    :vertex, "viking.vert",
    :fragment, "viking.frag"
  ),
  :ubo, ds.hashmap(
    :model, [
      1 0 0 0
      0 1 0 0
      0 0 1 0
      0 0 0 1
    ],
    :view, [
      1 0 0 0
      0 cos(x) -sin(x) 0
      0 sin(x) cos(x) 0
      0 0 0 1
    ],
    :projection, [
      1 0 0 0
      0 1 0 0
      0 0 1 0
      0 0 0 1
    ]
  )
)

function main()
  config = graphics.configure(load(prog))

  system = graphics.staticinit(config)

  texture = textures.textureimage(system, get(config, :texture_file))

  ubos = uniform.allocatebuffers(system, MVP, get(config, :concurrent_frames))

  bindings = [
    ds.hashmap(
      :usage, vk.DESCRIPTOR_TYPE_UNIFORM_BUFFER,
      :stage, vk.SHADER_STAGE_VERTEX_BIT,
      :buffer, ubos
    ),
    ds.hashmap(
      :usage, vk.DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
      :stage, vk.SHADER_STAGE_FRAGMENT_BIT,
      :buffer, texture
    )
  ]

  config = ds.assoc(config, :bindings, bindings)

  system, config = graphics.instantiate(system, config)

  config = fw.buffers(system, config)

  graphics.renderloop(system, config) do i, renderstate

    # TODO: Some sort of framestate abstraction so that we don't have to
    # manually juggle this index.
    uniform.setubo!(ubos[i], timerotate(get(config, :ubo)))

    return renderstate
  end
end

repl_teardown = main()
