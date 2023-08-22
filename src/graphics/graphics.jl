import hardware as hw
import pipeline as gp
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
      :extensions, [vk.VK_KHR_SWAPCHAIN_EXTENSION_NAME],
      :validation, ["VK_LAYER_KHRONOS_validation"]
    ),
    :debuginfo, debug.debuginfo(),
    :window, hashmap(:width, 1920, :height, 1080),
    :swapchain, hashmap(:format, vk.FORMAT_B8G8R8A8_SRGB,
      :colourspace, vk.COLOR_SPACE_SRGB_NONLINEAR_KHR,
      :presentmode, vk.PRESENT_MODE_FIFO_KHR,
      :images, 4)
  )

  window.configure(staticconfig)
end

function init(config)
  steps = [
    hw.instance,
    debug.debugmsgr,
    window.createwindow,
    window.createsurface,
    hw.createdevice,
    hw.createswapchain,
    gp.createpipelines
  ]

  ds.reduce((s, f) -> merge(s, f(config, s)), emptymap, steps)
end

config = configure()
system = init(config)

function repl_teardown()
  # Vulkan.jl mostly cleans up with finalisers, but GLFW.jl is just a C ffi
  # wrapper, so we need to be more careful.
  window.shutdown()
end
