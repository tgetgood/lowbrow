module computepipeline

import Vulkan as vk
import DataStructures as ds

import resources as rd
import pipeline as pipe
import hardware as hw

abstract type Pipeline end
abstract type GPUTask end

struct ComputePipeline <: Pipeline
  pipeline::vk.Pipeline
  pipelinelayout
#   # TODO: I can migrate config into this struct as I know what I need.
  config::ds.Map
end

struct ComputeTask <: GPUTask
  pipeline::ComputePipeline
  descriptorset::vk.DescriptorSet
  commandbuffer::vk.CommandBuffer

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
    dev, get(config, :shader), layout, pushconstants
  )

  queue = hw.findcomputequeue(get(config, :qf_properties))

  ComputePipeline(get(pipeline, :pipeline), get(pipeline, layout),
    merge(config, ds.hashmap(
    :descriptorsetlayout, layout,
    :queuefamily, queue,
  )))
end
