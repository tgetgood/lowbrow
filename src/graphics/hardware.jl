module hardware

import window
import GLFW

import Base: get

import Vulkan as vk
import DataStructures as ds
import DataStructures: getin, assoc, hashmap, into, emptyvector, emptymap

import resources: bufferusagebits, memorypropertybits, sharingmodes, imageusagebits

abstract type VKSystem end

struct VKRender <: VKSystem
  instance::vk.Instance
  physical_device::vk.PhysicalDevice
  device::vk.Device
  window::GLFW.Window
  surface::vk.SurfaceKHR
  queues::ds.Map
  commandpools::ds.Map
end

##### Seems I'll want these eventually, but they're just reminders at present.
struct VKHeadlessRender <: VKSystem
end

struct VKComputeOnly <: VKSystem
end

function get(x::VKSystem, k::Symbol, default)
  if hasproperty(x, k)
    getproperty(x, k)
  else
    default
  end
end

get(x::VKSystem, k::Symbol) = get(x, k, nothing)

function containsall(needles, hay)::Bool
  return [nothing] == indexin([nothing], indexin(needles, hay))
end

"""
Returns a hashmap isomorphic to s. It's probably better to override fns for
vk.HighLevelStruct to treat them like maps, rather than actually cast
everything.
"""
function srecord(s::T) where T
  into(emptymap, map(k -> (k, getproperty(s, k))), fieldnames(T))
end

function probeapi()
  hashmap(
    :version, vk.unwrap(vk.enumerate_instance_version()),
    :extensions, vk.unwrap(vk.enumerate_instance_extension_properties()),
    :layers, vk.unwrap(vk.enumerate_instance_layer_properties())
  )
end

function probedevices(instance, query)
end

function probe(requirements)
  vk.unwrap(vk.enumerate_instance_extension_properties())
end

function instance(_, config)
  ic = get(config, :instance)
  validationlayers = get(ic, :validation, [])
  extensions::Vector = get(ic, :extensions, [])

  @assert containsall(
    extensions,
    map(
      x -> x.extension_name,
      vk.unwrap(vk.enumerate_instance_extension_properties())
    )
  ) "unsupported extensions required."

  if get(config, :dev_tools)
    @assert containsall(
      validationlayers,
      map(
        x -> x.layer_name,
        vk.unwrap(vk.enumerate_instance_layer_properties())
      )
    ) "unsupported validation layers required."
  end

  appinfo = vk.ApplicationInfo(
    v"0.0.0",
    v"0.0.0",
    v"1.3";
    application_name=get(config, :name, "dev"),
    engine_name="TBD"
  )

  inst = vk.unwrap(vk.create_instance(
    validationlayers,
    extensions;
    next=get(config, :debuginfo, C_NULL),
    application_info=appinfo
  ))

  return hashmap(:instance, inst)
end

function findgraphicsqueue(device)
  try
    vk.find_queue_family(device, vk.QUEUE_GRAPHICS_BIT)
  catch e
    return nothing
  end
end

function findpresentationqueue(pdevice, surface)
  first(
    filter(
      i -> vk.unwrap(vk.get_physical_device_surface_support_khr(
        pdevice,
        i,
        surface
      )),
      0:length(vk.get_physical_device_queue_family_properties(pdevice))-1
    )
  )
end

function findtransferqueue(qfproperties)
  transferqs = into(
    emptyvector,
    ds.mapindexed((i, x) -> (x, i - 1))
    ∘
    filter(x -> (x[1].queue_flags & vk.QUEUE_TRANSFER_BIT).val > 0)
    ,
    qfproperties
  )

  # REVIEW: Is this productive? I.e. could there be a case where we have an
  # async compute queue that can be used for transfers, but no dedicated
  # transfer queue? In theory yes. But if we did only have compute and graphics
  # queues, which one do we want to transfer on? That would be load dependent.
  nog = filter(
    x -> (x[1].queue_flags & vk.QUEUE_GRAPHICS_BIT).val == 0,
    transferqs
  )

  noc = filter(
    x -> (x[1].queue_flags & vk.QUEUE_COMPUTE_BIT).val == 0,
    nog
  )

  if ds.emptyp(noc)
    if ds.emptyp(nog)
      first(transferqs)[2]
    else
      first(nog)[2]
    end
  else
    first(noc)[2]
  end
