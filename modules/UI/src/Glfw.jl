module Glfw

import Vulkan as vk
import GLFW.GLFW as glfw
import DataStructures as ds

import ..eventsystem as events

function size(window)
  glfw.GetFramebufferSize(window)
end

function extent(window, spec)
  sc = spec.surface.capabilities

  win = size(window)

  vk.Extent2D(
    clamp(win.width, sc.min_image_extent.width, sc.max_image_extent.width),
    clamp(win.height, sc.min_image_extent.height, sc.max_image_extent.height)
  )
end

function minimised(window)
  (width, height) = size(window)
  return width == 0 ||
         height == 0 ||
         glfw.GetWindowAttrib(window, glfw.VISIBLE) == 0
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
      ds.handleerror(e)
    end
  end
end

const buttons = ds.hashmap(
  glfw.MOUSE_BUTTON_LEFT, :left,
  glfw.MOUSE_BUTTON_RIGHT, :right,
  glfw.MOUSE_BUTTON_MIDDLE, :middle
)

const actions = ds.hashmap(
  glfw.PRESS, :down,
  glfw.RELEASE, :up,
  glfw.REPEAT, :repeat
)

const modmap = ds.hashmap(
  glfw.MOD_ALT, :alt,
  glfw.MOD_SHIFT, :shift,
  glfw.MOD_CONTROL, :ctrl,
  glfw.MOD_SUPER, :super
)

function mousebuttoncb(_, button, action, mods)
  try
    events.mouseclickupdate(ds.hashmap(
      :button, get(buttons, button, Int(button)),
      :action, get(actions, action),
      :modifiers, ds.into(
        ds.emptyset,
        filter(x -> (mods & ds.key(x)) > 0) ∘ map(ds.val),
        modmap
      )
    ))
  catch e
    ds.handleerror(e)
  end
end

function mouseposcb(w, x, y)
  try
    s = size(w)
    events.mousepositionupdate((x / s.width, y / s.height) .* -2 .+ 1)
  catch e
    ds.handleerror(e)
  end
end

function scrollcb(_, x, y)
  try
    events.mousescrollupdate(x, y)
  catch e
    ds.handleerror(e)
  end
end

function window(name, config)
  glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
  glfw.WindowHint(glfw.RESIZABLE, get(config, :resizable, false))
  glfw.WindowHint(glfw.REFRESH_RATE, get(config, :refresh, glfw.DONT_CARE))

  window = glfw.CreateWindow(get(config, :width), get(config, :height), name)

  ch = Channel()

  if get(config, :resizable, false)
      glfw.SetFramebufferSizeCallback(window, resizecb(ch))
  end

  if get(config, :interactive, false)
    # TODO: Make this event registration configurable
    glfw.SetMouseButtonCallback(window, mousebuttoncb)
    glfw.SetCursorPosCallback(window, mouseposcb)
    glfw.SetScrollCallback(window, scrollcb)
  end

  window, resized(ch)
end

# FIXME: This module has Vulkan as a dependency because of this one function.
function surface(instance, window)
  # REVIEW: GLFW creates a valid VK_KHR_Surface and returns a raw C pointer to it.
  # The jl vulkan wrapper I'm using needs a managed object, so I need to create
  # that myself.
  #
  # The problem is: to what do I set the initial refcount?
  #
  # Reloading over and over will eventually segfault. Is this the source?
  vk.SurfaceKHR(
    glfw.CreateWindowSurface(instance, window),
    instance,
    Base.Threads.Atomic{UInt64}(0)
  )
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
