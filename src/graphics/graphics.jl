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
    :vk12features, [:timeline_semaphore],
    :vk13features, [:synchronization2],
    # FIXME: logically these are sets. How does vk handle repeats?
    :extensions, ["VK_KHR_swapchain"]
  ),
  :window, hashmap(:width, 1200, :height, 1200),
  :render, hashmap(
    :swapchain, hashmap(
      # TODO: Fallback formats and init time selection.
      :format, vk.FORMAT_B8G8R8A8_SRGB,
      :colourspace, vk.COLOR_SPACE_SRGB_NONLINEAR_KHR,
      :presentmode, vk.PRESENT_MODE_FIFO_KHR,
      :images, 3
    )
  ),
  :concurrent_frames, 3
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

const tear_down = Ref{Function}(() -> nothing)

function configure(prog)
  tear_down[]()

  config = mergeconfig(defaults, prog)

  if get(config, :dev_tools, false)
    config = mergeconfig(
      config,
      merge(
        debug.configure(ds.selectkeys(config, [:dev_tools, :debuglevel])),
        devtooling
      )
    )
  end

  mergeconfig(config, window.configure())
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
    # However, if we start with an empty command pool and allocate on demand,
    # then the current strategy of figuring out what pool to use for everything
    # up front is fine.
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
  ]

  ds.reduce((s, f) -> begin @info f; merge(s, f(s, config)) end, emptymap, steps)
end

function dynamicinit(system, config)
  # FIXME: This is probably why resizing is so unresponsive.
  vk.device_wait_idle(get(system, :device))

  steps = [
    draw.commandbuffers,
    hw.createswapchain,
    hw.createimageviews,
    # TODO: There's so much config in the renderpass, it shouldn't be hardcoded.
    gp.renderpass,
    gp.createframebuffers,

    gp.creategraphicspipeline,
  ]

  ds.reduce((s, f) -> begin @info f; merge(s, f(s, config)) end, system, steps)
end

function instantiate(system, config)

  system = dynamicinit(system, config)

  return system, config
end

function renderloop(framefn, system, config)
  sigkill = Channel()

  tear_down[] = function()
    tear_down[] = () -> nothing
    @info "tearing down running process."
    @async put!(sigkill, true)
    @info "teardown finished."
  end

  renderstate = fw.assemblerender(system, config)

  handle = Threads.@spawn begin
    try
      @info "starting main loop"
      buffers = get(system, :commandbuffers)
      i = 0
      frames = get(config, :concurrent_frames, 1)
      t = time()
      framecounter = 0
      while !isready(sigkill)

        if window.closep(get(system, :window))
          @async put!(sigkill, true)
          break
        end

        i = (i % frames) + 1

        window.poll()

        if !window.minimised(get(system, :window))

          renderstate = framefn(i, renderstate)
          res = draw.draw(system, buffers[i], renderstate)

          if res == vk.ERROR_OUT_OF_DATE_KHR ||
             res == vk.SUBOPTIMAL_KHR ||
             get(system, :resizecb)()

            @info "resized"

            system = dynamicinit(system, config)
          end
        end

        framecounter += 1
      end

      @info isready(sigkill)
      @info "finished main loop; cleaning up"

      @info "Average fps: " * string(round(framecounter / (time() - t)))

      vk.device_wait_idle(get(system, :device))
      window.shutdown()

      config = nothing
      system = nothing
      renderstate = nothing

      if isready(sigkill)
        take!(sigkill)
      end

      tear_down[] = () -> nothing

      # The number of some types of Vulkan objects that can be created is
      # limited. Make sure finalisers run to clean up between iterations.
      GC.gc()

      @info "done"
    catch e
      ds.handleerror(e)
    end
  end
end

end # module