end

function findcomputequeue(qfproperties)
  computeqs = into(
    emptyvector,
    ds.mapindexed((i, x) -> (x, i - 1))
    ∘
    filter(x -> (x[1].queue_flags & vk.QUEUE_COMPUTE_BIT).val > 0)
    ,
    qfproperties
  )

  if ds.emptyp(computeqs)
    @error "device does not support compute. Vulkan requires that it does."
    throw("Unreachable")
  end

  dedicated = filter(
    x -> (x[1].queue_flags & vk.QUEUE_GRAPHICS_BIT).val == 0,
    computeqs
  )

  if ds.emptyp(dedicated)
    first(computeqs)[2]
  else
    first(dedicated)[2]

  end
end

function swapchainsupport(system)
  dev = get(system, :physicaldevice)
  surface = get(system, :surface)

  # capabilities = vk.get_physical_device_surface_capabilities_khr(dev, surface)
  formats = vk.unwrap(vk.get_physical_device_surface_formats_khr(dev; surface))
  modes = vk.unwrap(
    vk.get_physical_device_surface_present_modes_khr(dev; surface)
  )

  return length(formats) > 0 && length(modes) > 0
end


function checkdevice(system, config)
  pdev = get(system, :physicaldevice)
  features = vk.get_physical_device_features(pdev)

  return getin(system, [:queues, :graphics]) !== nothing &&
         getin(system, [:queues, :presentation]) !== nothing &&
         getin(system, [:queues, :transfer]) !== nothing &&
         getin(system, [:queues, :compute]) !== nothing &&
         all(
           map(x -> getproperty(features, x),
             ds.getin(config, [:device, :features]))
         ) &&
         swapchainsupport(system) &&
         containsall(
           getin(config, [:device, :extensions], []),
           map(
             x -> x.extension_name,
             vk.unwrap(vk.enumerate_device_extension_properties(pdev))
           )
         ) &&
         containsall(
           getin(config, [:device, :validation], []),
           map(
             x -> x.layer_name,
             vk.unwrap(vk.enumerate_device_layer_properties(pdev))
           )
         )
end

function findformat(system, config)
  filtered = filter(
    x -> x.format == getin(config, [:swapchain, :format]) &&
      x.color_space == getin(config, [:swapchain, :colourspace]),
    get(system, :surface_formats)
  )

  if length(filtered) == 0
    nothing
  else
    first(filtered)
  end
end

function findextent(system, config)
  sc = get(system, :surface_capabilities)

  win = get(system, :window)

  vk.Extent2D(
    clamp(win.width, sc.min_image_extent.width, sc.max_image_extent.width),
    clamp(win.height, sc.min_image_extent.height, sc.max_image_extent.height)
  )
end

function findpresentmode(system, config)
  modes = get(system, :surface_present_modes)

  if length(modes) == 0
    nothing
  else
    first(modes)
  end
end

const queuefinders = hashmap(
  :graphics, findgraphicsqueue,
  # a device doesn't have a "presentation queue", it may have a queue that can
  # present to a given surface. Thus `findpresentationqueue` is different in kind.
  # :presentation, findpresentationqueue,
  :transfer, findtransferqueue,
  :compute, findcomputequeue
)

function findqueues(system)
  pdevice = get(system, :physicaldevice)
  qfproperties = get(system, :qf_properties)
  hashmap(
    :graphics, findgraphicsqueue(pdevice),
    :presentation, findpresentationqueue(pdevice, get(system, :surface)),
    :transfer, findtransferqueue(qfproperties),
    :compute, findcomputequeue(qfproperties)
  )
end

