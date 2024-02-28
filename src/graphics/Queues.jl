module Queues

import Vulkan as vk
import DataStructures as ds

import resources as rd

import Helpers: thread

################################################################################
##### Wrap vk queues for thread safety
#
# There is a performance hit here, but check it's important before worrying.
################################################################################

struct SharedQueue
  ch
  sigkill
  queue
  qf
end

function submit(queue::vk.Queue, submissions, fence=C_NULL)
  vk.queue_submit_2(queue, submissions; fence)
end

function submit(queue::SharedQueue, submissions, fence=C_NULL)
  out = Channel(1)
  put!(queue.ch, (out, submissions, fence))
  return out
end

function teardown(p::SharedQueue)
  put!(p.sigkill, true)
end

function sharedqueue(queue::vk.Queue, qf)
  ch = Channel()
  kill = Channel()
  thread() do
    while !isready(kill)
      (out, submissions, fence) = take!(ch)
      res = submit(queue, submissions, fence)
      put!(out, res)
    end
  end

  SharedQueue(ch, kill, queue, qf)
end

function getqueue(system, info::vk.DeviceQueueInfo2)
  if ds.containsp(system.cache[].queues, info)
    return get(system.cache[].queues, info)
  else
    q = sharedqueue(
      vk.get_device_queue_2(system.device, info),
      info.queue_family_index
    )
    ds.swap!(system.cache, ds.associn, [:queues, info], q)
    return q
  end
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

end
