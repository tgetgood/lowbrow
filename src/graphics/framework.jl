module framework

import Vulkan as vk
import DataStructures as ds

import uniform
import resources as rd
import vertex

abstract type DescriptorSetBinding end

struct UniformBuffer <: DescriptorSetBinding
  config
end

struct Texture <: DescriptorSetBinding
  config
end

buffertypes = ds.hashmap(
  :texture, Texture,
  :uniform, UniformBuffer,
  :ssbo, Any
)

function binding(system, config, binding)
  # REVIEW: Probably ought to use type tags instead of binding
  # functions. Functions --- compiled functions anyway --- aren't data in the
  # sense I need for the bigger picture.
  buffers = get(binding, :allocate)(system, config, binding)

  if get(binding, :type) === :uniform
    data = get(binding, :loader)(get(config, get(binding, :initial_value)))

    for buff in buffers
      uniform.setubo!(buff, data)
    end
  end

  buffers
end

function model(system, config)
  merge(
    config,
    ds.getin(config, [:model, :loader])(config)
  )
end

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
end

function descriptorinfos(binding, data, i)
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
  buffers = get(config, :vbuffers)
  dsets = get(config, :descriptorsets)

  for i = 1:length(dsets)
    vk.update_descriptor_sets(
      dev,
      ds.into(
        [],
        ds.mapindexed((j, b) -> begin
          binding = get(config, :bindings)[j]
          vk.WriteDescriptorSet(
            dsets[i],
            j - 1,
            0,
            get(binding, :usage),
            descriptorinfos(binding, ds.val(b), i)...
          )
        end),
        buffers
      ),
      []
    )
  end
end

function buffers(system, config)
  ds.assoc(merge(
      config,
      vertex.vertexbuffer(system, get(config, :verticies)),
      indexbuffer(system, config)
    ),
    :vbuffers,
    ds.into(
      ds.emptymap,
      map(e -> (get(e, :name), binding(system, config, e))),
      get(config, :bindings)
    )
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