function multisamplemax(device)
  props = vk.get_physical_device_properties(device)
  depth = props.limits.framebuffer_depth_sample_counts
  colour = props.limits.framebuffer_color_sample_counts

  vk.SampleCountFlag(1 << (ndigits((depth&colour).val, base=2) - 1))
end

function surfaceinfo(system)
  ds.hashmap(
    :surface_formats, vk.unwrap(vk.get_physical_device_surface_formats_khr(
      get(system, :physicaldevice);
      surface=get(system, :surface)
    )),
    :surface_capabilities, vk.unwrap(
      vk.get_physical_device_surface_capabilities_khr(
        get(system, :physicaldevice),
        get(system, :surface)
      )
    ),
    :surface_present_modes, vk.unwrap(
      vk.get_physical_device_surface_present_modes_khr(
        get(system, :physicaldevice);
        surface=get(system, :surface)
      )
    )
  )
end

function pdevice(system, config)
  potential = into(
    emptyvector,
    map(x -> merge(system, hashmap(
      :physicaldevice, x,
      :qf_properties, vk.get_physical_device_queue_family_properties(x),
      :memoryproperties, vk.get_physical_device_memory_properties(x),
      :max_msaa, multisamplemax(x)
    )))
    ∘
    map(x -> merge(x, surfaceinfo(x)))
    ∘
    map(x -> assoc(x, :queues, findqueues(x)))
    ∘
    filter(system -> checkdevice(system, config)),
    vk.unwrap(vk.enumerate_physical_devices(get(system, :instance)))
  )

  if ds.emptyp(potential)
    throw("No suitable hardware found. Cannot continue.")
  else
    first(potential)
  end
end

function getqueue(system, queue, nth=1)
  vk.get_device_queue(
    get(system, :device),
    getin(system, [:queues, queue]),
    nth-1
  )
end

function createdevice(system, config)
  system = pdevice(system, config)
  queues = get(system, :queues)
  pdev = get(system, :physicaldevice)

  # Create one queue per op type, even if families overlap.
  # FIXME: We need to validate the hardware supports the number of queues we're
  # requesting.
  # rf(acc, e) = ds.containsp(acc, e) ? ds.assoc(acc, e, ds.conj(get(acc, e), 1.0)) : ds.assoc(acc, e, [1.0])

  # qs2c = ds.reduce(rf, ds.emptymap, ds.vals(queues))
  # qcis = ds.into!([], map(qf -> vk.DeviceQueueCreateInfo(ds.key(qf), ds.val(qf))), qs2c)

  qs2c = ds.into(ds.emptyset, ds.vals(queues))
  qcis = ds.into!([], map(qf -> vk.DeviceQueueCreateInfo(qf, [1.0])), qs2c)

  dci = vk.DeviceCreateInfo(
    qcis,
    getin(config, [:device, :validation], []),
    getin(config, [:device, :extensions], []);
    enabled_features=
    vk.PhysicalDeviceFeatures(ds.getin(config, [:device, :features])...),
    # FIXME: Confirm that these features are available before enabling.
    # How do I do that?
    # Not urgent since vulkan 1.2+ requires :timeline_semaphore.
    next=vk.PhysicalDeviceVulkan12Features(
      ds.getin(config, [:device, :vk12features])...;
      next=vk.PhysicalDeviceVulkan13Features(
        ds.getin(config, [:device, :vk13features])...
      )
    )
  )

  assoc(system, :device, vk.unwrap(vk.create_device(pdev, dci)))
end

function createswapchain(system, config)
  format = findformat(system, config)
  extent = findextent(system, config)

  # TODO: Use createinfo structs. Stop relying on Vulkan.jl wrapper functions
  # since I'm probably going to stop using it.
  # sci = vk._SwapchainCreateInfoKHR(

  # )

  sc = vk.create_swapchain_khr(
    get(system, :device),
    get(system, :surface),
    getin(config, [:swapchain, :images]),
    format.format,
    format.color_space,
    extent,
    1, # image arrays
    vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
    vk.SHARING_MODE_EXCLUSIVE, # <- FIXME: don't hardcode this
    [],
    vk.SURFACE_TRANSFORM_IDENTITY_BIT_KHR,
    vk.COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
    findpresentmode(system, config),
    true;
    old_swapchain=get(system, :swapchain, C_NULL)
  )

  hashmap(:swapchain, vk.unwrap(sc), :extent, extent, :format, format)
