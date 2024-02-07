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
    :features, [] #[:shader_float_64]
  ),
  :window, hashmap(:width, 1024, :height, 1024),
  :render, ds.hashmap(
    :texture_file, *(@__DIR__, "/../../assets/texture.jpg"),
    :shaders, ds.hashmap(
      :vertex, *(@__DIR__, "/../shaders/mand.vert"),
      :fragment, *(@__DIR__, "/../shaders/mand.frag")
    ),
    :inputassembly, ds.hashmap(
      :topology, :triangles
    ),
    # FIXME: push constants must be at least 16 bytes.
    # Is it because of glsl 16 byte alignment?
    # But why does 12 fail and 20 seem to work?
    :pushconstants, [ds.hashmap(:stage, :fragment, :size, 16)],
    :descriptorsets, ds.hashmap(
      :bindings, [ds.hashmap(:type, :storage_buffer, :stage, :fragment)]
    )
  ),
  :compute, ds.hashmap(
    :bufferinit, ds.hashmap(
      :shader, ds.hashmap(:file, *(@__DIR__, "/../shaders/mand-region.comp")),
      :workgroups, [32,32,1],
      :pushconstants, [ds.hashmap( :size, 20)],
      :inputs, [],
      :outputs, [ds.hashmap(:type, :ssbo,
        :usage, :storage_buffer,
        :size, sizeof(Pixel) * 1024 * 1024,
        :memoryflags, :device_local,
        :queues, [:compute, :graphics]
      )],
    ),
    :separator, ds.hashmap(
      :shader, ds.hashmap(:file, *(@__DIR__, "/../shaders/mand-iter.comp")),
      :workgroups, [32,32,1],
      :pushconstants, [ds.hashmap(:size, 16)],
      :inputs, [ds.hashmap(:type, :ssbo)],
      :outputs, [ds.hashmap(
        :type, :ssbo,
        :usage, :storage_buffer,
        :size, sizeof(Pixel) * 1024 * 1024,
        :memoryflags, :device_local,
        :queues, [:compute, :graphics]
      )],
    )
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
      :usage, :storage_buffer,
      :size, sizeof(Pixel) * winsize.width * winsize.height,
      :memoryflags, :device_local,
      :queues, [:compute]
    ))),
    1:frames
  )
end

function main()
  # cleanup
  window.shutdown()

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

  config = graphics.configure(load(prog))

  frames = get(config, :concurrent_frames)

  config = ds.associn(config, [:render, :descriptorsets, :count], frames)

  system = graphics.staticinit(config)

  dev = get(system, :device)

  dsets = fw.descriptors(dev, ds.getin(config, [:render, :descriptorsets]))

  config = ds.updatein(config, [:render, :descriptorsets], merge, dsets)

  system, config = graphics.instantiate(system, config)

  config = fw.buffers(system, config)

  # FIXME: This is a trap I'm going to fall into over and over.
  # REVIEW: I need to encapsulate pipelines as wholes. graphics and compute.
  config = merge(config, get(config, :render))

  hardwaredesc = ds.selectkeys(system, [:qf_properties])

  ## Compute pipelines

  init = fw.computepipeline(
    dev,
    merge(ds.getin(config, [:compute, :bufferinit]), hardwaredesc)
  )

  sep = fw.computepipeline(
    dev,
    merge(ds.getin(config, [:compute, :separator]), hardwaredesc)
  )

  ## Render loop
  framecounter = 0
  itercount = 50

  new = true
  current_frame = ds.emptymap

  renderstate = fw.assemblerender(system, config)

  iters = 600
  t0 = time()

  for i in 1:iters
    framecounter += 1

    if new || current_frame === ds.emptymap
      @info "new"
      framecounter = 1

      initout = fw.runcomputepipeline(system, init, [])

      @info initout
      current_frame = initout[1]

      new = false
    else
      initsems = []
    end

    pcs = [(1024, 1024, framecounter * itercount)]
    sepouts = fw.runcomputepipeline(system, sep, [current_frame], pcs)

    renderstate = ds.assoc(renderstate, :pushconstantvalues, pcs)

    fw.rungraphicspipeline(system, renderstate)

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


    if framecounter % 1000 == 0
      @info pcs
    end
  end

  t1 = time()
  @info "Average fps: " * string(round(iters / (t1 - t0)))
end

main()
