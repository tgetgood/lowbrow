module commands

import hardware as hw
import Vulkan as vk
import DataStructures as ds
import DataStructures: getin, emptymap, hashmap, emptyvector, into, nth

function pool(config, system)
  hashmap(
    :pool,
    vk.unwrap(vk.create_command_pool(
      get(system, :device),
      getin(system, [:queues, :graphics]);
      flags=vk.COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT
    ))
  )
end

function buffer(config, system)
  hashmap(
    :commandbuffer,
    vk.unwrap(vk.allocate_command_buffers(
      get(system, :device),
      vk.CommandBufferAllocateInfo(
        get(system, :pool),
        vk.COMMAND_BUFFER_LEVEL_PRIMARY,
        1
      )
    ))[1]
  )
end

function clearvalue(r,g,b,a)
  bytes::Vector{UInt8} = ds.transduce(
    map(x -> convert(Float32, x)) ∘
    map(x -> reinterpret(UInt8, [x])),
    vcat,
    [],
    [r,g,b,a]
  )

  vk.ClearValue(vk.LibVulkan.VkClearValue(NTuple{16, UInt8}(bytes)))
end

function recorder(config, system, n)
  # REVIEW: This can probably be sped up a lot by moving all of the lookups out
  # of the main loop.
  #
  # N.B.: This runs in the render loop!

  cmdbuf = get(system, :commandbuffer)
  render_pass = get(system, :renderpass)
  framebuffers = get(system, :framebuffers)
  win = get(config, :window)
  viewports = [vk.Viewport(0, 0, get(win, :width), get(win, :height), 0, 1)]
  scissors = [vk.Rect2D(vk.Offset2D(0, 0), get(system, :extent))]
  graphics_pipeline = get(system, :pipeline)


  @debug vk.unwrap(vk.reset_command_buffer(cmdbuf))

  vk.unwrap(vk.begin_command_buffer(
    cmdbuf,
    vk.CommandBufferBeginInfo()
  ))

  vk.cmd_begin_render_pass(
    cmdbuf,
    vk.RenderPassBeginInfo(
      render_pass,
      framebuffers[n],
      scissors[1],
      [clearvalue(0,0,0,1.0)]
    ),
    vk.SUBPASS_CONTENTS_INLINE
  )

  vk.cmd_bind_pipeline(
    cmdbuf,
    vk.PIPELINE_BIND_POINT_GRAPHICS,
    graphics_pipeline
  )

  vk.cmd_set_viewport(cmdbuf, viewports)

  vk.cmd_set_scissor(cmdbuf, scissors)

  vk.cmd_draw(cmdbuf, 3, 1, 0, 0)

  vk.cmd_end_render_pass(cmdbuf)

  vk.unwrap(vk.end_command_buffer(cmdbuf))
end

function syncsetup(config, system)
  hashmap(
    :locks,
    (
      vk.unwrap(vk.create_semaphore(
        get(system, :device)
      )),
      vk.unwrap(vk.create_semaphore(
        get(system, :device)
      )),
      vk.unwrap(vk.create_fence(
        get(system, :device);
        flags=vk.FENCE_CREATE_SIGNALED_BIT
      ))
    )
  )
end

function draw(config, system)
  dev = get(system, :device)
  timeout = typemax(Int64)
  (imagesem, rendersem, fence) = get(system, :locks)

  vk.wait_for_fences(dev, [fence], true, timeout)

  vk.reset_fences(dev, [fence])

  image = vk.unwrap(vk.acquire_next_image_khr(
    dev,
    get(system, :swapchain),
    timeout,
    semaphore = imagesem
  ))[1]

  recorder(config, system, image+1)

  submission = vk.SubmitInfo(
    [imagesem],
    [vk.PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT],
    [get(system, :commandbuffer)],
    [rendersem]
  )

  vk.queue_submit(hw.getqueue(system, :graphics), [submission]; fence)

  vk.queue_present_khr(
    hw.getqueue(system, :presentation),
    vk.PresentInfoKHR(
      [rendersem],
      [get(system, :swapchain)],
      [image]
    )
  )
end

end
