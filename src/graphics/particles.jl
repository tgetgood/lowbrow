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

function init(count)
  ds.into!(
    Particle[],
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
      :usage, ds.set(:vertex_buffer, :storage_buffer, :transfer_dst),
      :size,  sizeof(Particle) * n,
      :memoryflags, :device_local,
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
        ds.hashmap(:type, :uniform),
        ds.hashmap(:type, :ssbo),
        ds.hashmap(:type, :ssbo)
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
      :topology, :points,
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

  config = ds.update(config, :compute, x -> fw.computepipeline(dev, x))

  compute_bindings = ds.map(i -> [
      deltas[i], ssbos[(i % frames) + 1], ssbos[((i + 1) % frames) + 1]
    ],
    1:frames
  )

  fw.binddescriptors(
    dev,
    ds.getin(config, [:compute, :descriptorsets]),
    compute_bindings
  )

  ### record compute commands once since they never change.

  cqueue = hw.getqueue(system, :compute)

  ccmds = hw.commandbuffers(system, frames, :compute)

  for i in 1:frames
    ccmd = ccmds[i]
    commands.recordcomputation(
      ccmd,
      ds.getin(config, [:compute, :pipeline, :pipeline]),
      ds.getin(config, [:compute, :pipeline, :layout]),
      [ds.getin(config, [:compute, :descriptorsets, :sets])[i]],
    ) do cmd
      vk.cmd_dispatch(cmd, Int(floor(get(config, :particles) / 256)), 1, 1)
    end
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
