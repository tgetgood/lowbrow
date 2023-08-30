module commands

import hardware as hw
import Vulkan as vk
import DataStructures as ds
import DataStructures: getin, emptymap, hashmap, emptyvector, into, nth

function pool(system, config)
  hashmap(
    :pool,
    vk.unwrap(vk.create_command_pool(
      get(system, :device),
      getin(system, [:queues, :graphics]);
      flags=vk.COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT
    ))
  )
end

function syncsetup(system, config)
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


function buffers(system, config)
  buffers = hw.commandbuffers(system, get(config, :concurrent_frames))

  hashmap(
    :commandbuffers,
    map(x -> merge(syncsetup(system, config), hashmap(:commandbuffer, x)), buffers)
  )
end

function recorder(system, n, cmd)
  # REVIEW: This can probably be sped up a lot by moving all of the lookups out
  # of the body.
  #
  # N.B.: This runs in the render loop!

  cmdbuf = get(cmd, :commandbuffer)
  render_pass = get(system, :renderpass)
  framebuffers = get(system, :framebuffers)

  viewports = get(system, :viewports)
  scissors = get(system, :scissors)

  graphics_pipeline = get(system, :pipeline)

  vk.unwrap(vk.reset_command_buffer(cmdbuf))

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
      [vk.ClearValue(
        vk.ClearColorValue((Float32(0), Float32(0), Float32(0), Float32(1)))
      )]
    ),
    vk.SUBPASS_CONTENTS_INLINE
  )

  vk.cmd_bind_pipeline(
    cmdbuf,
    vk.PIPELINE_BIND_POINT_GRAPHICS,
    graphics_pipeline
  )

  vk.cmd_bind_vertex_buffers(
    cmdbuf,
    [ds.getin(system, [:vertexbuffer, :buffer])],
    Vector{vk.VkDeviceSize}([0])
  )

  vk.cmd_set_viewport(cmdbuf, viewports)

  vk.cmd_set_scissor(cmdbuf, scissors)

  vk.cmd_draw(cmdbuf, getin(system, [:vertexbuffer, :verticies]), 1, 0, 0)

  vk.cmd_end_render_pass(cmdbuf)

  vk.unwrap(vk.end_command_buffer(cmdbuf))
end

function draw(system, cmd)
  dev = get(system, :device)
  timeout = typemax(Int64)
  (imagesem, rendersem, fence) = get(cmd, :locks)

  vk.wait_for_fences(dev, [fence], true, timeout)

  imres = vk.acquire_next_image_khr(
    dev,
    get(system, :swapchain),
    timeout,
    semaphore = imagesem
  )

  if vk.iserror(imres)
    err = vk.unwrap_error(imres)
    return err.code
  else
    image = vk.unwrap(imres)[1]

    #  Don't record over unsubmitted buffer
    vk.reset_fences(dev, [fence])

    recorder(system, image + 1, cmd)

    submission = vk.SubmitInfo(
      [imagesem],
      [vk.PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT],
      [get(cmd, :commandbuffer)],
      [rendersem]
    )

    vk.queue_submit(hw.getqueue(system, :graphics), [submission]; fence)

    # end fenced region

    preres = vk.queue_present_khr(
      hw.getqueue(system, :presentation),
      vk.PresentInfoKHR(
        [rendersem],
        [get(system, :swapchain)],
        [image]
      )
    )

    if vk.iserror(preres)
      return vk.unwrap_error(preres).code
    else
    end
  end
end

end
