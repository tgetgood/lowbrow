module window

import Vulkan as vk
import GLFW.GLFW as glfw
import DataStructures: getin, hashmap, assoc, into, emptymap, updatein

function createwindow(config, system)
  glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
  glfw.WindowHint(glfw.RESIZABLE, true)

  window = glfw.CreateWindow(
    getin(config, [:window, :width]),
    getin(config, [:window, :height]),
    "not quite a browser"
  )

  hashmap(:window, window)
end

function createsurface(config, system)
  instance = get(system, :instance)
  surface = glfw.CreateWindowSurface(
    instance,
    get(system, :window)
  )

  # REVIEW: Undocumented. Feels brittle. Possibly incorrect.
  surface = vk.SurfaceKHR(
    surface,
    instance,
    Base.Threads.Atomic{UInt64}(0)
  )

  hashmap(:surface, surface)
end

function configure(config)
  # FIXME: This is an odd place to do side effects, but I don't see anywhere
  # better to do this. Explicit window.init() is not a good alternative.
  glfw.Init()

  updatein(
    config,
    [:instance, :extensions],
    vcat,
    glfw.GetRequiredInstanceExtensions()
  )
end

function shutdown()
  glfw.Terminate()
end

end
