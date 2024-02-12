module TaskPipelines

import Vulkan as vk
import DataStructures as ds

import hardware as hw
import framework as fw

abstract type Pipeline end

struct ComputePipeline <: Pipeline
  input::Channel
  sigkill::Channel
end

"""
Sets the state for all resources to a known value. Mostly of use in compute
pipelines.
"""
stagesetter(sets) = map(set -> merge(stage, set), sets)

function computepipeline(system, config)
  dev = get(system, :device)
  qf = get(system, :queuefamily)
  queue = get(system, :queue)

  stage = ds.hashmap(:stage, :compute)

  if ds.containsp(config, :pushconstants)
    config = ds.update(config, :pushconstants, stagesetter)
  end

  bindings = stagesetter(vcat(get(config, :inputs, []), get(config, :outputs)))

  layoutci = rd. descriptorsetlayout(bindings)
  layout = vk.unwrap(vk.create_descriptor_set_layout(dev, layoutci))

  pipeline = pipe.computepipeline(
    dev, get(config, :shader), layout, get(config, :pushconstants)
  )

  dsetpool = vk.unwrap(vk.create_descriptor_pool(
    dev,
    rd.descriptorpool(layoutci, 1)
  ))

  dsets = vk.unwrap(vk.allocate_descriptor_sets(
    dev,
    vk.DescriptorSetAllocateInfo(dsetpool, [layout])
  ))

  commandpool = hw.commandpool(dev, qf)

  outputs = ds.into!(
    [],
    map(x -> allocout(system, x)),
    ds.getin(cp, [:config, :outputs])
  )

  allocator = [] # ???

  ## Coordination

  inch = Channel()
  killch = Channel()

  Threads.@spawn begin
    try
      while !isready(killch)
        (inputs, pcs, outch) = take!(inch)

        (dset, cmdbuff, output, postsem) = passresources(allocator)

        fw.binddescriptors(
          dev, get(cp, :bindings), dset, vcat(inputs, outputs)
        )

        commands.recordcomputation(
          cmdbuff,
          ds.getin(cp, [:pipeline, :pipeline]),
          ds.getin(cp, [:pipeline, :layout]),
          ds.getin(cp, [:config, :workgroups]),
          dset,
          ds.assoc(ds.getin(cp, [:config, :pushconstants]), :value, pcs)
        )

        wait = ds.into!([], map(x -> get(x, :wait)) ∘ ds.cat(), inputs)

        cmdsub = vk.CommandBufferSubmitInfo(cmdbuff, 0)

        submit = vk.SubmitInfo2(wait, [cmdsub], [postsem])

        vk.queue_submit_2(queue, [submit])

        wrap = ds.into!([], map(x -> ds.assoc(x, :wait, [postsem])), outputs)

        put!(outch, wrap)
      end

      # TODO: Cleanup:
      # No more work will be submitted on this queue, but there might be
      # submitted work waiting on something else.
      #
      # Is it sufficient to bump all timeline semaphores in this queue to
      # "finished" (typemax(UInt32) maybe)? So long as every semaphore in
      # every pipeline runner gets to bumped, that should be enough for
      # everything to unblock and flush.
      #
      # What about presentation? That's a little different. Do we actually
      # have to present all buffered frames before exiting? Do we care?

    catch e
      print(stderr, "\n Error in pipeline thread: " *
                    string(get(config, :name)) * "\n")
      ds.handleerror(e)
    end
  end

  return ComputePipeline(inch, killch)
end

function run(p::ComputePipeline, inputs, pcs=[])
  # Create a fresh output channel for each set of inputs. I'm not convinced this
  # is the right way to do it, but it lets multiple people submit work and only
  # be able to see their own results.
  out = Channel()
  put!(p.input, [inputs, pcs, out])
  return out
end

function teardown(p::Pipeline)
  put!(p.sigkill, true)
end

end
