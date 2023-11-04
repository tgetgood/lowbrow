module framework

import Vulkan as vk
import DataStructures as ds

import uniform
import resources as rd
import vertex

function descriptors(dev, frames, bindings)

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
      :layoutcreateinfo, layoutci,
      :descriptorsetlayout, layout,
      :descriptorsets, sets
    )
  else
    config
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

function binddescriptors(dev, descriptors, bindings)
  dsets = get(descriptors, :descriptorsets)
  usages = map(x -> x.descriptor_type, get(descriptors, :layoutcreateinfo).bindings)

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

function frameupdater(system, config)
  function(i, renderstate)
    for (buff, bind) in zip(ds.vals(get(config, :vbuffers)), get(config, :bindings))
      if ds.containsp(bind, :update)
        v = get(bind, :update)(get(config, get(bind, :initial_value)))
        uniform.setubo!(buff[i], v)
      end
    end
  end
end

end
