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
  :name, "",
  :version, v"0.0.0",
  :engine, hashmap(
    :version, v"0.0.1",
    :name, "unnamed",
  ),
  :instance, hashmap(
    :vulkan_version, v"1.3"
  ),
  :device, hashmap(
    :features, hashmap(
      # v"1.0", [:sampler_anisotropy],
      v"1.2", [:timeline_semaphore],
      v"1.3", [:synchronization2],
    ),
    # FIXME: logically these are sets. How does vk handle repeats?
    :extensions, ["VK_KHR_swapchain"]
  ),
  :window, hashmap(:width, 1200, :height, 1200),
  :render, hashmap(
    :msaa, 1, # Disabled
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

end # module
