module TaskPipelines

import Vulkan as vk
import DataStructures as ds

import ..Helpers: thread

import ..Queues as q
import ..Sync

import ..Presentation
import ..hardware as hw
import ..framework as fw
import ..resources as rd
import ..render
import ..pipeline as pipe

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

function cpe(system, queue)
  dev = system.device

  buffercount = ds.Atom(0)
  pool = vk.unwrap(vk.create_command_pool(dev, q.queue_family(queue)))

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
      postsig = Sync.ssi(dev)
      cmd = hw.commandbuffer(dev, pool)

      recorder(cmd, postsig, queue)

      thread() do
        # REVIEW: These probably block threads. Assess that.
        Sync.wait_semaphore(dev, postsig)
        ds.swap!(buffercount, -, 1)
      end
    end
  end

  CommandPoolExecutor(work, sigkill, pool, queue)
end

function transferpipeline(system, spec)
  dev = system.device
  name = spec.name

  queue = get(system.queues, name)

  tasks = Channel(32)
  sigkill = Channel(1)
  exec = ds.vector(cpe(system, queue))

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

    put!(out, (post, res))
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

function recordcomputation(
  cmd, pipeline, layout, workgroup=[1, 1, 1], dsets=[], pcs=ds.emptymap
)
  vk.begin_command_buffer(cmd, vk.CommandBufferBeginInfo())

  vk.cmd_bind_pipeline(cmd, vk.PIPELINE_BIND_POINT_COMPUTE, pipeline)

  if !ds.emptyp(pcs)
    vk.cmd_push_constants(
      cmd,
      layout,
      vk.SHADER_STAGE_COMPUTE_BIT,
      get(pcs, :offset, 0),
      get(pcs, :size),
      Ptr{Nothing}(pointer(get(pcs, :value)))
    )
  end

  vk.cmd_bind_descriptor_sets(
    cmd,
    vk.PIPELINE_BIND_POINT_COMPUTE,
    layout,
    0,
    dsets,
    []
  )

  vk.cmd_dispatch(cmd, workgroup...)

  vk.end_command_buffer(cmd)
end

