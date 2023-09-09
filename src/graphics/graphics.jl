import hardware as hw
import pipeline as gp
import uniform
import vertex
import render as draw
import debug
import window
import textures
import Vulkan as vk
import DataStructures as ds
import DataStructures: hashmap, emptymap

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
    :window, hashmap(:width, 800, :height, 600),
    :swapchain, hashmap(
      :format, vk.FORMAT_B8G8R8A8_SRGB,
      :colourspace, vk.COLOR_SPACE_SRGB_NONLINEAR_KHR,
      :presentmode, vk.PRESENT_MODE_FIFO_KHR,
      :images, 3
    ),
    :concurrent_frames, 2,
    :vertex_data, [
      [[0, -0.5], [1, 1, 1]],
      [[0.5, 0.5], [0, 1, 0]],
      [[-0.5, 0.5], [0, 0, 1]],
      [[-1, -0.5], [1,0,0]],
    ],
    :indicies, [0, 1, 2, 2, 3, 0],
    :ubo, hashmap(
      :model, [
        1 0 0 0
        0 1 0 0
        0 0 1 0
        0 0 0 1
      ],
      :view, [
        1 0 0 0
        0 1 0 0
        0 0 1 0
        0 0 0 1
      ],
      :projection, [
        1 0 0 0
        0 1 0 0
        0 0 1 0
        0 0 0 1
      ]
    )
  )

  ds.reduce((s, f) -> f(s), staticconfig, [
    window.configure,
    debug.configure,
    vertex.configure,
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
    gp.renderpass,
    hw.createcommandpools,
    hw.createdescriptorpools,
    draw.commandbuffers,
    vertex.vertexbuffer,
    vertex.indexbuffer,
    uniform.allocatebuffers,
    uniform.allocatesets,
    # textures.textureimage,
    # textures.allocatesets,
    gp.writedescriptorsets,

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
  dset = ds.getin(system, [:ubo, :descriptorsets])[i+1]

  (ubuff, dset)
end

function main(system, config)
  sigkill = Channel()

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

 repl_teardown = main(system, config)
