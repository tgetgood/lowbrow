import graphics
import window
import hardware as hw
import resources as rd
import commands
import framework as fw
import pipeline as gp
import render as draw
import eventsystem as es
import mouse

import DataStructures as ds
import Vulkan as vk

struct Vertex
  position::NTuple{2, Float32}
end

function vert(pos)
  Vertex(tuple(pos...))
end

function load(config)
  config = ds.update(config, :verticies, x -> map(vert, x))
  config = ds.update(config, :indicies, x -> map(UInt16, x))
  config = ds.assoc(config, :vertex_input_state, rd.vertex_input_state(Vertex))
end

struct Pixel
  done::Bool
  count::Int
  mu::NTuple{2, Float64}
  z::NTuple{2, Float64}
end

prog = ds.hashmap(
  :name, "The Separator",
  :device, ds.hashmap(
    :features, [:shader_float_64]
  ),
  :render, ds.hashmap(
    :texture_file, *(@__DIR__, "/../../assets/texture.jpg"),
    :shaders, ds.hashmap(
      :vertex, *(@__DIR__, "/../shaders/mand.vert"),
      :fragment, *(@__DIR__, "/../shaders/mand.frag")
    ),
    :inputassembly, ds.hashmap(
      :topology, :triangles
    )
  ),
  :compute, ds.hashmap(
    :bufferinit, ds.hashmap(
      :shader, ds.hashmap(
        :stage, :compute,
        :file, *(@__DIR__, "/../shaders/mand-region.comp")
      ),
      :pushconstants, [ds.hashmap(:stage, :compute, :size, 40)],
      :descriptorsets, ds.hashmap(
        :count, 1,
        :bindings, [
          ds.hashmap(
            :usage, vk.DESCRIPTOR_TYPE_STORAGE_BUFFER,
            :stage, vk.SHADER_STAGE_COMPUTE_BIT
          )
        ]
      )
    ),

  ),
  :model, ds.hashmap(
    :loader, load,
    :vertex_type, Vertex
  ),
  :verticies, [
    [-1.0f0, -1.0f0],
    [1.0f0, -1.0f0],
    [1.0f0, 1.0f0],
    [-1.0f0, 1.0f0]
  ],
  :indicies, [0, 3, 2, 2, 1, 0,]
)

### Mouse event handlers

function normalisezoom(z)
  exp(-z/100)
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

function pixel_buffers(system, frames, winsize)
  ds.into(
    ds.emptyvector,
    map(_ -> hw.buffer(system, ds.hashmap(
      :usage, vk.BUFFER_USAGE_STORAGE_BUFFER_BIT,
      :size, sizeof(Pixel) * winsize.width * winsize.height,
      :memoryflags, vk.MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
      :queues, [:compute]
    ))),
    1:frames
  )
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
  new = true

  ## VK wrapper setup

  config = graphics.configure(load(prog))

  system, config = graphics.instantiate(graphics.staticinit(config), config)

  dev = get(system, :device)

  config = fw.buffers(system, config)

  frames = get(config, :concurrent_frames)

  w = get(system, :window)
  winsize = window.size(w)

  ## Compute

  initconfig = ds.getin(config, [:compute, :bufferinit])

  initconfig = ds.update(
    initconfig, :descriptorsets, x -> merge(x, fw.descriptors(dev, x))
  )

  initconfig = ds.assoc(
    initconfig, :pipeline, gp.computepipeline(dev, initconfig)
  )

  pbuffs = []

  ## Render loop
  framecounter = 0

  graphics.renderloop(system, config) do i, renderstate
    framecounter += 1
    if new
      @info "new"
      pbuffs = pixel_buffers(system, frames, winsize)
      fw.binddescriptors(dev, get(initconfig, :descriptorsets), [pbuffs])

      pipeline = ds.getin(initconfig, [:pipeline, :pipeline])
      layout = ds.getin(initconfig, [:pipeline, :layout])

      pcvs = [(
        winsize.width, winsize.height, get(coords, :offset), get(coords, :zoom)
      )]

      # Prevent GC.
      initconfig = ds.assoc(initconfig, :pushconstantvalues, pcvs)

      initsem = commands.cmdseq(system, :compute) do cmd
        vk.cmd_bind_pipeline(cmd, vk.PIPELINE_BIND_POINT_COMPUTE, pipeline)
        vk.cmd_push_constants(
          cmd,
          layout,
          vk.SHADER_STAGE_COMPUTE_BIT,
          0,
          sizeof(pcvs),
          Ptr{Nothing}(pointer(pcvs))
        )
        vk.cmd_bind_descriptor_sets(
          cmd,
          vk.PIPELINE_BIND_POINT_COMPUTE,
          layout,
          0,
          ds.getin(initconfig, [:descriptorsets, :sets]),
          []
        )

        vk.cmd_dispatch(
          cmd,
          Int(ceil(winsize.width/32)), Int(ceil(winsize.height/32)), 1
        )
      end

      initsems = [initsem]
      new = false
    else
      initsems = []
    end



    # Check for updated inputs.
    #
    # This is way too pedantic, there has to be a cleaner way to talk about such
    # a common pattern.
    ctemp = take!(viewstate)
    new = ctemp !== coords
    coords = ctemp
    wtemp = window.size(w)
    new = new || wtemp != winsize
    winsize = wtemp

    return renderstate
  end

end

main()