end

function imageview(system, config, image)
  vk.unwrap(vk.create_image_view(
    get(system, :device),
    get(image, :image),
    vk.IMAGE_VIEW_TYPE_2D,
    get(config, :format),
    vk.ComponentMapping(
      vk.COMPONENT_SWIZZLE_IDENTITY,
      vk.COMPONENT_SWIZZLE_IDENTITY,
      vk.COMPONENT_SWIZZLE_IDENTITY,
      vk.COMPONENT_SWIZZLE_IDENTITY
    ),
    vk.ImageSubresourceRange(
      get(config, :aspect, vk.IMAGE_ASPECT_COLOR_BIT),
      0,
      get(image, :miplevels, 1),
      0,
      1
    )
  ))
end

function commandpool(dev, qf, flags=vk.CommandPoolCreateFlag(0))
  vk.unwrap(vk.create_command_pool(dev, qf; flags=flags))
end

function createcommandpools(system, config)
  dev = get(system, :device)
  qfs = collect(Set(ds.vals(get(system, :queues))))

  hashmap(
    :commandpools,
    ds.zipmap(
      qfs,
      map(qf -> commandpool(
          dev, qf, vk.COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT
        ), qfs))
  )
end

function createdescriptorpools(system, config)
  n = get(config, :concurrent_frames)

  hashmap(
    :descriptorpool,
    vk.unwrap(vk.create_descriptor_pool(
      get(system, :device),
      2*n,
      [
        vk.DescriptorPoolSize(vk.DESCRIPTOR_TYPE_UNIFORM_BUFFER, n),
        vk.DescriptorPoolSize(vk.DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, n)
      ]
    ))
  )
end

"""
Returns command pool to use for given queue family `qf`.
"""
function getpool(system, qf)
  getin(system, [:commandpools, getin(system, [:queues, qf])])
end

function findmemtype(system, config)
  properties = get(system, :memoryproperties)

  mask = get(config, :typemask)
  flags = get(config, :flags)

  mt = into(
    [],
    ds.mapindexed((i, x) -> (x, i-1))
    ∘ filter(x -> (mask & (1 << x[2])) > 0)
    ∘ filter(x -> (x[1].property_flags & flags) == flags)
    ,
    properties.memory_types[1:properties.memory_type_count]
  )

  @assert length(mt) > 0

  mt[1]
end

# How do we catch typographical errors in a dynamic language?

struct Typo end
typo = Typo()

function orlist(bitmap, x::Symbol)
  get(bitmap, x, typo)
end

# OR is such a basic monoid, but because |() needs to return a *typed* zero, we
# can't treat it as such. If you're going to insist on a type system of this
# sort, the identity should be its own type.
#
# I've run into the same problem with datastructures. Making the empty list,
# empty map, empty set, &c. into singleton types is the only way I've figured
# out how to make generic sequence operations play nice with type inference.
#
# It doesn't matter in this case since the bitmasks Vulkan uses will cast the
# zero to their own empty set
bitor() = 0
bitor(x) = x
bitor(x, y) = x | y

function orlist(bitmap, xs)
  flags = ds.transduce(map(k -> get(bitmap, k, typo)), bitor, xs)
  @assert flags !== 0
  flags
end

