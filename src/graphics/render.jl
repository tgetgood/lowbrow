module render

import hardware as hw
import Vulkan as vk
import DataStructures as ds
import DataStructures: getin, emptymap, hashmap, emptyvector, into, nth

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


function commandbuffers(system, config)
  buffers = hw.commandbuffers(system, get(config, :concurrent_frames), :graphics)

  hashmap(
    :commandbuffers,
    map(x -> merge(syncsetup(system, config), hashmap(:commandbuffer, x)), buffers)
  )
end

function recorder(cmd, framebuffer, config)
  # REVIEW: This can probably be sped up a lot by moving all of the lookups out
  # of runtime.
  #
  # N.B.: This runs in the render loop!

  cmdbuf = get(cmd, :commandbuffer)
  render_pass = get(config, :renderpass)

  viewports = get(config, :viewports)
  scissors = get(config, :scissors)

  graphics_pipeline = get(config, :pipeline)

  vk.unwrap(vk.reset_command_buffer(cmdbuf))

  vk.unwrap(vk.begin_command_buffer(
    cmdbuf,
    vk.CommandBufferBeginInfo()
  ))

  vk.cmd_begin_render_pass(
    cmdbuf,
    vk.RenderPassBeginInfo(
      render_pass,
      framebuffer,
      scissors[1],
      [
        vk.ClearValue(vk.ClearColorValue((0f0, 0f0, 0f0, 1f0))),
        vk.ClearValue(vk.ClearDepthStencilValue(1, 0)),
      ]
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

  if ds.containsp(config, :descriptorsets)
    descriptorsets = get(config, :descriptorsets)
    if length(descriptorsets) > 0
      vk.cmd_bind_descriptor_sets(
        cmdbuf,
        vk.PIPELINE_BIND_POINT_GRAPHICS,
        get(config, :pipelinelayout),
        0,
        [descriptorsets[1]],
        []
      )
    end
  end

  vert = ds.get(config, :vertexbuffer)

  vk.cmd_bind_vertex_buffers(
    cmdbuf,
    [get(vert, :buffer)],
    Vector{vk.VkDeviceSize}([0])
  )

  if ds.containsp(config, :indexbuffer)
    ind = get(config, :indexbuffer)
    vk.cmd_bind_index_buffer(cmdbuf, get(ind, :buffer), 0, get(ind, :type))

    vk.cmd_draw_indexed(cmdbuf, get(ind, :verticies), 1, 0, 0, 0)
  else
    vk.cmd_draw(cmdbuf, get(vert, :size), 1, 0, 0)
  end

  vk.cmd_end_render_pass(cmdbuf)

  vk.unwrap(vk.end_command_buffer(cmdbuf))
end

function draw(system, cmd, renderstate)
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

    recorder(cmd, get(system, :framebuffers)[image + 1], renderstate)

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
