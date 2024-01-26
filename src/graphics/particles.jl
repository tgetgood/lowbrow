import hardware as hw
import resources as rd
import framework as fw
import pipeline as gp
import uniform
import commands
import graphics
import render

import DataStructures as ds
import DataStructures: hashmap, into, emptyvector

import Vulkan as vk

struct Particle
  position::NTuple{2,Float32}
  velocity::NTuple{2,Float32}
  colour::NTuple{4,Float32}
end

function position(r, θ)
  (r * cos(θ), r * sin(θ))
end

function velocity(p)
  x = p[1]
  y = p[2]

  n = sqrt(x^2 + y^2)

  (25.0f-3 / n) .* (x, y)
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
    map(x -> Particle(x[1], velocity(x[1]), tuple(x[2]..., 1.0f0))),
    rand(Float32, 5, count)
  )
end

function init_particle_buffer(system, config)
  n = get(config, :particles)
  particles = init(n)

  buffconfig = ds.hashmap(
    :usage, ds.set(:vertex_buffer, :storage_buffer, :transfer_dst),
    # Need simultaneous readonly access from compute and graphics pipelines if
    # we want async parallelism without copying.
    # TODO: Copying wouldn't be quicker, would it? That's potentially a lot of
    # wasted vram.
    :sharingmode, :concurrent,
    :size, sizeof(Particle) * n,
    :memoryflags, :device_local,
    :queues, [:transfer, :graphics, :compute]
  )

  ssbo = ds.assoc(hw.buffer(system, buffconfig), :verticies, n)

  next = commands.todevicelocal(system, particles, ssbo)

  ds.assoc(ssbo, :wait, [next], :config, buffconfig)
end

frames = 3
nparticles = 2^14

prog = hashmap(
  :name, "VK tutorial particle sim.",
  :version, v"0.1",
  :vulkan_req, ds.hashmap(
    :version, v"1.3"
  ),
  # TODO: Rectify this :device/:device_req split
  :device_req, ds.hashmap(
    :features, ds.hashmap(
      v"1.0", ds.set(:sampler_anisotropy),
      v"1.2", ds.set(:timeline_semaphore),
      v"1.3", [:synchronization2]
    ),
    :extensions, ds.set("VK_KHR_swapchain")
  ),
  :window, hashmap(:width, 1000, :height, 1000),
  :swapchain, hashmap(
    # Triple buffering.
    :images, 3
  ),
  :particles, nparticles,
  :compute, ds.hashmap(
    # inputs and outputs are combined to create descriptor sets.
    :inputs, [ds.hashmap(:type, :ssbo)],
    :outputs, [ds.hashmap(:type, :ssbo)],
    # push constants are... constants. Treat them accordingly.
    :pushconstants, [ds.hashmap(:stage, :compute, :size, 16)],
    # The workgroup size and shader local size are tightly coupled, so this is,
    # in fact, a property of the pipeline, not of any task on it.
    :workgroups, [Int(floor(nparticles / 256)), 1, 1],
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
      :fragment, *(@__DIR__, "/../shaders/particles.frag")
    )
  )
)

function computecommands(config, frame, Δt)
end

function main()
  config = graphics.configure(prog)
  frames = get(config, :concurrent_frames)

  system = graphics.staticinit(config)
  dev = get(system, :device)

  # TODO: The data description of hardware should be its own thing. At the very
  # least a dedicated submap of `system`.
  hardwaredesc = ds.selectkeys(system, [:qf_properties])

  ### rendering

  config = ds.assoc(
    config,
    :vertex_input_state,
    rd.vertex_input_state(Particle, [:position, :colour])
  )

  ### Init graphics pipeline

  system, config = graphics.instantiate(system, config)

  ### Initial sim state

  current_particles = init_particle_buffer(system, config)

  ### compute pipeline

  compute = fw.computepipeline(dev, merge(get(config, :compute), hardwaredesc))

  ### render loop

  renderstate = fw.assemblerender(system, config)

  t1 = time()
  cjoin = Channel()
  gjoin = Channel()

  # while true
    t2 = time()
    dt = Float32(t2 - t1)

    cjoin = fw.thread(
      fw.runcomputepipeline, system, compute, current_particles, [dt]
    )

    t1 = t2

    # Graphics is async mostly for proof of concept. Doesn't accomplish much
    # here

  gjoin = fw.thread() do
    commandpool = hw.commandpool(dev, get(cp, :queuefamily))
    cmd = hw.commandbuffers(dev, commandpool, 1)[1]

    gsig = render.draw(
      system,
      cmd,
      ds.assoc(renderstate, :vertexbuffer, current_particles))

    @async begin
      commands.wait_semaphore(dev, gsig)
      cmd, commandpool
    end

    gsig
  end

    next_particles = take!(cjoin)

  fw.thread() do
    gsig = take!(gjoin)
    commands.wait_semaphores(dev, ds.conj(get(next_particles, :wait), gsig))
    # It's safe to free the particle buffer after the above signals.
    current_particles
  end

    current_particles = next_particles

  # end
end

 main()
