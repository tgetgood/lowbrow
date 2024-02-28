module TaskPipelines

import Distributed: pmap

import Vulkan as vk
import DataStructures as ds

import Helpers: thread

import Queues as q

import hardware as hw
import framework as fw
import resources as rd
import commands
import render
import Glfw as window
import pipeline as pipe

# Think of a Pipeline as gpu pipeline: one or more shaders plus all the crap to
# configure and coordinate.
#
# A PipelineExecutor, is then a logical "thread" which feeds that pipeline. Most
# of the resources which are required to create work for a queue are externally
# synchronised, which means that if you want to feed one Pipeline (or Queue)
# from more than one thread, you need multiple copies of these resources wrapped
# up in such a way that you know each copy will be used on a single thread at
# any given time. Those copies are the Executors.
#
# So we have one pipeline and one queue, with possibly many executors binding
# memory and recording command buffers in between.
abstract type Pipeline end
abstract type PipelineExecutor end

# REVIEW: Really a pipeline IO wrapper. All of the real logic is hidden in the
# closure of the thread with which these channels communicate.
#
# That isn't ideal.
struct AsyncPipeline <: Pipeline
  input::Channel
  sigkill::Channel
end


################################################################################
##### Host <-> Device Data Transfer
################################################################################

struct TransferPipeline <: Pipeline
  taskqueue
  kill
  spec
  executors
end

struct CommandPoolExecutor <: PipelineExecutor
  work
  kill
  pool
  queue
end

function cpe(system, qf, queue)
  dev = system.device

  buffercount = ds.Atom(0)
  pool = vk.unwrap(vk.create_command_pool(dev, qf))

  work = Channel()
  sigkill = Channel(1)

  thread() do
    while !isready(sigkill)
      recorder = take!(work)

      if buffercount[] === 0
        @info "resetting transfer pool"
        # FIXME: pools never get reset until the pipeline is idle.
        #
        # This will probably lead to memory leaks in heavily used pipelines.
        vk.reset_command_pool(dev, pool)
      end

      ds.swap!(buffercount, +, 1)
      postsig = hw.ssi(dev)
      cmd = hw.commandbuffer(dev, pool)

      recorder(cmd, postsig, queue)

      thread() do
        # REVIEW: These probably block threads. Assess that.
        commands.wait_semaphore(dev, postsig)
        ds.swap!(buffercount, -, 1)
      end
    end
  end

  CommandPoolExecutor(work, sigkill, pool, queue)
end

function transferpipeline(system, name, spec)
  dev = system.device

  qf = get(system.spec.queues.queue_families, spec.type)
  queue = q.getqueue(system, get(system.spec.queues.allocations, name))

  tasks = Channel(32)
  sigkill = Channel(1)
  exec = ds.vector(cpe(system, qf, queue))

  # FIXME: This indirection is stupid overengineering as presently used.
  thread() do
    while !isready(sigkill)
      cb = take!(tasks)
      @info "scheduling transfer task."
      put!(exec[1].work, cb)
    end
  end

  TransferPipeline(tasks, sigkill, spec, ds.Atom(exec))
end

function register(p::TransferPipeline, cb)
  put!(p.taskqueue, cb)
end

function record(cb, p::TransferPipeline, wait=[], signal=[])
  out = Channel(1)

  function recorder(cmd, post, queue)
    vk.begin_command_buffer(cmd, vk.CommandBufferBeginInfo())

    cb(cmd)

    vk.end_command_buffer(cmd)

    cbi = vk.CommandBufferSubmitInfo(cmd, 0)

    res = q.submit(queue, [vk.SubmitInfo2(wait, [cbi], vcat(signal, [post]))])

    put!(out, (post, take!(res)))
  end

  register(p, recorder)

  return out

end

################################################################################
##### Compute Pipelines
################################################################################


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

function teardown(p::AsyncPipeline)
  @async begin
    try
      put!(p.sigkill, true)
    catch e
      ds.handleerror(e)
    end
  end
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
    a.config.outputs
  )

  return (dset, cmd, outputs, post)
end

function dummyallocator(system, config, qf, layoutci, layout)
  dev = get(system, :device)

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