function buffer(system, config)
  dev = get(system, :device)

  queues = into(ds.emptyset, map(x -> getin(system, [:queues, x]), get(config, :queues)))

  mode = get(sharingmodes, get(config, :sharingmode,
    ds.count(queues) == 1 ? :exclusive : :concurrent
  ))

  bci = vk.BufferCreateInfo(
    get(config, :size),
    vk.BufferUsageFlag(orlist(bufferusagebits, get(config, :usage))),
    mode,
    into([], queues)
  )

  buffer = vk.unwrap(vk.create_buffer(dev, bci))

  memreq = vk.get_buffer_memory_requirements(dev, buffer)

  req = ds.hashmap(
    :typemask, memreq.memory_type_bits,
    :flags, orlist(memorypropertybits, get(config, :memoryflags))
  )

  memtype = findmemtype(system, req)

  memory = vk.unwrap(vk.allocate_memory(dev, memreq.size, memtype[2]))

  vk.unwrap(vk.bind_buffer_memory(dev, buffer, memory, 0))

  hashmap(:buffer, buffer, :memory, memory, :size, memreq.size)
end

function transferbuffer(system, size)
  buffer(
    system,
    ds.hashmap(
      :size, size,
      :usage, [:transfer_src, :transfer_dst],
      :queues, [:transfer],
      :memoryflags, [:host_coherent, :host_visible]
    )
  )
end

function commandbuffers(
  dev::vk.Device, pool::vk.CommandPool, n::Int, level=vk.COMMAND_BUFFER_LEVEL_PRIMARY
)
  vk.unwrap(
    vk.allocate_command_buffers(dev, vk.CommandBufferAllocateInfo(pool, level, n))
  )
end

function commandbuffers(system, n::Int, qf, level=vk.COMMAND_BUFFER_LEVEL_PRIMARY)
  commandbuffers(get(system, :device), getpool(system, qf), n, level)
end

function createimage(system, config)
  dev = get(system, :device)
  samples = get(config, :samples, vk.SAMPLE_COUNT_1_BIT)

  queues::Vector{UInt32} = ds.into(
    [], map(x -> ds.getin(system, [:queues, x])), get(config, :queues)
  )

  sharingmode = get(sharingmodes, get(config, :sharingmode,
    length(queues) == 1 ? :exclusive : :concurrent
  ))

  image = vk.unwrap(vk.create_image(
    dev,
    vk.IMAGE_TYPE_2D,
    get(config, :format),
    vk.Extent3D(get(config, :size)..., 1),
    get(config, :miplevels, 1),
    1,
    samples,
    get(config, :tiling, vk.IMAGE_TILING_OPTIMAL),
    orlist(imageusagebits, get(config, :usage)),
    sharingmode,
    queues,
    get(config, :layout, vk.IMAGE_LAYOUT_UNDEFINED)
  ))

  memreq = vk.get_image_memory_requirements(dev, image)

  memory = vk.unwrap(vk.allocate_memory(
    dev,
    memreq.size,
    findmemtype(system, ds.hashmap(
      :typemask, memreq.memory_type_bits,
      :flags, orlist(memorypropertybits, get(config, :memoryflags))
    ))[2]
  ))

  vk.unwrap(vk.bind_image_memory(dev, image, memory, 0))

  hashmap(
    :image, image,
    :memory, memory,
    :size, memreq.size,
    :miplevels, get(config, :miplevels, 1),
    :samples, samples,
    :format, get(config, :format),
    :resolution, get(config, :size)
  )
end

function colourresources(system, config)
  format = getin(config, [:swapchain, :format])
  ext = get(system, :extent)

  image = createimage(system, hashmap(
    :size, [ext.width, ext.height],
    :format, format,
    :samples, get(system, :max_msaa),
    :memoryflags, :device_local,
    :queues, [:graphics],
    :usage, [:transient_attachment, :colour_attachment]
  ))

  view = imageview(system, hashmap(:format, format), image)

  assoc(image, :view, view)
end

