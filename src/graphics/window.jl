module window

import Vulkan as vk
import GLFW.GLFW as glfw
import DataStructures as ds

function size(window)
  glfw.GetFramebufferSize(window)
end

function minimised(window)
  (width, height) = size(window)
  return width == 0 || height == 0
end

function resized(ch)
  function inner()
    res = false
    while isready(ch)
      take!(ch)
      res = true
    end
    return res
  end
end

function closep(window)
  glfw.WindowShouldClose(window)
end

function poll()
  glfw.PollEvents()
end

function resizecb(ch)
  function inner(win, _, _)
    try
      if !isready(ch)
        @async put!(ch, true)
      end
    catch e
      @error e
    end
  end
end

function createwindow(system, config)
  glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
  glfw.WindowHint(glfw.RESIZABLE, true)
  glfw.WindowHint(glfw.REFRESH_RATE, glfw.DONT_CARE)

  width = ds.getin(config, [:window, :width])
  height = ds.getin(config, [:window, :height])

  window = glfw.CreateWindow(width, height, get(config, :name, "dev"))

  ch = Channel()

  glfw.SetFramebufferSizeCallback(window, resizecb(ch))

  ds.hashmap(:window, window, :resizecb, resized(ch), :window_size, (;width, height))
end

function createsurface(system, config)
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

  ds.hashmap(:surface, surface)
end

function configure()
  # FIXME: This is an odd place to do side effects, but I don't see anywhere
  # better to do this. Explicit window.init() is not a good alternative.
  glfw.Init()

  ds.associn(
    ds.emptymap,
    [:instance, :extensions],
    glfw.GetRequiredInstanceExtensions()
  )
end

function shutdown()
  glfw.Terminate()
end

end
