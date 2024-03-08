module Queues

import Vulkan as vk
import DataStructures as ds

import ..resources as rd
import ..Helpers: thread
import ..Sync

################################################################################
##### Wrap vk queues for thread safety
#
# There is a performance hit here, but check it's important before worrying.
################################################################################

struct SharedQueue
  info::vk.DeviceQueueInfo2
  submissions::Channel
  kill::Channel
end

struct Submit2
  submissions::Vector{vk.SubmitInfo2}
  fence
end

function sharedqueue(queue::vk.Queue, info::vk.DeviceQueueInfo2)
  ch = Channel()
  kill = Channel()
  thread() do
    while !isready(kill)
      (submission, responsech) = take!(ch)
      put!(responsech, submit(queue, submission))
    end
  end

  SharedQueue(info, ch, kill)
end

function submit(queue::vk.Queue, submission::Submit2)
  vk.queue_submit_2(queue, submission.submissions; fence=submission.fence)
end

function submit(queue::vk.Queue, submission::vk.PresentInfoKHR)
  vk.queue_present_khr(queue, submission)
end

"""
Submits work to a VkQueue on a dedicated thread to avoid contention. Waits for a
result from the queue_submit or queue_present_khr and returns it to the caller.
"""
function submit(queue::SharedQueue, submissions, fence=C_NULL)
  out = Channel()
  put!(queue.submissions, (Submit2(submissions, fence), out))
  return take!(out)
end

function submit(queue::SharedQueue, submission::vk.PresentInfoKHR)
  out = Channel()
  put!(queue.submissions, (submission, out))
  return take!(out)
end

function teardown(p::SharedQueue)
  put!(p.sigkill, true)
end

function createqueue(device, cache, info::vk.DeviceQueueInfo2)
  if ds.containsp(cache[], info)
    return get(cache[], info)
  else
    q = sharedqueue(vk.get_device_queue_2(device, info), info)
    ds.swap!(cache, ds.assoc, info, q)
    return q
  end
end

function createqueues(device, queuemap)
  cache = ds.Atom(ds.emptymap)
  ds.mapvals(v -> createqueue(device, cache, v), queuemap)
end

@inline function queue_family(q::SharedQueue)
  q.info.queue_family_index
end

################################################################################
##### VK Init
################################################################################

"""
Choose the "simplest" queue which has all bits specified. Simple means least
queueflagbits total.
"""
function selectqueue(qfp, bits)
  q = sort(
    filter(x -> (x.queue_flags & bits) == bits, qfp);
    by=x -> count_ones(x.queue_flags.val)
  )[1]

  return indexin([q], qfp)[1] - 1
end

function queuetype(qfp, t)
  t, selectqueue(qfp, get(rd.queuebits, t, rd.typo))
end

################################################################################
##### High level negotiation
################################################################################

function allocatequeues(requested_counts, supported_counts, pipelines, qfs)
  if requested_counts == supported_counts
    pbyf = ds.mapvals(ds.keys, pipelines)
    ds.into(
      ds.emptymap,
      ds.mapvals(v -> reduce(ds.concat, map(x -> get(pbyf, x), v)))
      ∘
      ds.remove(e -> ds.emptyp(ds.val(e)))
      ∘
      ds.map(e -> ds.mapindexed(
        (i, name) -> [name, vk.DeviceQueueInfo2(ds.key(e), i - 1)],
        ds.val(e))
      )
      ∘
      ds.cat(),
      ds.invert(qfs)
    )
  elseif sum(ds.vals(supported_counts)) == 1
    # REVIEW: If the hardware only supports one queue, it *has to be* (0, 0), no?
    q = vk.DeviceQueueInfo2(0, 0)
    reduce(merge, map(m -> ds.mapvals(_ -> q, m), ds.vals(pipelines)))
  else
    # Hard case. Also the most likely, I would think.
    throw("not implemented")
  end
end

function queuerequirements(config, info)
  qfp = info.device.qf_properties
  qtypes = [:transfer, :compute, :graphics]

  queue_families = ds.into(ds.emptymap, map(x -> queuetype(qfp, x)), qtypes)

  pipelines = ds.groupby(x -> ds.val(x).type, config.pipelines)

  pipelinecounts = ds.mapvals(ds.count, pipelines)

  queuecountbyfamily = ds.into(
    ds.emptymap,
    ds.mapvals(x -> sum(ds.into!([], map(y -> get(pipelinecounts, y, 0)), x)))
    ∘
    filter(e -> ds.val(e) > 0),
    ds.invert(queue_families)
  )

  if !get(config, :headless, false)
    queue_families = ds.assoc(
      queue_families,
      :presentation,
      first(sort(ds.seq(info.surface.presentation_qfs)))
    )

    presqf = queue_families.presentation

    queuecountbyfamily = ds.assoc(
      queuecountbyfamily,
      presqf,
      get(queuecountbyfamily, presqf, 0) + 1
    )

    pipelines = ds.assoc(pipelines, :presentation,
      ds.hashmap(:presentation, ds.hashmap(:type, :presentation))
    )
  end

  supported_counts = ds.into(
    ds.emptymap,
    map(x -> [ds.key(x), min(ds.val(x), qfp[ds.key(x) + 1].queue_count)])
    ∘
    filter(x -> x[2] > 0),
    queuecountbyfamily
  )

  queue_allocations = allocatequeues(
    queuecountbyfamily, supported_counts, pipelines, queue_families
  )

  ds.hashmap(
    :queue_families, queue_families,
    :supported_counts, supported_counts,
    :allocations, queue_allocations
  )
end

################################################################################
##### Pipeline-free Work Submission
################################################################################

function submitcommands(cb, dev::vk.Device, queue::SharedQueue, wait=[], signal=[])
  # FIXME: I want to keep dependencies clean, but at the same time, I want to
  # wrap this VK interaction. Dilemma
  pool = vk.unwrap(vk.create_command_pool(dev, queue_family(queue)))
  cmd = vk.unwrap(vk.allocate_command_buffers(dev, vk.CommandBufferAllocateInfo(
      pool, vk.COMMAND_BUFFER_LEVEL_PRIMARY, 1))
  )[1]

  post = Sync.ssi(dev)

  vk.begin_command_buffer(cmd, vk.CommandBufferBeginInfo())

  cb(cmd)

  vk.end_command_buffer(cmd)

  cbi = vk.CommandBufferSubmitInfo(cmd, 0)

  res = submit(queue, [vk.SubmitInfo2(wait, [cbi], vcat(signal, [post]))])

  thread() do
    # Prevent GC from deleting this pool until the GPU is done with it
    Sync.wait_semaphore(dev, post)
    pool
    cmd
  end

  return post, res
end

end
