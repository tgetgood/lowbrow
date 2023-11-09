import hardware as hw
import resources as rd
import framework as fw
import pipeline as gp
import uniform
import commands
import graphics

import DataStructures as ds
import DataStructures: hashmap, into, emptyvector

import Vulkan as vk

struct Particle
  position::NTuple{2, Float32}
  velocity::NTuple{2, Float32}
  colour::NTuple{4, Float32}
end

function position(r, θ)
  (r*cos(θ) , r*sin(θ))
end

function velocity(p)
  x = p[1]
  y = p[2]

  n = sqrt(x^2+y^2)

  (25f-3/n) .* (x, y)
end

function init(count)::Vector{Particle}
  ds.into(
    ds.emptyvector,
    ds.partition(5)
    ∘
    map(x -> (sqrt(x[1]) * 25.0f-2, x[2] * 2pi, x[3:5]))
    ∘
    map(x -> (position(x[1], x[2]), x[3]))
    ∘
    map(x -> Particle(x[1], velocity(x[1]), tuple(x[2]..., 1f0))),
    rand(Float32, 5, count)
  )
end

function particle_buffers(system, config)
  n = get(config, :particles)
  particles = init(n)

  ssbos = into(
    emptyvector,
    map(_ -> hw.buffer(system, ds.hashmap(
      :usage, vk.BUFFER_USAGE_VERTEX_BUFFER_BIT |
              vk.BUFFER_USAGE_TRANSFER_DST_BIT |
              vk.BUFFER_USAGE_STORAGE_BUFFER_BIT,
      :size,  sizeof(Particle) * n,
      :memoryflags, vk.MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
      :queues, [:transfer, :graphics, :compute]
    )))
    ∘
    map(x -> ds.assoc(x, :verticies, n))
    ,
    1:get(config, :concurrent_frames)
    )

  commands.todevicelocal(system, particles, ssbos...)

  ssbos
end

prog = hashmap(
  :particles, 2^14,
  :compute, ds.hashmap(
    :shader, "particles.comp"
  ),
  :shaders, hashmap(
    :vertex, "particles.vert",
    :fragment, "particles.frag",
  ),
)

function main()
  config = graphics.configure(prog)
  frames = get(config, :concurrent_frames)

  system = graphics.staticinit(config)
  dev = get(system, :device)

  ### rendering

  config = ds.assoc(
    config,
    :vertex_input_state,
    rd.vertex_input_state(Particle, [:position, :colour])
  )

  ### Init graphics pipeline

  system, config = graphics.instantiate(system, config)

  ### Bound buffers

  deltas = uniform.allocatebuffers(system, Float32, frames)

  ssbos = particle_buffers(system, config)

  ### compute

  dsets = fw.descriptors(
    dev,
    frames,
    [
      ds.hashmap(
        :usage, vk.DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        :stage, vk.SHADER_STAGE_COMPUTE_BIT
      ),
      ds.hashmap(
        :usage, vk.DESCRIPTOR_TYPE_STORAGE_BUFFER,
        :stage, vk.SHADER_STAGE_COMPUTE_BIT
      ),
      ds.hashmap(
        :usage, vk.DESCRIPTOR_TYPE_STORAGE_BUFFER,
        :stage, vk.SHADER_STAGE_COMPUTE_BIT
      )
    ]
  )

  compute_bindings = ds.map(i -> [
      deltas[i], ssbos[(i % frames) + 1], ssbos[((i + 1) % frames) + 1]
    ],
    1:frames
  )

  fw.binddescriptors(dev, dsets, compute_bindings)

  playout = vk.unwrap(vk.create_pipeline_layout(
    dev, [get(dsets, :descriptorsetlayout)], []
  ))

  cp = vk.unwrap(vk.create_compute_pipelines(
    dev,
    [vk.ComputePipelineCreateInfo(
      # FIXME: Shaders have different assumptions here.
      gp.shader(dev, ds.getin(config, [:compute, :shader]), :compute),
      playout,
      0
    )]
  ))[1][1]

  ### run

  t1 = time()

  graphics.renderloop(system, config) do i, renderstate
    # TODO: Some sort of framestate abstraction so that we don't have to
    # manually juggle this index.
    t2 = time()
    uniform.setubo!(deltas[i], Float32(t2-t1))
    t1 = t2

    commands.cmdseq(system, :compute) do cmd
      vk.cmd_bind_pipeline(cmd, vk.PIPELINE_BIND_POINT_COMPUTE, cp)

      vk.cmd_bind_descriptor_sets(
        cmd,
        vk.PIPELINE_BIND_POINT_COMPUTE,
        playout,
        0,
        [get(dsets, :descriptorsets)[(i%frames)+1]],
        [],
      )

      vk.cmd_dispatch(cmd, Int(floor(get(config, :particles) / 256)), 1, 1)
    end

    vb = ssbos[((i+1) % frames) + 1]

    return ds.assoc(renderstate, :vertexbuffer, vb)
  end
end

main()
