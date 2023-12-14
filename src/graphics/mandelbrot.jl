import graphics
import hardware as hw
import resources as rd
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

prog = ds.hashmap(
  :name, "The Separator",
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

struct MemoChannel{T}
  cache::Ref{T}
  ch::Channel{T}
end

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
  MemoChannel(Ref(init), ch)
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

  config = fw.buffers(system, config)

  framecount = get(config, :concurrent_frames)

  ## Compute

  images = ds.into(
    ds.emptyvector,
    map(_ -> hw.createimage(system, ds.hashmap(
      :format, vk.FORMAT_R64G64B64_SFLOAT,
      :queres, [:compute, :graphics],
      :sharingmode, vk.SHARING_MODE_CONCURRENT,
      :size, 1200*1200*8*3, #FIXME!!!
      :usage, vk.IMAGE_USAGE_STORAGE_BIT | vk.IMAGE_USAGE_SAMPLED_BIT,
      :memoryflags, vk.MEMORY_PROPERTY_DEVICE_LOCAL_BIT

    ))),
    1:framecount
  )

  ## Render loop
  graphics.renderloop(system, config) do i, renderstate
    if new
      # reset image buffer and iteration counter (zero out)
    end

    temp = take!(viewstate)
    new = temp !== coords
    coords = temp

    return renderstate
  end

end


# main()
