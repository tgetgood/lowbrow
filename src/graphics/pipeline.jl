module pipeline

import hardware as hw
import resources

import Vulkan as vk
import DataStructures as ds
import DataStructures: getin, emptymap, hashmap, emptyvector, into, mapindexed

function glslc(src, out)
  run(`glslc $(@__DIR__)/../shaders/$src -o $out`)
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

const shadertypes = hashmap(
  :vertex, vk.SHADER_STAGE_VERTEX_BIT,
  :fragment, vk.SHADER_STAGE_FRAGMENT_BIT,
  :compute, vk.SHADER_STAGE_COMPUTE_BIT
)

function shader(device, fname, stage, entry="main")
  vk.PipelineShaderStageCreateInfo(
    get(shadertypes, stage),
    compileshader(device, fname),
    entry
  )
end

function shaders(device, config)
  # REVIEW: This assumes only one shader of a given type per pipeline. Is that
  # correct?
  into(
    [],
    map(e -> shader(device, ds.val(e), ds.key(e))),
    get(config, :shaders))
end

function renderpass(system, config)
  hashmap(
    :renderpass,
    vk.unwrap(vk.create_render_pass(
      get(system, :device),
      [
        vk.AttachmentDescription(
          getin(config, [:swapchain, :format]),
          getin(system, [:colour, :samples]),
          vk.ATTACHMENT_LOAD_OP_CLEAR,
          vk.ATTACHMENT_STORE_OP_STORE,
          vk.ATTACHMENT_LOAD_OP_DONT_CARE,
          vk.ATTACHMENT_STORE_OP_DONT_CARE,
          vk.IMAGE_LAYOUT_UNDEFINED,
          vk.IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
        ),
        vk.AttachmentDescription(
          hw.optdepthformat(system),
          getin(system, [:depth, :samples]),
          vk.ATTACHMENT_LOAD_OP_CLEAR,
          vk.ATTACHMENT_STORE_OP_DONT_CARE,
          vk.ATTACHMENT_LOAD_OP_DONT_CARE,
          vk.ATTACHMENT_STORE_OP_DONT_CARE,
          vk.IMAGE_LAYOUT_UNDEFINED,
          vk.IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
        ),
        vk.AttachmentDescription(
          getin(config, [:swapchain, :format]),
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
  dl = get(config, :descriptorsetlayout, nothing)
  dl = dl === nothing ? [] : [dl]
  dev = get(system, :device)

  vk.unwrap(vk.create_pipeline_layout(dev, dl, []))
end

function creategraphicspipeline(system, config)
  device = get(system, :device)

  dynamic_state = vk.PipelineDynamicStateCreateInfo([
    vk.DYNAMIC_STATE_SCISSOR,
    vk.DYNAMIC_STATE_VIEWPORT
  ])

  input_assembly_state = vk.PipelineInputAssemblyStateCreateInfo(
    vk.PRIMITIVE_TOPOLOGY_POINT_LIST,
    # vk.PRIMITIVE_TOPOLOGY_LINE_LIST,
    # vk.PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    false
  )

  # FIXME: It's possible for :window_size and :extent to get out of sync, which
  # crashes the program.
  ext = get(system, :extent)

  viewports = [vk.Viewport(0, 0, ext.width, ext.height, 0, 1)]
  scissors = [vk.Rect2D(vk.Offset2D(0, 0), ext)]

  viewport_state = vk.PipelineViewportStateCreateInfo(
    ;
    viewports, scissors
  )

  multisample_state = vk.PipelineMultisampleStateCreateInfo(
    getin(system, [:colour, :samples]),
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

  vertex_input_state = get(config, :vertex_input_state)

  layout = pipelinelayout(system, config)

  ps = vk.unwrap(vk.create_graphics_pipelines(
    device,
    [vk.GraphicsPipelineCreateInfo(
      shaders(device, config),
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
    )]
  ))

  hashmap(:pipeline, ps[1][1], :viewports, viewports, :scissors, scissors,
          :pipelinelayout, layout)
end

function createframebuffers(system, config)
  dev = get(system, :device)
  images = get(system, :imageviews)
  pass = get(system, :renderpass)
  extent = get(system, :extent)
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

function computelayout(buffers)
end

function computepipeline(system, config)
  layout = computelayout(get(system, :particle_buffers))
  pipeline = vk.unwrap(vk.create_compute_pipelines(
    get(system, :device),
    [vk.ComputePipelineCreateInfo(
      ds.getin(system, [:shaders, :compute]),
      vk.PipelineLayoutCreateInfo(layout, [])
    )]
  ))
  hashmap(:compute, hashmap(:pipeline, pipeline, :layout, layout))
end

end #module
