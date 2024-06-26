module pipeline

import Vulkan as vk
import DataStructures as ds
import DataStructures: getin, emptymap, hashmap, emptyvector, into, mapindexed

import ..hardware as hw
import ..resources: shaderstagebits
import ..resources as rd

function glslc(src, out)
  run(`glslc $src -o $out`)
end

function compileshader(device, fname)
  (tmp, io) = mktemp()
  close(io)
  glslc(fname, tmp)
  bin = read(tmp)
  size = length(bin)
  code = reinterpret(UInt32, bin)
  vk.unwrap(vk.create_shader_module(device, size, code))
end

function shader(device, fname, stage, entry="main")
  vk.PipelineShaderStageCreateInfo(
    get(shaderstagebits, stage),
    compileshader(device, fname),
    entry
  )
end

function shaders(device, config)
  ds.into!([], map(e -> shader(device, ds.val(e), ds.key(e))), config)
end

function pushconstantrange(x)
 vk.PushConstantRange(
   get(shaderstagebits, get(x, :stage)), get(x, :offset, 0), get(x, :size)
 )
end

##### Compute Pipelines

# TODO: Map this over multiple configs for multiple pipelines (minimise vk calls).
function computepipeline(
  system, shaderconfig, descriptorsetlayout, pushconstantconfigs=[]
)
  dev = system.device

  pcrs = ds.into!([], map(pushconstantrange), pushconstantconfigs)

  pipelinelayout = vk.unwrap(vk.create_pipeline_layout(
    dev, [descriptorsetlayout], pcrs
  ))

  computeshader = shader(
    dev,
    get(shaderconfig, :file),
    get(shaderconfig, :stage, :compute) # compute pipeline!
  )

  ds.hashmap(
    :layout, pipelinelayout,
    :bindpoint, :compute,
    :pipeline, vk.unwrap(vk.create_compute_pipelines(
      dev,
      [vk.ComputePipelineCreateInfo(computeshader, pipelinelayout, -1)];
      pipeline_cache=get(system, :pipeline_cache, C_NULL)
    ))[1][1]
  )
end

##### Render Pipelines

function renderpass(system, config)
  samples = hw.multisamplemax(system.spec, config.samples)

  # TODO: If samples === 1, we shouldn't include a separate colour attachement
  # for multisampling.
  hashmap(
    :renderpass,
    vk.unwrap(vk.create_render_pass(
      system.device,
      [
        vk.AttachmentDescription(
          system.spec.swapchain.format.format,
          samples,
          vk.ATTACHMENT_LOAD_OP_CLEAR,
          vk.ATTACHMENT_STORE_OP_DONT_CARE,
          vk.ATTACHMENT_LOAD_OP_DONT_CARE,
          vk.ATTACHMENT_STORE_OP_DONT_CARE,
          vk.IMAGE_LAYOUT_UNDEFINED,
          vk.IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
        ),
        vk.AttachmentDescription(
          hw.optdepthformat(system),
          samples,
          vk.ATTACHMENT_LOAD_OP_CLEAR,
          vk.ATTACHMENT_STORE_OP_DONT_CARE,
          vk.ATTACHMENT_LOAD_OP_DONT_CARE,
          vk.ATTACHMENT_STORE_OP_DONT_CARE,
          vk.IMAGE_LAYOUT_UNDEFINED,
          vk.IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
        ),
        vk.AttachmentDescription(
          system.spec.swapchain.format.format,
          vk.SAMPLE_COUNT_1_BIT,
          vk.ATTACHMENT_LOAD_OP_DONT_CARE,
          vk.ATTACHMENT_STORE_OP_STORE,
          vk.ATTACHMENT_LOAD_OP_DONT_CARE,
          vk.ATTACHMENT_STORE_OP_DONT_CARE,
          vk.IMAGE_LAYOUT_UNDEFINED,
          vk.IMAGE_LAYOUT_PRESENT_SRC_KHR
        )
      ],
      [vk.SubpassDescription(
        vk.PIPELINE_BIND_POINT_GRAPHICS,
        [],
        [vk.AttachmentReference(0, vk.IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL)],
        [];
        depth_stencil_attachment=vk.AttachmentReference(
          1,
          vk.IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
        ),
        resolve_attachments=[vk.AttachmentReference(
          2,
          vk.IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
        )]

      )],
      [vk.SubpassDependency(
        vk.SUBPASS_EXTERNAL,
        0;
        src_stage_mask=vk.PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT |
                       vk.PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
        src_access_mask=0,
        dst_stage_mask=vk.PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT |
                       vk.PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
        dst_access_mask=vk.ACCESS_COLOR_ATTACHMENT_WRITE_BIT |
                        vk.ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT
      )]
    ))
  )
end

