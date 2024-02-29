module render

import Sync
import Queues as q
import hardware as hw
import Vulkan as vk
import DataStructures as ds
import DataStructures: getin, emptymap, hashmap, emptyvector, into, nth

function syncsetup(system)
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
    map(x -> merge(syncsetup(system), hashmap(:commandbuffer, x)), buffers)
  )
end

function recorder(cmd, i, system, config)
  # REVIEW: This can probably be sped up a lot by moving all of the lookups out
  # of runtime.
  #
  # N.B.: This runs in the render loop!

  framebuffers = system.framebuffers
  cmdbuf = get(cmd, :commandbuffer)
  render_pass = system.renderpass

  viewports = system.viewports
  scissors = system.scissors

  graphics_pipeline = system.pipeline

  vk.unwrap(vk.begin_command_buffer(
    cmdbuf,
    vk.CommandBufferBeginInfo()
  ))

  vk.cmd_begin_render_pass(
    cmdbuf,
    vk.RenderPassBeginInfo(
      render_pass,
      framebuffers[i],
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

  descriptorsets = ds.getin(config, [:descriptorsets, :sets], [])
  layout = system.pipelinelayout

  if length(descriptorsets) > 0
    vk.cmd_bind_descriptor_sets(
      cmdbuf,
      vk.PIPELINE_BIND_POINT_GRAPHICS,
      layout,
      0,
      [descriptorsets[i]],
      []
    )
  end

  pcvs = get(config, :pushconstants, [])

  if length(pcvs) > 0
    vk.cmd_push_constants(
      cmdbuf,
      layout,
      # FIXME: what about the other stages?
      vk.SHADER_STAGE_FRAGMENT_BIT,
      0,
      sizeof(pcvs),
      Ptr{Nothing}(pointer(pcvs))
    )
  end

  vert = config.vertexbuffer

  vk.cmd_bind_vertex_buffers(cmdbuf, [vert.buffer], vk.VkDeviceSize[0])

  if ds.containsp(config, :indexbuffer)
    ind = config.indexbuffer
    vk.cmd_bind_index_buffer(cmdbuf, ind.buffer, 0, ind.type)

    vk.cmd_draw_indexed(cmdbuf, ind.verticies, 1, 0, 0, 0)
  else
    vk.cmd_draw(cmdbuf, vert.verticies, 1, 0, 0)
  end

  vk.cmd_end_render_pass(cmdbuf)

  vk.unwrap(vk.end_command_buffer(cmdbuf))
end

function draw(system, gqueue, pqueue, cmd, renderstate)
  dev = get(system, :device)
  timeout = typemax(Int64)
  (imagesem, rendersem, fence) = get(cmd, :locks)

  vk.wait_for_fences(dev, [fence], true, timeout)

  imres = vk.acquire_next_image_khr(
    dev, system.swapchain, timeout; semaphore = imagesem
  )

  if vk.iserror(imres)
    err = vk.unwrap_error(imres)
    return err.code
  else
    image = vk.unwrap(imres)[1]

    #  Don't record over unsubmitted buffer
    vk.reset_fences(dev, [fence])

    if ds.containsp(renderstate, :binding)
      des.binddescriptors(
        dev,
        ds.getin(renderstate, [:descriptorsets, :bindings]),
        ds.getin(renderstate, [:descriptorsets, :sets])[image+1],
        get(renderstate, :binding)
      )
    end

    recorder(cmd, image + 1, system, renderstate)

    sig = Sync.ssi(dev)

    vwait = ds.getin(renderstate, [:vertexbuffer, :wait], [])

    imagewait = vk.SemaphoreSubmitInfo(
      imagesem, 0, 0;
      stage_mask=vk.PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT
    )

    submission = vk.SubmitInfo2(
      ds.conj(vwait, imagewait),
      [vk.CommandBufferSubmitInfo(get(cmd, :commandbuffer), 0)],
      [vk.SemaphoreSubmitInfo(rendersem, 0, 0), sig]
    )

    # We need to wait for this submission before submitting to the presentation
    # queue. This is because binary semaphores must be set to signal before
    # anything can be set to wait on them. This restriction doesn't apply to
    # timeline semaphores, but presentation can't take those.
    q.submitsync(gqueue, [submission], fence)

    preres = q.submitsync(
      pqueue,
      vk.PresentInfoKHR(
        [rendersem],
        [system.swapchain],
        # FIXME: If graphics and present are not the same qf, we need to
        # transfer the framebuffer image. Is that possible?
        [image]
      )
    )

    if vk.iserror(preres)
      return vk.unwrap_error(preres).code
    else
      return sig
    end
  end
end

end
