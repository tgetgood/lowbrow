import hardware as hw
import pipeline as gp
import uniform
import vertex
import model
import render as draw
import debug
import window
import textures
import Vulkan as vk
import DataStructures as ds
import DataStructures: hashmap, emptymap

function rotateX(a)
  c = cos(a)
  s = sin(a)

  return [
    1 0 0 0
    0 c -s 0
    0 s c 0
    0 0 0 1
  ]
end

function rotateY(a)
  c = cos(a)
  s = sin(a)

  return [
    c 0 s 0
    0 1 0 0
   -s 0 c 0
    0 0 0 1
  ]
end

function rotateZ(a)
  c = cos(a)
  s = sin(a)

  return [
    c -s 0 0
    s c 0 0
    0 0 1 0
    0 0 0 1
  ]
end

function translate(v)
  [
    1 0 0 v[1]
    0 1 0 v[2]
    0 0 1 v[3]
    0 0 0 1
  ]
end

function scale(x::Real)
  [
    1 0 0 0
    0 1 0 0
    0 0 1 0
    0 0 0 1/x
  ]
end


x = pi/3
function configure()
  staticconfig = hashmap(
    :shaders, hashmap(:vert, "ex1.vert", :frag, "ex1.frag"),
    :instance, hashmap(
      :extensions, [
        "VK_EXT_debug_utils"
      ],
      :validation, ["VK_LAYER_KHRONOS_validation"]
    ),
    :device, hashmap(
      :features, [:sampler_anisotropy],
      :extensions, ["VK_KHR_swapchain"],
      :validation, ["VK_LAYER_KHRONOS_validation"]
    ),
    :debuglevel, vk.DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT,
    :window, hashmap(:width, 1600, :height, 1200),
    :swapchain, hashmap(
      :format, vk.FORMAT_B8G8R8A8_SRGB,
      :colourspace, vk.COLOR_SPACE_SRGB_NONLINEAR_KHR,
      :presentmode, vk.PRESENT_MODE_FIFO_KHR,
      :images, 3
    ),
    :concurrent_frames, 2,
    :vertex_data, [
      [[-0.5, -0.5, 0.3], [1, 0, 0], [0, 0]],
      [[0.5, -0.5, 0.3], [0, 1, 0], [1, 0]],
      [[0.5, 0.5, 0.3], [0, 0, 1], [1, 1]],
      [[-0.5, 0.5, 0.3], [1, 1, 1], [0, 1]],

      [[-0.5, -0.5, 0.7], [1, 1, 1], [0, 0]],
      [[0.5, -0.5, 0.7], [0, 1, 0], [1, 0]],
      [[0.5, 0.5, 0.7], [0, 1, 0], [1, 1]],
      [[-0.5, 0.5, 0.7], [0, 0, 1], [0, 1]],
    ],
    :indicies, [
      0, 1, 2, 2, 3, 0,
      4, 5, 6, 6, 7, 4,
    ],
    :texture_file, *(@__DIR__, "/../../assets/viking_room.png"),
    :model_file, *(@__DIR__, "/../../assets/viking_room.obj"),
    :ubo, hashmap(
      :model, [
        1 0 0 0
        0 cos(x) -sin(x) 0
        0 sin(x) cos(x) 0
        0 0 0 1
      ],
      :view, [
        1 0 0 0
        0 1 0 0
        0 0 1 0
        0 0 0 1
      ],
      :projection, rotateY(pi/3)
    )
  )

  ds.reduce((s, f) -> f(s), staticconfig, [
    window.configure,
    debug.configure,
    # vertex.configure,
    uniform.configure
  ])
end

function staticinit(config)
  steps = [
    hw.instance,
    debug.debugmsgr,
    window.createwindow,
    window.createsurface,
    hw.createdevice,
    hw.createcommandpools,
    hw.createdescriptorpools,
    # model.load,
    gp.renderpass,
    draw.commandbuffers,
    # (x, y) -> vertex.vertexbuffer(x, get(y, :vertex_data)),
    # (x, y) -> vertex.indexbuffer(x, get(y, :indicies)),
    uniform.allocatebuffers,
    # uniform.allocatesets,
    textures.textureimage,
    textures.allocatesets,
  ]

  ds.reduce((s, f) -> merge(s, f(s, config)), emptymap, steps)
end

function dynamicinit(system, config)
  vk.device_wait_idle(get(system, :device))

  steps = [
    hw.createswapchain,
    hw.createimageviews,
    gp.createpipelines,
    gp.createframebuffers,
  ]

  ds.reduce((s, f) -> merge(s, f(s, config)), system, steps)
end

# FIXME: These should be inside `main`, but it's convenient for repl purposes to
# make them global during development.

config = configure()
system = staticinit(config)
system = dynamicinit(system, config)

@info "Ready"

function dsets(system, config, i)
  ubuff = get(system, :uniformbuffers)[i+1]
  dset = [
    ds.getin(system, [:dsets, :descriptorsets])[i+1],
  ]

  (ubuff, dset)
end

function main(system, config)
  sigkill = Channel()

  # The number of some types of Vulkan objects that can be created is
  # limited. Make sure finalisers run to clean up between iterations.
  GC.gc()

  handle = Threads.@spawn begin
    try
      @info "starting main loop"
      buffers = get(system, :commandbuffers)
      i = 0
      frames = 0
      t = time()
      while !window.closep(get(system, :window)) && !isready(sigkill)
        window.poll()

        (ubuff, dset) = dsets(system, config, i)

        if !window.minimised(get(system, :window))
          uniform.setubo!(config, ubuff)
          res = draw.draw(system, buffers[i+1], dset)

          if res == vk.ERROR_OUT_OF_DATE_KHR ||
             res == vk.SUBOPTIMAL_KHR ||
             get(system, :resizecb)()
            system = dynamicinit(system, config)
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
    catch e
      showerror(stderr, e)
      show(stderr, "text/plain", stacktrace(catch_backtrace()))
    end
  end

  @info "returning control"
  return function repl_teardown()
    if istaskstarted(handle) && !istaskdone(handle)
      put!(sigkill, true)
    end
  end
end

# repl_teardown = main(system, config)
