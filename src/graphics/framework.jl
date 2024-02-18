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
import render
import dsets as des

##### Descriptors

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


function descriptorinfos(binding)
  if ds.containsp(binding, :buffer)
    (
      [],
      [vk.DescriptorBufferInfo(
        0, get(binding, :size); buffer=get(binding, :buffer)
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

function binddescriptors(dev, layout, dset, buffers)
  vk.update_descriptor_sets(dev,
    ds.into!(
      [],
      map(x -> get(x, :type))
      ∘
      map(t -> get(rd.descriptortypes, t))
      ∘
      ds.mapindexed((j, dtype) -> begin
        vk.WriteDescriptorSet(
          dset,
          j - 1,
          0,
          dtype,
          descriptorinfos(buffers[j])...
        )
      end),
      layout
    ),
    []
  )
end

function binddescriptors(dev, config, bindings)
  dsets = get(config, :sets)

  @info config
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
    ds.mapindexed((i, dset) -> ds.into!(
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

function renderloop(body, teminate, resize)
  t = time()
  framecounter = 0
  while !terminate()

    window.poll()

    if window.closep(get(system, :window))
      break
    end

    if !window.minimised(get(system, :window))


      renderstate = framefn(i, renderstate)
      res = draw.draw(system, buffers[i], renderstate)

      if res == vk.ERROR_OUT_OF_DATE_KHR ||
         res == vk.SUBOPTIMAL_KHR ||
         get(system, :resizecb)()

        @info "resized"

        resize()
      end
    end

    framecounter += 1
  end
  @info "finished main loop; cleaning up"
  @info "Average fps: " * string(round(framecounter / (time() - t)))
end

end