function computepipeline(system, config)
  dev = system.device
  name = config.name
  qf = system.spec.queues.queue_families.compute
  queue = get(system.queues, name)

  stage = ds.hashmap(:stage, :compute)
  stagesetter(sets) = map(set -> merge(stage, set), sets)

  if ds.containsp(config, :pushconstants)
    config = ds.update(config, :pushconstants, merge, stage)
  end

  bindings = stagesetter(vcat(get(config, :inputs, []), config.outputs))

  layoutci = rd.descriptorsetlayout(bindings)
  layout = vk.unwrap(vk.create_descriptor_set_layout(dev, layoutci))

  pipeline = pipe.computepipeline(
    system, config.shader, layout, [config.pushconstants]
  )

  allocator = dummyallocator(system, config, qf, layoutci, layout)

  ## Coordination

  inch = Channel()
  killch = Channel()

  Threads.@spawn begin
    try
      while !isready(killch)
        (input, outch) = take!(inch)
        inputs, pcs = input

        (dset, cmdbuff, outputs, postsem) = passresources(allocator)

        fw.binddescriptors(
          dev, bindings, dset, vcat(inputs, outputs)
        )

        recordcomputation(
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
      # Bump all timelines to "finished" (typemax(UInt32) maybe)? So long as
      # every semaphore in every pipeline runner gets bumped, that should be
      # enough for everything to unblock and flush.

    catch e
      print(stderr, "\n Error in pipeline thread: " * name * "\n")
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

function graphicspipeline(system, config)
  dev = system.device
  win = system.window
  bcount = system.spec.swapchain.images

  name = config.name
  qf = system.spec.queues.queue_families.graphics
  gqueue = get(system.queues, name)
  pqueue = system.queues.presentation

  # REVIEW: Would outputs from a render really work like this? In reality you
  # want things like the depth buffer, framebuffer, etc.. These things are
  # already implicit inputs that need to be accessed separately (and the
  # renderpass may need to be modified to make them available).
  # bindings = vcat(get(config, :inputs, []), get(config, :outputs, []))
  #
  # For now, I'm just going to stick with the old name
  bindings = get(config, :bindings, [])

  layoutci = rd.descriptorsetlayout(bindings)
  layout = vk.unwrap(vk.create_descriptor_set_layout(dev, layoutci))

  dsets = fw.descriptors(dev, bindings, bcount)

  commandpool = hw.commandpool(dev, qf)

  extent = system.wm.extent(system.window, system.spec)

  # Steps to initialise graphics.

  swch = thread() do
    swapchain = Presentation.swapchain(system, extent, system.spec.swapchain)
    iviews = hw.createimageviews(merge(system, swapchain), extent, config)
    return merge(swapchain, iviews)
  end

  system = merge(system, pipe.renderpass(system, config))

  gpch = thread() do
    pipe.creategraphicspipeline(system, extent, ds.hashmap(name, ds.associn(
      config, [:descriptorsets, :layout], layout)
    ))
  end

  system = merge(system, take!(swch))

  system = merge(system, pipe.createframebuffers(system, extent))

  system = merge(system, take!(gpch))

  # Initialised

  inch = Channel()
  killch = Channel()

  buffer = 0
  dsetbindings::Vector{Any} = map(_ -> nothing, 1:bcount)

  Threads.@spawn begin
    framecounter = 0
    t = time()
    try
      while !isready(killch)
        buffer = (buffer % bcount) + 1
        framecounter += 1
        (renderstate, outch) = take!(inch)

        # FIXME: This will crash if we switch window managers.
        if system.wm.closep(win)
          put!(outch, :closed)
          break
        end

        # FIXME: This will also crash if we switch window managers.
        if system.wm.minimised(win)
          put!(outch, :skip)
        else
          data = renderstate.bindings
          if dsetbindings[buffer] !== data
            # TODO: Performance warnings flag! macro?
            @info "rebinding descriptorset"
            fw.binddescriptors(dev, bindings, dsets.sets[buffer], data)
            dsetbindings[buffer] = data
          end

          cmd = hw.commandbuffers(dev, commandpool, 1)[1]
          co = ds.assoc(render.syncsetup(system), :commandbuffer, cmd)

          dset = ds.containsp(dsets, :sets) ? dsets.sets[buffer] : nothing

          gsig = render.draw(system, gqueue, pqueue, co, dset, renderstate)

          @async begin
            Sync.wait_semaphore(dev, gsig)
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

function initpipeline(system, config)
  t = config.type
  if t === :transfer
    transferpipeline(system, config)
  elseif t === :compute
    computepipeline(system, config)
  elseif t === :graphics
    graphicspipeline(system, config)
  else
    @warn config
    throw("unknown pipeline type: " * string(t))
  end
end

function cachekey(config)
 *(
    @__DIR__, "/../../../cache/", string(config.name), "-", string(config.version)
  )
end

function getcache(dev, key)
  if isfile(key)
    size = stat(key).size
    v = Vector{UInt8}(undef, size)
    read!(key, v)

    init = Ptr{Nothing}(pointer(v))
  else
    size = 0
    init = Ptr{Nothing}()
  end

  vk.unwrap(vk.create_pipeline_cache(dev, init; initial_data_size=UInt32(size)))
end

function savecache(dev, cache, key)
  size, ptr = vk.unwrap(vk.get_pipeline_cache_data(dev, cache))

  v = unsafe_wrap(Array, Ptr{UInt8}(ptr), size; own=true)

  write(key, v)
end

function buildpipelines(system, config)
  key = cachekey(config)

  if get(config, :cache_pipelines, false)
    system = ds.assoc(system, :pipeline_cache, getcache(system.device, key))
  end

  ps = ds.into(
    ds.emptymap,
    map(e -> (ds.key(e), ds.assoc(ds.val(e), :name, ds.key(e))))
    ∘
    ds.mapvals(p -> thread(() -> initpipeline(system, p)))
    ∘
    ds.mapvals(take!),
    config.pipelines
  )

  if get(config, :cache_pipelines, false)
    savecache(system.device, system.pipeline_cache, key)
  end

  return ps
end

end
