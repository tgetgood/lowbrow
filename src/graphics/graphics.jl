import hardware as hw
import pipeline as gp
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
      :extensions, [vk.VK_KHR_SWAPCHAIN_EXTENSION_NAME],
      :validation, ["VK_LAYER_KHRONOS_validation"]
    ),
    :debuglevel, vk.DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT,
    :window, hashmap(:width, 1920, :height, 1080),
    :swapchain, hashmap(:format, vk.FORMAT_B8G8R8A8_SRGB,
      :colourspace, vk.COLOR_SPACE_SRGB_NONLINEAR_KHR,
      :presentmode, vk.PRESENT_MODE_FIFO_KHR,
      :images, 2)
  )

  ds.reduce((s, f) -> f(s), staticconfig, [
    window.configure,
    debug.configure
  ])
end

function init(config)
  steps = [
    hw.instance,
    debug.debugmsgr,
    window.createwindow,
    window.createsurface,
    hw.createdevice,
    hw.createswapchain,
    hw.createimageviews,
    gp.createpipelines,
    gp.createframebuffers,
    commands.pool,
    commands.buffer,
    commands.syncsetup
  ]

  ds.reduce((s, f) -> merge(s, f(config, s)), emptymap, steps)
end

config = configure()
system = init(config)

@info "Ready"

function main(config, system)
  @async begin
    while !window.closep(get(system, :window))
      commands.draw(config, system)
    end

    vk.device_wait_idle(get(system, :device))
    window.shutdown()
  end
end

main(config, system)

function repl_teardown()
  # Vulkan.jl mostly cleans up with finalisers, but GLFW.jl is just a C ffi
  # wrapper, so we need to be more careful.
  vk.device_wait_idle(get(system, :device))
  window.shutdown()
end