function pipelinelayout(system, config)
  dl = ds.getin(config, [:render, :descriptorsets, :layout], nothing)
  dl = dl === nothing ? [] : [dl]
  dev = get(system, :device)
  pcs = map(pushconstantrange, ds.getin(config, [:render, :pushconstants], []))

  vk.unwrap(vk.create_pipeline_layout(dev, dl, pcs))
end

const topomap = ds.hashmap(
  :points, vk.PRIMITIVE_TOPOLOGY_POINT_LIST,
  :lines, vk.PRIMITIVE_TOPOLOGY_LINE_LIST,
  :linearspline, vk.PRIMITIVE_TOPOLOGY_LINE_STRIP,
  :triangles, vk.PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
)

function creategraphicspipeline(system, ext, config)
  device = system.device

  dynamic_state = vk.PipelineDynamicStateCreateInfo([
    vk.DYNAMIC_STATE_SCISSOR,
    vk.DYNAMIC_STATE_VIEWPORT
  ])

  ias = config.render.inputassembly

  input_assembly_state = vk.PipelineInputAssemblyStateCreateInfo(
    get(topomap, ias.topology), get(ias, :restart, false)
  )

  viewports = [vk.Viewport(0, 0, ext.width, ext.height, 0, 1)]
  scissors = [vk.Rect2D(vk.Offset2D(0, 0), ext)]

  viewport_state = vk.PipelineViewportStateCreateInfo(; viewports, scissors)

  multisample_state = vk.PipelineMultisampleStateCreateInfo(
    hw.multisamplemax(system.spec, config.render.samples),
    false,
    1,
    false,
    false
  )

  color_write_mask = vk.COLOR_COMPONENT_R_BIT |
    vk.COLOR_COMPONENT_G_BIT |
    vk.COLOR_COMPONENT_B_BIT |
    vk.COLOR_COMPONENT_A_BIT

  color_blend_state = vk.PipelineColorBlendStateCreateInfo(
    false,
    vk.LOGIC_OP_COPY,
    [vk.PipelineColorBlendAttachmentState(
      false,
      vk.BLEND_FACTOR_ONE,
      vk.BLEND_FACTOR_ZERO,
      vk.BLEND_OP_ADD,
      vk.BLEND_FACTOR_ONE,
      vk.BLEND_FACTOR_ZERO,
      vk.BLEND_OP_ADD;
      color_write_mask
    )],
    NTuple{4, Float32}((0,0,0,0))
  )

  stencil_stub = vk.StencilOpState(
    vk.StencilOp(0),
    vk.StencilOp(0),
    vk.StencilOp(0),
    vk.COMPARE_OP_LESS,
    0,
    0,
    0
  )

  depth_stencil_state = vk.PipelineDepthStencilStateCreateInfo(
    true,
    true,
    vk.COMPARE_OP_LESS,
    false,
    false,
    stencil_stub,
    stencil_stub,
    0,
    1
  )

  vertex_input_state = config.render.vertex_input_state
  if vertex_input_state === nothing
    v = config.render.vertex
    T = v.type
    if ds.containsp(v, :fields)
      fields = v.fields
    else
      fields = fieldnames(T)
    end
    vertex_input_state = rd.vertex_input_state(T, fields)
  end

  layout = pipelinelayout(system, config)

  ps = vk.unwrap(vk.create_graphics_pipelines(
    device,
    [vk.GraphicsPipelineCreateInfo(
      shaders(device, config.render.shaders),
      vk.PipelineRasterizationStateCreateInfo(
        false,
        false,
        vk.POLYGON_MODE_FILL,
        vk.FRONT_FACE_COUNTER_CLOCKWISE,
        false,
        0.0, 0.0, 0.0,
        1.0;
        cull_mode=vk.CULL_MODE_BACK_BIT
      ),
      layout,
      0,
      -1;
      vertex_input_state,
      input_assembly_state,
      viewport_state,
      multisample_state,
      color_blend_state,
      dynamic_state,
      depth_stencil_state,
      render_pass=get(system, :renderpass)
    )];
    pipeline_cache=get(system, :pipeline_cache, C_NULL)
  ))

  hashmap(:pipeline, ps[1][1], :viewports, viewports, :scissors, scissors,
          :bindpoint, :graphics,
          :pipelinelayout, layout)
end

function createframebuffers(system, extent)
  dev = get(system, :device)
  images = get(system, :imageviews)
  pass = get(system, :renderpass)
  depthview = ds.getin(system, [:depth, :view])
  colourview = ds.getin(system, [:colour, :view])

  hashmap(
    :framebuffers,
    into(
      emptyvector,
      map(image -> vk.create_framebuffer(
        dev,
        pass,
        [colourview, depthview, image],
        extent.width,
        extent.height,
        1
      ))
      ∘
      map(vk.unwrap),
      images
    )
  )
end

end #module