function texturesampler(system, config)
  props = vk.get_physical_device_properties(get(system, :physicaldevice))
  anis = props.limits.max_sampler_anisotropy

  vk.unwrap(vk.create_sampler(
    get(system, :device),
    vk.FILTER_LINEAR,
    vk.FILTER_LINEAR,
    vk.SAMPLER_MIPMAP_MODE_LINEAR,
    vk.SAMPLER_ADDRESS_MODE_REPEAT,
    vk.SAMPLER_ADDRESS_MODE_REPEAT,
    vk.SAMPLER_ADDRESS_MODE_REPEAT,
    0,
    true,
    anis,
    false,
    vk.COMPARE_OP_ALWAYS,
    0,
    get(config, :miplevels, 1),
    vk.BORDER_COLOR_INT_OPAQUE_BLACK,
    false
  ))
end

function finddepthformats(system, config)
  pdev = get(system, :physicaldevice)
  reqs = get(config, :features)

  function getfeats(x)
    t = get(config, :tiling)
    if t == vk.IMAGE_TILING_LINEAR
      x.linear_tiling_features
    elseif t == vk.IMAGE_TILING_OPTIMAL
      x.optimal_tiling_features
    end
  end

  candidates = ds.into(
    [],
    map(x -> (x, vk.get_physical_device_format_properties(pdev, x)))
    ∘
    filter(x -> (reqs & getfeats(x[2])) > 0),
    get(config, :formats)
  )

  @assert length(candidates) > 0

  return first(candidates)[1]
end

optdepthformat(system) = finddepthformats(
  system,
  hashmap(
    :tiling, vk.IMAGE_TILING_OPTIMAL,
    :features, vk.FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT,
    :formats, [
      vk.FORMAT_D32_SFLOAT,
      vk.FORMAT_D24_UNORM_S8_UINT,
      vk.FORMAT_D32_SFLOAT_S8_UINT,
    ]
  )
)

function depthresources(system, config)
  format = optdepthformat(system)

  ex = get(system, :extent)
  image = createimage(system,
    hashmap(
      :tiling, vk.IMAGE_TILING_OPTIMAL,
      :format, format,
     :samples, get(system, :max_msaa),
      :size, [ex.width, ex.height],
      :usage, :depth_stencil_attachment,
      :queues, [:graphics],
      :memoryflags, :device_local
    )
  )

  view = imageview(
    system,
    hashmap(
      :format, format,
      :aspect, vk.IMAGE_ASPECT_DEPTH_BIT
    ),
    image
  )

  assoc(image, :view, view)
end

function createimageviews(system, config)
  dev = get(system, :device)

  hashmap(
    :imageviews, into(
      emptyvector,
      map(image -> imageview(
        system,
        hashmap(:format, findformat(system, config).format),
        hashmap(:image, image)
      )),
      vk.unwrap(vk.get_swapchain_images_khr(dev, get(system, :swapchain)))
    ),
    :depth, depthresources(system, config),
    :colour, colourresources(system, config)
  )
end

function timelinesemaphore(dev::vk.Device, init=1)
  vk.unwrap(vk.create_semaphore(
    dev,
    vk.SemaphoreCreateInfo(
      next=vk.SemaphoreTypeCreateInfo(
        vk.SEMAPHORE_TYPE_TIMELINE,
        UInt(init)
      )
    )
  ))
end

function tick(ss::vk.SemaphoreSubmitInfo)
  vk.SemaphoreSubmitInfo(ss.semaphore, ss.value + 1, ss.device_index)
end

"""
Takes a function and args and applies it in a thread, returning a channel which
will eventually yield the result.
"""
function thread(f, args...)
  # TODO: Flag to disable in production
  # HACK: This is slow as hell. Do not use except in dire straights.
  # invocation_trace = stacktrace()
  invocation_trace = "disabled"

  join = Channel()
  Threads.@spawn begin
      try
        put!(join, f(args...))
      catch e
        ds.handleerror(e)
        print(stderr, "\n Thread launched from:\n")
        # FIXME: This doesn't seem to be lexically captured, but gets
        # dynamically bound to the most recent invocation of `thread`.
        show(stderr, "text/plain", invocation_trace)
      end
  end
  return join
end

end
