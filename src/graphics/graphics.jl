import hardware as hw
import pipeline as gp
import vertex
import commands
import debug
import window
import Vulkan as vk
import DataStructures as ds
import DataStructures: hashmap, emptymap

function configure()
  staticconfig = hashmap(
    :shaders, hashmap(:vert, "ex1.vert", :frag, "ex1.frag"),
    :instance, hashmap(
      :extensions, ["VK_EXT_debug_utils"],
      :validation, ["VK_LAYER_KHRONOS_validation"]
    ),
    :device, hashmap(
      :extensions, ["VK_KHR_swapchain"],
      :validation, ["VK_LAYER_KHRONOS_validation"]
    ),
    :debuglevel, vk.DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT,
    :window, hashmap(:width, 800, :height, 600),
    :swapchain, hashmap(
      :format, vk.FORMAT_B8G8R8A8_SRGB,
      :colourspace, vk.COLOR_SPACE_SRGB_NONLINEAR_KHR,
      :presentmode, vk.PRESENT_MODE_FIFO_KHR,
      :images, 3
    ),
    :concurrent_frames, 2
  )

  ds.reduce((s, f) -> f(s), staticconfig, [
    window.configure,
    debug.configure
  ])
end

function staticinit(config)
  steps = [
    hw.instance,
    debug.debugmsgr,
    window.createwindow,
    window.createsurface,
    hw.createdevice,
    gp.renderpass,
    commands.pool,
    commands.buffers
  ]

  ds.reduce((s, f) -> merge(s, f(config, s)), emptymap, steps)
end

function dynamicinit(config, system)
  vk.device_wait_idle(get(system, :device))

  steps = [
    vertex.bufferfrom(vertex.verticies(vertex.vertex_data)),
    hw.createswapchain,
    hw.createimageviews,
    gp.createpipelines,
    gp.createframebuffers,
  ]

  ds.reduce((s, f) -> merge(s, f(config, s)), system, steps)
end

# FIXME: These should be inside `main`, but it's convenient for repl purposes to
# make them global during development.

config = configure()
system = staticinit(config)
system = dynamicinit(config, system)

@info "Ready"

function main(config, system)
  sigkill = Channel()

  handle = Threads.@spawn begin
    @info "starting main loop"
    buffers = get(system, :commandbuffers)
    i = 0
    frames = 0
    t = time()
    while !window.closep(get(system, :window)) && !isready(sigkill)
      window.poll()

      if !window.minimised(get(system, :window))
        res = commands.draw(config, system, buffers[i+1])

        if res == vk.ERROR_OUT_OF_DATE_KHR ||
          res == vk.SUBOPTIMAL_KHR ||
          get(system, :resizecb)()
          system = dynamicinit(config, system)
        end
        i = (i + 1) % get(config, :concurrent_frames)
      end
   end

    @info "finished main loop; cleaning up"
    vk.device_wait_idle(get(system, :device))
    window.shutdown()

    if isready(sigkill)
      take!(sigkill)
    end

    @info "done"
  end

  @info "returning control"
  return function repl_teardown()
    if istaskstarted(handle) && !istaskdone(handle)
      put!(sigkill, true)
    end
  end
end

repl_teardown = main(config, system)
