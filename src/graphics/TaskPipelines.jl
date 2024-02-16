module TaskPipelines

import Vulkan as vk
import DataStructures as ds

import hardware as hw
import framework as fw
import resources as rd
import commands
import pipeline as pipe

abstract type Pipeline end

# REVIEW: Really a pipeline IO wrapper. All of the real logic is hidden in the
# closure of the thread with which these channels communicate.
#
# That isn't ideal.
struct AsyncPipeline <: Pipeline
  input::Channel
  sigkill::Channel
end

abstract type PipelineAllocator end

struct LeakyAllocator <: PipelineAllocator
  system
  dev
  config
  layout
  dsetpool
  commandpool
  dsets
  cmdsbuffs
  outputs
  semaphores
end

function passresources(a::LeakyAllocator)
  sem = vk.unwrap(vk.create_semaphore(
    a.dev,
    vk.SemaphoreCreateInfo(
      next=vk.SemaphoreTypeCreateInfo(vk.SEMAPHORE_TYPE_TIMELINE, UInt(1))
    )))

  post = vk.SemaphoreSubmitInfo(sem, UInt(2), 0)

  dset = vk.unwrap(vk.allocate_descriptor_sets(
    a.dev,
    vk.DescriptorSetAllocateInfo(a.dsetpool, [a.layout])
  ))[1]

  cmd = hw.commandbuffers(a.dev, a.commandpool, 1)[1]

  outputs = ds.into!(
    [],
    map(x -> allocout(a.system, x)),
    get(a.config, :outputs)
  )

  return (dset, cmd, outputs, post)
end

function dummyallocator(system, config, layoutci, layout)
  dev = get(system, :device)
  qf = ds.getin(system, [:queues, :compute])

  dsetpool = vk.unwrap(vk.create_descriptor_pool(
    dev,
    rd.descriptorpool(layoutci, 10000)
  ))

  commandpool = hw.commandpool(dev, qf)

  LeakyAllocator(system, dev, config, layout, dsetpool, commandpool, [], [], [], [])

end

function allocout(system, config)
  type = get(config, :type)
  if type === :ssbo
    out = hw.buffer(system, config)
  elseif type === :image
    out = hw.createimage(system, config)
  else
    throw("not implemented")
  end

  ds.assoc(out, :config, config)
end

# TODO: Wrap vk queues in tasks or some other form of locking so that they can
# be shared from multiple threads
# TODO: Check results and handle errors
#
# REVIEW: This is overkill for my current needs, but if I understand
# https://registry.khronos.org/vulkan/specs/1.1-extensions/html/chap3.html#fundamentals-objectmodel-lifetime
# correctly, vkQueueSubmit2 owns the array submissions while it is executing,
# but releases ownership when it returns.
#
# This would mean that I can have a ringbuffer with many writers and one
# consuming loop, and that loop can just submit chunks of the ringbuffer. Of
# course it would have to be threadsafe, but since write could never (if
# correct) touch the section of ring currently being consumed by submit, it
# should work without any allocation at all. It would have to take a single
# submission at a time and call reduce if they've already been allocated.
#
# The number of useless extra allocations --- often just wrapping values in
# vectors --- is starting to worry me. Some high level architectural changes are
# going to have to happen eventually.
function submit(queue::vk.Queue, submissions)
  vk.queue_submit_2(queue, submissions)
end

function computepipeline(system, config)
  dev = get(system, :device)
  qf = ds.getin(system, [:queues, :compute])
  queue = vk.get_device_queue(dev, qf, 0)

  stage = ds.hashmap(:stage, :compute)
  stagesetter(sets) = map(set -> merge(stage, set), sets)

  if ds.containsp(config, :pushconstants)
    config = ds.update(config, :pushconstants, merge, stage)
  end

  bindings = stagesetter(vcat(get(config, :inputs, []), get(config, :outputs)))

  layoutci = rd. descriptorsetlayout(bindings)
  layout = vk.unwrap(vk.create_descriptor_set_layout(dev, layoutci))

  pipeline = pipe.computepipeline(
    dev, get(config, :shader), layout, [get(config, :pushconstants)]
  )

  allocator = dummyallocator(system, config, layoutci, layout)

  ## Coordination

  inch = Channel()
  killch = Channel()

  Threads.@spawn begin
    try
      while !isready(killch)
        (inputs, pcs, outch) = take!(inch)

        (dset, cmdbuff, outputs, postsem) = passresources(allocator)

        fw.binddescriptors(
          dev, bindings, dset, vcat(inputs, outputs)
        )

        commands.recordcomputation(
          cmdbuff,
          get(pipeline, :pipeline),
          get(pipeline, :layout),
          get(config, :workgroups),
          [dset],
          ds.assoc(get(config, :pushconstants), :value, pcs)
        )

        wait = ds.into!([], map(x -> get(x, :wait)) ∘ ds.cat(), inputs)

        cmdsub = vk.CommandBufferSubmitInfo(cmdbuff, 0)

        submission = vk.SubmitInfo2(wait, [cmdsub], [postsem])

        submit(queue, [submission])

        wrap = ds.into!([], map(x -> ds.assoc(x, :wait, [postsem])), outputs)

        put!(outch, wrap)
      end

      # TODO: Cleanup:
      # No more work will be submitted on this queue, but there might be
      # submitted work waiting on something else.
      #
      # Is it sufficient to bump all timeline semaphores in this queue to
      # "finished" (typemax(UInt32) maybe)? So long as every semaphore in
      # every pipeline runner gets bumped, that should be enough for everything
      # to unblock and flush.
      #
      # What about presentation? That's a little different. Do we actually
      # have to present all buffered frames before exiting? Do we care?

    catch e
      print(stderr, "\n Error in pipeline thread: " *
                    string(get(config, :name)) * "\n")
      ds.handleerror(e)
    end
  end

  return AsyncPipeline(inch, killch)
end

function run(p::AsyncPipeline, inputs, pcs=[])
  # Create a fresh output channel for each set of inputs. I'm not convinced this
  # is the right way to do it, but it lets multiple people submit work and only
  # be able to see their own results.
  out = Channel()
  put!(p.input, [inputs, pcs, out])
  return out
end

function teardown(p::AsyncPipeline)
  put!(p.sigkill, true)
end

function graphicspipeline(system, config)
  dev = get(system, :device)
  qf = ds.getin(system, [:queues, :graphics])
  queue = vk.get_device_queue(dev, qf, 0)

  # Steps to initialise graphics.
    # draw.commandbuffers,
    # hw.createswapchain,
    # hw.createimageviews,
    # gp.renderpass,
    # gp.createframebuffers,
    # gp.creategraphicspipeline,

  Threads.@spawn begin
    try
      while !isready(killch)

        gsig = render.draw(system, co, renderstate)
      end
    catch e
      print(stderr, "\n Error in pipeline thread: " *
                    string(get(config, :name)) * "\n")
      ds.handleerror(e)
    end
  end
end

end
