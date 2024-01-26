"""
Helpers that work in a frameworky fashion. I don't want a framework, but I
really hate boilerplate.
"""
module framework

import Vulkan as vk
import DataStructures as ds

import commands
import resources as rd
import vertex
import pipeline as pipe
import hardware as hw

const initialpoolsize = 3

function descriptors(dev, bindings, poolsize=initialpoolsize)
  if length(bindings) > 0
    layoutci = rd.descriptorsetlayout(bindings)
    poolci = rd.descriptorpool(layoutci, poolsize)

    layout = vk.unwrap(vk.create_descriptor_set_layout(dev, layoutci))

    pool = vk.unwrap(vk.create_descriptor_pool(dev, poolci))

    sets = vk.unwrap(vk.allocate_descriptor_sets(
      dev,
      vk.DescriptorSetAllocateInfo(
        pool,
        ds.into([], ds.take(poolsize), ds.repeat(layout))
      )
    ))

    ds.hashmap(
      :pool, pool,
      :layout, layout,
      :sets, sets
    )
  else
    ds.emptymap
  end
end

function computepipeline(dev, config)
  stage = ds.hashmap(:stage, :compute)
  stagesetter = sets -> map(set -> merge(stage, set), sets)

  if ds.containsp(config, :pushconstants)
    config = ds.update(config, :pushconstants, stagesetter)
  end

  bindings = stagesetter(vcat(get(config, :inputs, []), get(config, :outputs)))

  layoutci = rd.descriptorsetlayout(bindings)
  layout = vk.unwrap(vk.create_descriptor_set_layout(dev, layoutci))

  pipeline = pipe.computepipeline(
    dev, get(config, :shader), layout, get(config, :pushconstants)
  )

  queue = hw.findcomputequeue(get(config, :qf_properties))

  ds.hashmap(
    :config, config,
    :descriptorsetlayout, layout,
    :descriptorsetlayoutci, layoutci,
    :bindings, bindings,
    :pipeline, pipeline,
    :queuefamily, queue,
  )
end

function runcomputepipeline(system, cp, inputs, pushconstants=[])

  # Need
  # 1) pool for descriptor sets
  # 2) pool for commanpools
  # 3) pool for ssbos (output)
  #
  # OR, just create a new one each time and throw it away. Good enough for a
  # proof of concept.

  layout = get(cp, :descriptorsetlayout)
  layoutci = get(cp, :descriptorsetlayoutci)

  dev = get(system, :dev)

  dsetpool = vk.unwrap(vk.create_descriptor_pool(
    dev,
    rd.descriptorpool(layoutci, 1)
  ))

  dsets = vk.unwrap(vk.allocate_descriptor_sets(
    dev,
    vk.DescriptorSetAllocateInfo(dsetpool, [layout])
  ))

  commandpool = hw.commandpool(dev, get(cp, :queuefamily))
  cmd = hw.commandbuffers(dev, commandpool, 1)[1]

  output = merge(inputs, hw.buffer(system, get(inputs, :config)))

  fw.binddescriptors(dev, ds.assoc(bindings, :sets, dsets), [inputs, output])

  ### record compute commands once since they never change.

  cqueue = vk.get_device_queue(get(cmd, :queuefamily), 0)

  commands.recordcomputation(
    cmd,
    ds.getin(cp, [:pipeline, :pipeline]),
    ds.getin(cp, [:pipeline, :layout]),
    ds.getin(cp, [:config, :workgroups]),
    dsets
  )

  sem = vk.unwrap(vk.create_semaphore(
    dev,
    vk.SemaphoreCreateInfo(
      next=vk.SemaphoreTypeCreateInfo(vk.SEMAPHORE_TYPE_TIMELINE, UInt(1))
    )))

  post = vk.SemaphoreSubmitInfo(sem, UInt(2))

  cmdsub = vk.CommandBufferSubmitInfo(cmd, 0)

  submit = vk.SubmitInfo2(get(inputs, :wait), [cmdsub], [post])

  vk.queue_submit_2(cqueue, [submit])

  @async begin
    wait_semaphore(dev, post)
    # withhold refs from gc until gpu is done with them.
    (dsetpool, dsets, commandpool, cmds)
  end

  ds.assoc(output, :wait, [post])
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

  dtypes = ds.into!(
    [],
    map(x -> get(x, :type))
    ∘
    map(t -> get(rd.descriptortypes, t))
    ,
    get(config, :bindings)
  )

  writes = ds.into!(
    [],
    ds.mapindexed((i, dset) -> ds.into(
      [],
      ds.mapindexed((j, dtype) -> begin
        vk.WriteDescriptorSet(
          dset,
          j - 1,
          0,
          dtype,
          descriptorinfos(bindings[i][j])...
        )
      end),
      dtypes
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

"""
Takes a function and args and applies it in a thread, returning a channel which
will eventually yield the result.
"""
function thread(f, args...)
  join = Channel()
  Threads.@spawn begin
      try
        put!(join, f(args...))
      catch e
        ds.handleerror(e)
      end
  end
  return join
end

end
