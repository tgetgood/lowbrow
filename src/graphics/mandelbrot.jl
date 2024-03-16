import HLVK.hardware as hw
import HLVK.init
import HLVK.TaskPipelines as tp
import HLVK.vertex

import Glfw as window
import eventsystem as es
import mouse
import HLVK.Commands: fromdevicelocal

# For development
import Vulkan as vk

import DataStructures as ds

struct Vertex
  position::NTuple{2,Float32}
end

function vert(pos)
  Vertex(tuple(pos...))
end

function load(config)
  config = ds.update(config, :verticies, x -> map(vert, x))
  config = ds.update(config, :indicies, x -> map(UInt16, x))
end

struct Pixel
  done::UInt32
  count::UInt32
  mu::NTuple{2,Float32}
  z::NTuple{2,Float32}
end

prog = ds.hashmap(
  :name, "The Separator",
  :window, ds.hashmap(:width, 1024, :height, 1024),
  :device, ds.hashmap(
    :features, ds.hashmap(
      v"1.0.0", [:pipeline_statistics_query]
    ),
    :extensions, ["VK_EXT_mesh_shader"]
  ),
  :pipelines, ds.hashmap(
    :render, ds.hashmap(
      :type, :graphics,
      :texture_file, *(@__DIR__, "/../../assets/texture.jpg"),
      :shaders, ds.hashmap(
        :vertex, *(@__DIR__, "/../shaders/mand.vert"),
        :fragment, *(@__DIR__, "/../shaders/mand.frag")
      ),
      :vertex, ds.hashmap(
        :type, Vertex
      ),
      :inputassembly, ds.hashmap(
        :topology, :triangles
      ),
      # FIXME: push constants must be at least 16 bytes.
      # Is it because of glsl 16 byte alignment?
      # But why does 12 fail and 20 seem to work?
      # FIXME: Asymmetry here: list of pcs in graphics, single map in compute.
      :pushconstants, [ds.hashmap(:stage, :fragment, :size, 16)],
      :bindings, [ds.hashmap(:type, :ssbo, :stage, :fragment)]
    ),
    :bufferinit, ds.hashmap(
      :type, :compute,
      :shader, ds.hashmap(:file, *(@__DIR__, "/../shaders/mand-region.comp")),
      :workgroups, [32, 32, 1],
      :pushconstants, ds.hashmap(:size, 20),
      :inputs, [],
      :outputs, [ds.hashmap(
        :type, :ssbo,
        :usage, :storage_buffer,
        :eltype, Pixel,
        :length, 2^20,
        # TODO: Calculate size for uniform and ssbo via eltype and length.
        :size, sizeof(Pixel) * 1024 * 1024,
        :memoryflags, :device_local,
        :queues, [:compute, :graphics]
      )],
    ),
    :separator, ds.hashmap(
      :type, :compute,
      :shader, ds.hashmap(:file, *(@__DIR__, "/../shaders/mand-iter.comp")),
      :workgroups, [32, 32, 1],
      :pushconstants, ds.hashmap(:size, 16),
      :inputs, [ds.hashmap(:type, :ssbo)],
      :outputs, [ds.hashmap(
        :type, :ssbo,
        :usage, :storage_buffer,
        :size, sizeof(Pixel) * 1024 * 1024,
        :memoryflags, :device_local,
        :queues, [:compute, :graphics]
      )],
    ),
    # :image, ds.hashmap(
    #   :shader, ds.hashmap(:file, *(@__DIR__, "/../shaders/mand-image.comp")),
    #   :workgroups, [32,32,1],
    #   :pushconstants, [ds.hashmap(:size, 16)],
    #   :inputs, [ds.hashmap(
    #     :type, :ssbo,
    #     :usage, :storage_buffer,
    #     :size, sizeof(Pixel) * 1024 * 1024,
    #     :memoryflags, :device_local,
    #     :queues, [:compute, :graphics]
    #   )],
    #   :outputs, [ds.hashmap(
    #     :type, :image,
    #     :format, vk.FORMAT_R8G8B8A8_UINT,
    #     :usage, [:storage, :sampled],
    #     :size, (1024, 1024),
    #     :memoryflags, :device_local,
    #     :queues, [:compute, :graphics]
    #   )],
    # )
  ),
  :verticies, [
    [-1.0f0, -1.0f0],
    [1.0f0, -1.0f0],
    [1.0f0, 1.0f0],
    [-1.0f0, 1.0f0]
  ],
  :indicies, [0, 3, 2, 2, 1, 0,]
)

##### Debugging tools

## Queries

function qp(system)
  pool = vk.create_query_pool(
    system.device,
    vk.QUERY_TYPE_PIPELINE_STATISTICS,
    1;
    pipeline_statistics=vk.QUERY_PIPELINE_STATISTIC_VERTEX_SHADER_INVOCATIONS_BIT |
    vk.QUERY_PIPELINE_STATISTIC_FRAGMENT_SHADER_INVOCATIONS_BIT
  )
end

## Debug pipelines (inputs and outputs visible to cpu).

function addusages(x::Symbol, xs...)
  ds.set(x, xs...).elements
end

function addusages(x, xs...)
  into(ds.set(xs...), x).elements
