import hardware as hw
import resources as rd
import framework as fw
import Commands
import graphics
import render
import Glfw as window
import TaskPipelines as tp
import Sync
import init

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

function initparticles(count)
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
  particles = initparticles(n)

  buffconfig = ds.hashmap(
    :usage, ds.set(:vertex_buffer, :storage_buffer, :transfer_dst),
    :size, sizeof(Particle) * n,
    :memoryflags, :device_local,
    :queues, [:transfer, :graphics, :compute]
  )

  ssbo = hw.buffer(system, buffconfig)

  next = Commands.todevicelocal(system, particles, ssbo)

  ds.assoc(ssbo, :wait, [next], :config, buffconfig)
end

frames = 3
nparticles = 2^12

prog = hashmap(
  :name, "VK tutorial particle sim.",
  :version, v"0.1",
  :vulkan_req, ds.hashmap(
    :version, v"1.3"
  ),
  # TODO: Rectify this :device/:device_req split
  :device, ds.hashmap(
    :features, ds.hashmap(
      v"1.2", ds.set(:timeline_semaphore),
      v"1.3", [:synchronization2]
    ),
    :extensions, ds.set("VK_KHR_swapchain")
  ),
  :dev_tools, true,
  :window, hashmap(:width, 1000, :height, 1000),
  :particles, nparticles,
  :pipelines, ds.hashmap(
    :sim, ds.hashmap(
      # inputs and outputs are combined to create descriptor sets.
      :inputs, [ds.hashmap(:type, :ssbo)],
      :outputs, [ds.hashmap(
        :type, :ssbo,
        :usage, ds.set(:vertex_buffer, :storage_buffer),
        :size, sizeof(Particle) * nparticles,
        :memoryflags, :device_local,
        :queues, [:graphics, :compute]
      )],
      :type, :compute,
      # push constants are... constants. Treat them accordingly.
      :pushconstants, ds.hashmap(:size, 16),
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
      :samples, 1,
      :type, :graphics,
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
)

function load(config)
  ds.associn(
    config,
    [:pipelines, :render, :vertex_input_state],
    rd.vertex_input_state(Particle, [:position, :colour])
  )
end

function main()
  window.shutdown()

  system, config = init.setup(load(prog), window)

  # REVIEW: building the pipelines is not in the purview of init, but it this is
  # just boilerplate that should be wrapped up somehow.
  pipelines = tp.buildpipelines(system, config)
  system = ds.assoc(system, :pipelines, pipelines)

  nparticles = config.particles

  dev = system.device

  ### Initial sim state

  current_particles = init_particle_buffer(system, config)

  ### pipelines

  compute = system.pipelines.sim

  graphics = system.pipelines.render

  ### render loop

  t1 = time()
  t0 = t1

  iters = 10
  terminate() = begin iters -= 1; iters < 0 end

  while true
    window.poll()

    t2 = time()
    dt = Float32(t2 - t1)
    t1 = t2

    comp = tp.run(compute, ([current_particles], [dt]))

    gout = tp.run(graphics, ds.hashmap(:vertexbuffer,
      ds.assoc(current_particles, :verticies, nparticles)))

    next_particles = take!(comp)[1]
    current_particles = next_particles

    gsig = take!(gout)

    if gsig === :closed
      break
    elseif gsig === :skip
      sleep(0.08)
    else
      @async begin
        Sync.wait_semaphores(dev, ds.conj(get(next_particles, :wait), gsig))
        # It's safe to free the particle buffer after the above signals.
        current_particles
      end
    end
  end

  tp.teardown(compute)
  tp.teardown(graphics)
end

main()
