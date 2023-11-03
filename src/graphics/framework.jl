module framework

import Vulkan as vk
import DataStructures as ds

import uniform
import resources as rd
import vertex

function indexbuffer(system, config)
  if ds.containsp(config, :indicies)
    vertex.indexbuffer(system, get(config, :indicies))
  else
    ds.emptymap
  end
end

function descriptors(system, config)
  dev = get(system, :device)
  frames = get(config, :concurrent_frames, 1)

  if ds.containsp(config, :bindings) && length(get(config, :bindings)) > 0
    layoutci = rd.descriptorsetlayout(get(config, :bindings, []))
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

    ds.assoc(config,
      :descriptorsetlayout, layout,
      :descriptorsets, sets
    )
  else
    config
  end
end

function descriptorinfos(binding, i)
  data = get(binding, :buffer)

  if data isa Vector
    data = data[i]
  end

  if ds.containsp(data, :buffer)
    (
      [],
      [vk.DescriptorBufferInfo(0, get(data, :size), buffer=get(data, :buffer))],
      []
    )
  elseif ds.containsp(data, :texture)
    (
      [vk.DescriptorImageInfo(
        get(data, :sampler),
        get(data, :textureimageview),
        vk.IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
      )],
      [],
      []
    )
  else
    ([],[],[])
  end
end

function binddescriptors(system, config)
  dev = get(system, :device)
  bindings = get(config, :bindings)
  dsets = get(config, :descriptorsets, [])

  for i = 1:length(dsets)
    vk.update_descriptor_sets(
      dev,
      ds.into(
        [],
        ds.mapindexed((j, binding) -> begin
          vk.WriteDescriptorSet(
            dsets[i],
            j - 1,
            0,
            get(binding, :usage),
            descriptorinfos(binding, i)...
          )
        end),
        bindings
      ),
      []
    )
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