end

function enabletransfer(config)
  map(x -> ds.update(x, :usage, addusages, :transfer_src, :transfer_dst), config)
end

function debugpipeline(system, config, name)
  config = ds.assoc(get(config.pipelines, name), :name, name)

  config = ds.update(config, :inputs, enabletransfer)
  config = ds.update(config, :outputs, enabletransfer)

  tp.initpipeline(system, config)
end

function debugrun(system, p, inputs, T)
  ijoin = tp.run(p, inputs)
  outputs = take!(ijoin)

  fromdevicelocal(system, T, outputs[1])
end

### Mouse event handlers

function normalisezoom(z)
  exp(-z / 100)
end

function recentrezoom(Δzoom, offset, zoomcentre)
  znorm = normalisezoom(Δzoom)

  (znorm .* offset) .+ ((1 - znorm) .* zoomcentre)
end

function viewframe(frame, ev)
  if ds.containsp(ev, :drag)
    ds.update(frame, :offset, .+, get(ev, :drag))
  elseif ds.containsp(ev, :scroll)
    zoom = get(frame, :zoom)
    offset = get(frame, :offset)

    Δzoom = ds.getin(ev, [:scroll, :scroll])
    zoomcentre = ds.getin(ev, [:scroll, :position])

    ds.hashmap(
      :zoom, zoom + Δzoom,
      :offset, recentrezoom(Δzoom, offset, zoomcentre)
    )
  else
    @assert false "unreachable"
  end
end

struct MemoChannel
  cache::Ref{Any}
  ch
end

import Base.take!
function take!(ch::MemoChannel)
  try
    lock(ch.ch)
    if isready(ch.ch)
      ch.cache[] = take!(ch.ch)
    end
    return ch.cache[]
  finally
    unlock(ch.ch)
  end
end

function takelast(init, ch)
  MemoChannel(init, ch)
end

function topcs(window, coords)
  offset::Tuple{Float32,Float32} = get(coords, :offset)
  zoom::Float32 = normalisezoom(get(coords, :zoom))
  pcs = [(window[1], window[2], offset[1], offset[2], zoom)]
  pcs
end

function initpixels(win, coords)
end

function main()
  ## UI setup
  es.init()

  drag = ds.stream(
    ds.combinelast(ds.emptymap) ∘ mouse.drag(),
    ds.interleave(es.getstreams(:click, :position))
  )

  zoom = ds.stream(
    mouse.zoom() ∘ map(x -> ds.update(x, :scroll, y -> y isa Tuple ? y[2] : y)),
    ds.interleave(es.getstreams(:position, :scroll))
  )

  viewport = ds.stream(
    ds.scan(viewframe, ds.hashmap(:zoom, 0, :offset, (0.5, 0.5))),
    ds.interleave(ds.hashmap(:scroll, zoom, :drag, drag))
  )

  viewstate = takelast(
    ds.hashmap(:zoom, 0, :offset, (0, 0)),
    ds.subscribe(viewport; buffer=1)
  )

  coords = take!(viewstate)

  ## VK wrapper setup

  system, config = init.setup(load(prog), window)

  frames = system.spec.swapchain.images

  dev = get(system, :device)

  vb, ib = vertex.buffers(system, config.verticies, config.indicies)

  pipelines = tp.buildpipelines(system, config)

  ## Render loop
  framecounter::UInt32 = 0
  itercount::UInt32 = 500

  new = true
  current_frame = []

  # FIXME: hardcoded window size
  w::Tuple{UInt32,UInt32} = (1024, 1024)

  renderstate = ds.hashmap(
    :vertexbuffer, vb,
    :indexbuffer, ib
  )

  while true
    window.poll()
    framecounter += 1

    if new || current_frame === ds.emptymap
      @info "new"
      framecounter = 1

      @info topcs(w, coords)
      ijoin = tp.run(pipelines.bufferinit, ([], topcs(w, coords)))
      current_frame = take!(ijoin)

      ex = fromdevicelocal(system, Pixel, current_frame[1])

      new = false
    end

    sep = tp.run(pipelines.separator, (current_frame, [(w[1], w[2], itercount)]))

    # @info framecounter
    gjoin = tp.run(pipelines.render, ds.assoc(renderstate,
      :pushconstants, [(w[1], w[2], UInt32(framecounter))],
      :bindings, current_frame
    ))

    # Check for updated inputs.
    #
    # This is way too pedantic, there has to be a cleaner way to talk about such
    # a common pattern.
    ctemp = take!(viewstate)
    new = ctemp !== coords
    coords = ctemp
    # wtemp = window.size(w)
    # new = new || wtemp != winsize
    # winsize = wtemp

    # sleep(0.01)

    sig = take!(gjoin)
    if sig === :closed
      break
    elseif sig === :skip
      sleep(0.08)
    else
      next_frame = take!(sep)

      Threads.@spawn begin
        Sync.wait_semaphores(system.device, [sig, next_frame.wait])
        current_frame
        @info "discard"
      end

      current_frame = next_frame
    end
  end

  ds.mapvals(tp.teardown, pipelines)
  window.shutdown()
  GC.gc()
end

# main()
