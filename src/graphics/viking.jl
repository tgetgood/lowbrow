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
frames = 3

"""
Static description of the program to be run. Pure data. Shouldn't invoke
anything.
"""
prog = ds.hashmap(
  :model_file, *(@__DIR__, "/../../assets/viking_room.obj"),
  :texture_file, *(@__DIR__, "/../../assets/viking_room.png"),
  :concurrent_frames, frames,
  :render, ds.hashmap(
    :shaders, ds.hashmap(
      :vertex, *(@__DIR__, "/../shaders/viking.vert"),
      :fragment, *(@__DIR__, "/../shaders/viking.frag")
    ),
    :inputassembly, ds.hashmap(
      :topology, :triangles
    ),
    :descriptorsets, ds.hashmap(
      :count, frames,
      :bindings, [
        ds.hashmap(
          :usage, vk.DESCRIPTOR_TYPE_UNIFORM_BUFFER,
          :stage, vk.SHADER_STAGE_VERTEX_BIT,
        ),
        ds.hashmap(
          :usage, vk.DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
          :stage, vk.SHADER_STAGE_FRAGMENT_BIT,
        )
      ]
    )
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
  config = graphics.configure(load(prog)); nothing
  frames = get(config, :concurrent_frames)

  system = graphics.staticinit(config)
  dev = get(system, :device)

  texture = textures.textureimage(system, get(config, :texture_file))

  ubos = uniform.allocatebuffers(system, MVP, frames)

  dsets = fw.descriptors(dev, ds.getin(config, [:render, :descriptorsets]))

  bindings = [ubos, texture]

  config = ds.updatein(config, [:render, :descriptorsets], merge, dsets)

  system, config = graphics.instantiate(system, config)

  fw.binddescriptors(
    dev,
    ds.getin(config, [:render, :descriptorsets]),
    ds.into([], map(i -> [ubos[i], texture]), 1:frames)
  )

  config = fw.buffers(system, config)

  config = merge(config, get(config, :render))

  graphics.renderloop(system, config) do i, renderstate

    # TODO: Some sort of framestate abstraction so that we don't have to
    # manually juggle this index.
    uniform.setubo!(ubos[i], timerotate(get(config, :ubo)))

    return renderstate
  end
end

main()