function computepipeline(system, name, config)
  dev = system.device
  qf = system.queues.compute
  # FIXME:
  queue = hw.getqueue(system, :compute)

  stage = ds.hashmap(:stage, :compute)
  stagesetter(sets) = map(set -> merge(stage, set), sets)

  if ds.containsp(config, :pushconstants)
    config = ds.update(config, :pushconstants, merge, stage)
  end

  bindings = stagesetter(vcat(get(config, :inputs, []), config.outputs))

  layoutci = rd. descriptorsetlayout(bindings)
  layout = vk.unwrap(vk.create_descriptor_set_layout(dev, layoutci))

  pipeline = pipe.computepipeline(
    dev, config.shader, layout, [config.pushconstants]
  )

  allocator = dummyallocator(system, config, qf, layoutci, layout)

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
          pipeline.pipeline,
          pipeline.layout,
          config.workgroups,
          [dset],
          ds.assoc(config.pushconstants, :value, pcs)
        )

        wait = ds.into!([], map(x -> x.wait) ∘ ds.cat(), inputs)

        cmdsub = vk.CommandBufferSubmitInfo(cmdbuff, 0)

        submission = vk.SubmitInfo2(wait, [cmdsub], [postsem])

        q.submit(queue, [submission])

        wrap = ds.into!([], map(x -> ds.assoc(x, :wait, [postsem])), outputs)

        put!(outch, wrap)
      end

      # TODO: Cleanup:
      # No more work will be submitted on this queue, but there might be
      # submitted work waiting on something else.
      #

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

function run(p::AsyncPipeline, inputs)
  # Create a fresh output channel for each set of inputs. I'm not convinced this
  # is the right way to do it, but it lets multiple people submit work and only
  # be able to see their own results.
  out = Channel()
  put!(p.input, (inputs, out))
  return out
end

function presentationpipeline(system)
end

function graphicspipeline(system, name, config)
  dev = system.device
  win = system.window

  qf = system.spec.queues.queue_families.graphics
  gqueue = q.getqueue(system, get(system.spec.queues.allocations, name))
  pqueue = q.getqueue(system, system.spec.queues.allocations.presentation).queue

  bindings = []
  layoutci = rd. descriptorsetlayout(bindings)
  layout = vk.unwrap(vk.create_descriptor_set_layout(dev, layoutci))

  commandpool = hw.commandpool(dev, qf)

  # Steps to initialise graphics.

  swch = thread() do
    swapchain = hw.createswapchain(system, system.spec)
    iviews = hw.createimageviews(merge(system, swapchain), config)
    return merge(swapchain, iviews)
  end

  system = merge(system, pipe.renderpass(system, config))

  gpch = thread() do
    pipe.creategraphicspipeline(system, ds.hashmap(name, config))
  end

  system = merge(system, take!(swch))

  system = merge(system, pipe.createframebuffers(system))

  system = merge(system, take!(gpch))

  inch = Channel()
  killch = Channel()

  Threads.@spawn begin
    framecounter = 0
    t = time()
    try
      while !isready(killch)
        framecounter += 1
        (renderstate, outch) = take!(inch)

        if window.closep(win)
          put!(outch, :closed)
          break
        end

        if window.minimised(win)
          put!(outch, :skip)
        else
          cmd = hw.commandbuffers(dev, commandpool, 1)[1]
          co = ds.assoc(render.syncsetup(system), :commandbuffer, cmd)

          gsig = render.draw(system, gqueue, pqueue, co, renderstate)

          @async begin
            commands.wait_semaphore(dev, gsig)
            # Don't let GC get the command buffer prematurely.
            co
          end

          put!(outch, gsig)
        end
      end
      @info "Average fps: " * string(round(framecounter / (time() - t)))
    catch e
      print(stderr, "\n Error in pipeline thread: " * string(name) * "\n")
      ds.handleerror(e)
    end
  end

  return AsyncPipeline(inch, killch)
end

function initpipeline(system, pipeline)
  name = ds.key(pipeline)
  config = ds.val(pipeline)
  t = config.type
  if t === :transfer
    transferpipeline(system, name, config)
  elseif t === :compute
    computepipeline(system, name, config)
  elseif t === :graphics
    graphicspipeline(system, name, config)
  else
    throw("unknown pipeline type: " * string(pipeline))
  end
end

function buildpipelines(system, config)
  # TODO: Here's where we set up the pipeline cache

  map(e -> [ds.key(e), initpipeline(system, e)], config.pipelines)
  # ds.into(ds.emptymap, pmap(
  #   e -> [ds.key(e), initpipeline(system, e)],
  #   config.pipelines
  # ))
end

end
