"""
Helpers that work in a frameworky fashion. I don't want a framework, but I
really hate boilerplate.
"""
module framework

import Vulkan as vk
import DataStructures as ds

import uniform
import resources as rd
import vertex

function descriptors(dev, dsetspec)
  bindings = get(dsetspec, :bindings)
  frames = get(dsetspec, :count)

  if length(bindings) > 0
    layoutci = rd.descriptorsetlayout(bindings)
    poolci = rd.descriptorpool(layoutci, frames)

    layout = vk.unwrap(vk.create_descriptor_set_layout(dev, layoutci))

    pool = vk.unwrap(vk.create_descriptor_pool(dev, poolci))

    sets = vk.unwrap(vk.allocate_descriptor_sets(
      dev,
      vk.DescriptorSetAllocateInfo(
        pool,
        ds.into([], ds.take(frames), ds.repeat(layout))
      )
    ))

    ds.hashmap(
      :layout, layout,
      :sets, sets
    )
  else
    ds.emptymap
  end
end

function descriptorinfos(binding)
  if ds.containsp(binding, :buffer)
    (
      [],
      [vk.DescriptorBufferInfo(
        0, get(binding, :size), buffer=get(binding, :buffer)
      )],
      []
    )
  elseif ds.containsp(binding, :texture)
    (
      [vk.DescriptorImageInfo(
        get(binding, :sampler),
        get(binding, :textureimageview),
        vk.IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
      )],
      [],
      []
    )
  else
    ([],[],[])
  end
end

function binddescriptors(dev, config, bindings)
  dsets = get(config, :sets)
  usages = map(x -> get(x, :usage), get(config, :bindings))

  writes = ds.into(
    [],
    ds.mapindexed((i, dset) -> ds.into(
      [],
      ds.mapindexed((j, usage) -> begin
        vk.WriteDescriptorSet(
          dset,
          j - 1,
          0,
          usage,
          descriptorinfos(bindings[i][j])...
        )
      end),
      usages
    )),
    dsets
  )

  for write in writes
    vk.update_descriptor_sets(dev, write, [])
  end
end

function indexbuffer(system, config)
  if ds.containsp(config, :indicies)
    vertex.indexbuffer(system, get(config, :indicies))
  else
    ds.emptymap
  end
end

function buffers(system, config)
  merge(
    config,
    vertex.vertexbuffer(system, get(config, :verticies)),
    indexbuffer(system, config)
  )
end

function acquire_present(drawfn, system, swapchain, locks)
  dev = get(system, :device)
  timeout = typemax(Int64)
  (imagesem, rendersem, fence) = locks

  vk.wait_for_fences(dev, [fence], true, timeout)

  imres = vk.acquire_next_image_khr(
    dev,
    swapchain,
    timeout,
    semaphore = imagesem
  )

  if vk.iserror(imres)
    err = vk.unwrap_error(imres)
    return err.code
  else
    image = vk.unwrap(imres)[1] + 1 # 0-indexed -> 1-indexed

    #  Don't record over unsubmitted buffer
    vk.reset_fences(dev, [fence])

    drawfn(image)

    # end fenced region

    preres = vk.queue_present_khr(
      hw.getqueue(system, :presentation),
      vk.PresentInfoKHR(
        [rendersem],
        [swapchain],
        [image]
      )
    )

    if vk.iserror(preres)
      return vk.unwrap_error(preres).code
    end
  end
end

function assemblerender(system, config)
  merge(
    ds.selectkeys(system, [
      :renderpass,
      :viewports,
      :scissors,
      :pipeline,
      :pipelinelayout,
    ]),
    ds.selectkeys(config, [
      :vertexbuffer,
      :indexbuffer,
      :descriptorsets,
      :vbuffers,
      :bindings
    ])
  )
end

end
