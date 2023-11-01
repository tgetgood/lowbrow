module graphics

import hardware as hw
import pipeline as gp
import render as draw
import debug
import window
import framework as fw

import Vulkan as vk
import DataStructures as ds
import DataStructures: hashmap, emptymap

VS = Union{Vector, ds.Vector}

mergeconfig(x, y) = y
mergeconfig(x::ds.Map, y::ds.Map) = ds.mergewith(mergeconfig, x, y)
mergeconfig(x::VS, y::VS) = ds.into(y, x)


defaults = hashmap(
  :dev_tools, true,
  :debuglevel, vk.DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT,
  :device, hashmap(
    :features, [:sampler_anisotropy],
    # FIXME: logically these are sets. How does vk handle repeats?
    :extensions, ["VK_KHR_swapchain", "VK_KHR_shader_float16_int8"]
  ),
  :window, hashmap(:width, 1600, :height, 1200),
  :swapchain, hashmap(
    # TODO: Fallback formats and init time selection.
    :format, vk.FORMAT_B8G8R8A8_SRGB,
    :colourspace, vk.COLOR_SPACE_SRGB_NONLINEAR_KHR,
    :presentmode, vk.PRESENT_MODE_FIFO_KHR,
    :images, 2
  ),
  :concurrent_frames, 2
)

devtooling = ds.hashmap(
  :instance, hashmap(
    :extensions, ["VK_EXT_debug_utils"],
    :validation, ["VK_LAYER_KHRONOS_validation"]
  ),
  :device, hashmap(
    :validation, ["VK_LAYER_KHRONOS_validation"]
  )
)

function configure(prog)
  devcfg = ds.transduce(
    map(x -> ds.selectkeys(x, [:dev_tools, :debuglevel])),
    merge,
    ds.emptymap,
    [defaults, prog]
  )

  devmode = get(devcfg, :dev_tools, false)

  ds.reduce(
    mergeconfig,
    defaults,
    ds.vector(
      # Only configure logging in dev mode.
      devmode ? debug.configure(devcfg) : ds.emptymap,
      devmode ? devtooling : ds.emptymap,

      window.configure(),
      prog # Input potentially overrides everything. What could go wrong?
    )
  )
end

function staticinit(config)
  steps = [
    hw.instance,
    debug.debugmsgr,
    window.createwindow,
    window.createsurface,

    # REVIEW: Decide which kinds of queues we're going to need before we create
    # the device, or just create all of the queues I might need and a command
    # pool for each? Right now the latter is simpler, but it might not be a good
    # choice.
    hw.createdevice,

    # This ^ is the core setup.
    #
    # We need to break the config up logically so that we perform 3
    # rounds of negotiations.
    # 1. Negotiate the instance, AKA choose the best API version and
    # extensions that are available. And make sure we can open a window and
    # create a render surface.
    # 2. Negotiate (and possibly choose) the physical and logical devices based
    # on the desired and available extentions. Then choose the best config
    # available.

    hw.createcommandpools,
    # hw.createdescriptorpools,
    # gp.shaders,
    # model.load,
    draw.commandbuffers,
    # uniform.allocatebuffers,
    # textures.textureimage,
    # textures.allocatesets,
  ]

  ds.reduce((s, f) -> begin @info f; merge(s, f(s, config)) end, emptymap, steps)
end

function dynamicinit(system, config)
  # FIXME: This is probably why resizing is so unresponsive.
  vk.device_wait_idle(get(system, :device))

  steps = [
    hw.createswapchain,
    hw.createimageviews,
    # TODO: There's so much config in the renderpass, it shouldn't be hardcoded.
    gp.renderpass,
    gp.creategraphicspipeline,
    gp.createframebuffers,
  ]

  ds.reduce((s, f) -> begin @info f; merge(s, f(s, config)) end, system, steps)
end

# TODO: This is where the config negotiation will happen
function instantiate(config)
  system = staticinit(config)

  config = fw.descriptors(system, config)

  system = dynamicinit(system, config)

  config = fw.buffers(system, config)

  fw.binddescriptors(system, config)

  return system, config
end

tear_down = Ref{Function}(() -> nothing)

function renderloop(framefn, system, config)
  tear_down[]()

  sigkill = Channel()

  # The number of some types of Vulkan objects that can be created is
  # limited. Make sure finalisers run to clean up between iterations.
  GC.gc()

  configcache = config
  renderstate = fw.assemblerender(system, config)

  handle = Threads.@spawn begin
    try
      @info "starting main loop"
      buffers = get(system, :commandbuffers)
      i = 0
      frames = get(config, :concurrent_frames, 1)
      t = time()
      while !window.closep(get(system, :window)) && !isready(sigkill)
        i = (i % frames) + 1

        window.poll()

        if config !== configcache
          renderstate = vertex.assemblerender(system, config)
          configcache = config
        end

        if !window.minimised(get(system, :window))

          framefn(i, renderstate)
          res = draw.draw(system, buffers[i], renderstate)

          if res == vk.ERROR_OUT_OF_DATE_KHR ||
             res == vk.SUBOPTIMAL_KHR ||
             get(system, :resizecb)()

            system = ds.assoc(system, :window_size, window.size(get(system, :window)))
            system = dynamicinit(system, config)
          end
        end
      end

      @info "finished main loop; cleaning up"
      vk.device_wait_idle(get(system, :device))
      window.shutdown()

      if isready(sigkill)
        take!(sigkill)
      end

      @info "done"
    catch e
      showerror(stderr, e)
      show(stderr, "text/plain", stacktrace(catch_backtrace()))
    end
  end

  @info "returning control"
  tear_down[] = function repl_teardown()
    if istaskstarted(handle) && !istaskdone(handle)
      put!(sigkill, true)
    end
  end
end

end # module
