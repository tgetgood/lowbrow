import DataStructures as ds
import uniform
import model
import textures
import resources as rd

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

  t = time()
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
config = ds.hashmap(
  :model_file, *(@__DIR__, "/../../assets/viking_room.obj"),
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
  ),
  :bindings, [
    ds.hashmap(
      :type, :uniform,
      :name, :projection,
      :loader, ubo,
      # magically applies `f` to current binding and updates
      :update, timerotate,
      :allocate, uniform.allocatebuffers,
      :eltype, MVP,
      :size, 1,
      :usage, vk.DESCRIPTOR_TYPE_UNIFORM_BUFFER,
      :stage, vk.SHADER_STAGE_VERTEX_BIT
    ),
    ds.hashmap(
      :type, :texture,
      :name, :texture,
      :usage, vk.DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
      :stage, vk.SHADER_STAGE_FRAGMENT_BIT,
      :allocate, textures.textureimage,
      :texture_file, *(@__DIR__, "/../../assets/viking_room.png"),
    )
  ]
)

function main()
  state = graphics.configure(load(config))

  system, state = graphics.instantiate(state)

  ubobuff = ds.getin(state, [:vbuffers, :projection])

  graphics.renderloop(system, state) do i, renderstate

    # TODO: Some sort of framestate abstraction so that we don't have to
    # manually juggle this index.
    uniform.setubo!(ubobuff[i], timerotate(get(state, :ubo)))
  end
end

repl_teardown = main()
