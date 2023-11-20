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

frames = 3

prog = hashmap(
  :name, "VK tutorial particle sim.",
  :version, v"0.1",
  :vulkan_req, ds.hashmap(
    :version, v"1.3"
  ),
  :device_req, ds.hashmap(
    :features, ds.hashmap(
      v"1.0", ds.set(:sampler_anisotropy),
      v"1.2", ds.set(:timeline_semaphore)
    ),
    :extensions, ds.set("VK_KHR_swapchain", "VK_KHR_timeline_semaphore")
  ),
  :concurrent_frames, frames,
  :particles, 2^14,
  :compute, ds.hashmap(
    :descriptorsets, ds.hashmap(
      :count, frames,
      :bindings, [
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
    ),
    :shader, ds.hashmap(
      :stage, :compute,
      :file, *(@__DIR__, "/../shaders/particles.comp"),
      # FIXME: Currently no caching is implemented.
      :cache, true
    )
  ),
  :render, ds.hashmap(
    :inputassembly, ds.hashmap(
      :topology, :lines,
      :restart, false
    ),
    :shaders, hashmap(
      :vertex, *(@__DIR__, "/../shaders/particles.vert"),
      :fragment, *(@__DIR__, "/../shaders/particles.frag"),
    )
  )
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

  cpconfig = get(config, :compute)

  cpconfig = ds.update(
    cpconfig, :descriptorsets, x -> merge(x, fw.descriptors(dev, x))
  )

  compute_bindings = ds.map(i -> [
      deltas[i], ssbos[(i % frames) + 1], ssbos[((i + 1) % frames) + 1]
    ],
    1:frames
  )

  fw.binddescriptors(dev, get(cpconfig, :descriptorsets), compute_bindings)

  cpconfig = ds.assoc(cpconfig, :pipeline, gp.computepipeline(dev, cpconfig))

  config = ds.assoc(config, :computeparticles, cpconfig)

  ### record compute commands once since they never change.

  cqueue = hw.getqueue(system, :compute)

  ccmds = hw.commandbuffers(system, frames, :compute)

  for i in 1:frames
    ccmd = ccmds[i]
    vk.begin_command_buffer(ccmd, vk.CommandBufferBeginInfo())

    vk.cmd_bind_pipeline(
      ccmd,
      vk.PIPELINE_BIND_POINT_COMPUTE,
      ds.getin(cpconfig, [:pipeline, :pipeline])
    )

    vk.cmd_bind_descriptor_sets(
      ccmd,
      vk.PIPELINE_BIND_POINT_COMPUTE,
      ds.getin(cpconfig, [:pipeline, :layout]),
      0,
      [ds.getin(cpconfig, [:descriptorsets, :sets])[i]],
      [],
    )

    vk.cmd_dispatch(ccmd, Int(floor(get(config, :particles) / 256)), 1, 1)

    vk.end_command_buffer(ccmd)
  end

  csemcounters::Vector{UInt} = map(x->UInt(0), 1:frames)

  csems = map(x -> vk.unwrap(vk.create_semaphore(
      get(system, :device),
      vk.SemaphoreCreateInfo(
        next=vk.SemaphoreTypeCreateInfo(vk.SEMAPHORE_TYPE_TIMELINE, x)
      )
    )), csemcounters)

  ### run

  t1 = time()

  graphics.renderloop(system, config) do i, renderstate
    t2 = time()
    uniform.setubo!(deltas[i], Float32(t2-t1))
    t1 = t2

    csem = csems[i]

    # wait on cpu, signal on gpu. Not the most efficient, but with multiple
    # frames in flight it should be just fine.
    vk.wait_semaphores(
      get(system, :device),
      vk.SemaphoreWaitInfo([csem], [csemcounters[i]]),
      typemax(UInt)
    )

    vk.queue_submit(cqueue, [vk.SubmitInfo([],[],[ccmds[i]], [csem];
      next=vk.TimelineSemaphoreSubmitInfo(
        signal_semaphore_values=[csemcounters[i]+1]
      )
    )])

    csemcounters[i] += 1

    return ds.assoc(renderstate, :vertexbuffer, ssbos[i])
  end
end

main()
