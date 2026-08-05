{.passC: "-I/opt/homebrew/include -I/opt/homebrew/include/harfbuzz -DSDL_MAIN_HANDLED".}
{.passL: "-L/opt/homebrew/lib -lSDL3 -lharfbuzz".}

type
  SdlAppResult* {.importc: "SDL_AppResult", header: "SDL3/SDL_main.h".} = enum
    app_continue = 0
    app_success = 1
    app_failure = 2
  SdlEvent* {.importc: "SDL_Event", header: "SDL3/SDL.h".} = object
    kind* {.importc: "type".}: uint32
  SdlWindow* {.importc: "SDL_Window", header: "SDL3/SDL.h".} = object
  SdlGpuDevice* {.importc: "SDL_GPUDevice", header: "SDL3/SDL_gpu.h", incompleteStruct.} = object
  SdlGpuBuffer* {.importc: "SDL_GPUBuffer", header: "SDL3/SDL_gpu.h", incompleteStruct.} = object
  SdlGpuTransferBuffer* {.importc: "SDL_GPUTransferBuffer", header: "SDL3/SDL_gpu.h", incompleteStruct.} = object
  SdlGpuTexture* {.importc: "SDL_GPUTexture", header: "SDL3/SDL_gpu.h", incompleteStruct.} = object
  SdlGpuSampler* {.importc: "SDL_GPUSampler", header: "SDL3/SDL_gpu.h", incompleteStruct.} = object
  SdlGpuShader* {.importc: "SDL_GPUShader", header: "SDL3/SDL_gpu.h", incompleteStruct.} = object
  SdlGpuGraphicsPipeline* {.importc: "SDL_GPUGraphicsPipeline", header: "SDL3/SDL_gpu.h", incompleteStruct.} = object
  SdlGpuCommandBuffer* {.importc: "SDL_GPUCommandBuffer", header: "SDL3/SDL_gpu.h", incompleteStruct.} = object
  SdlGpuRenderPass* {.importc: "SDL_GPURenderPass", header: "SDL3/SDL_gpu.h", incompleteStruct.} = object
  SdlGpuCopyPass* {.importc: "SDL_GPUCopyPass", header: "SDL3/SDL_gpu.h", incompleteStruct.} = object
  SdlGpuFence* {.importc: "SDL_GPUFence", header: "SDL3/SDL_gpu.h", incompleteStruct.} = object

  SdlPropertiesId* = uint32
  SdlGpuPrimitiveType* = cint
  SdlGpuLoadOp* = cint
  SdlGpuStoreOp* = cint
  SdlGpuIndexElementSize* = cint
  SdlGpuTextureFormat* = cint
  SdlGpuTextureType* = cint
  SdlGpuSampleCount* = cint
  SdlGpuShaderStage* = cint
  SdlGpuVertexElementFormat* = cint
  SdlGpuVertexInputRate* = cint
  SdlGpuFillMode* = cint
  SdlGpuCullMode* = cint
  SdlGpuFrontFace* = cint
  SdlGpuCompareOp* = cint
  SdlGpuStencilOp* = cint
  SdlGpuBlendOp* = cint
  SdlGpuBlendFactor* = cint
  SdlGpuFilter* = cint
  SdlGpuSamplerMipmapMode* = cint
  SdlGpuSamplerAddressMode* = cint
  SdlGpuPresentMode* = cint
  SdlGpuSwapchainComposition* = cint
  SdlGpuShaderFormat* = uint32
  SdlGpuTextureUsageFlags* = uint32
  SdlGpuBufferUsageFlags* = uint32
  SdlGpuTransferBufferUsage* = cint
  SdlGpuColorComponentFlags* = uint8
  SdlPixelFormat* = uint32
  SdlFlipMode* = cint

const
  sdl_gpu_primitive_type_triangle_list* = SdlGpuPrimitiveType(0)
  sdl_gpu_primitive_type_triangle_strip* = SdlGpuPrimitiveType(1)
  sdl_gpu_primitive_type_line_list* = SdlGpuPrimitiveType(2)
  sdl_gpu_primitive_type_line_strip* = SdlGpuPrimitiveType(3)
  sdl_gpu_primitive_type_point_list* = SdlGpuPrimitiveType(4)

  sdl_gpu_load_op_load* = SdlGpuLoadOp(0)
  sdl_gpu_load_op_clear* = SdlGpuLoadOp(1)
  sdl_gpu_load_op_dont_care* = SdlGpuLoadOp(2)
  sdl_gpu_store_op_store* = SdlGpuStoreOp(0)
  sdl_gpu_store_op_dont_care* = SdlGpuStoreOp(1)
  sdl_gpu_store_op_resolve* = SdlGpuStoreOp(2)
  sdl_gpu_store_op_resolve_and_store* = SdlGpuStoreOp(3)
  sdl_gpu_index_element_size_16_bit* = SdlGpuIndexElementSize(0)
  sdl_gpu_index_element_size_32_bit* = SdlGpuIndexElementSize(1)

  sdl_gpu_texture_type_2d* = SdlGpuTextureType(0)
  sdl_gpu_texture_type_2d_array* = SdlGpuTextureType(1)
  sdl_gpu_texture_type_3d* = SdlGpuTextureType(2)
  sdl_gpu_texture_type_cube* = SdlGpuTextureType(3)
  sdl_gpu_texture_type_cube_array* = SdlGpuTextureType(4)
  sdl_gpu_sample_count_1* = SdlGpuSampleCount(0)
  sdl_gpu_sample_count_2* = SdlGpuSampleCount(1)
  sdl_gpu_sample_count_4* = SdlGpuSampleCount(2)
  sdl_gpu_sample_count_8* = SdlGpuSampleCount(3)
  sdl_gpu_texture_usage_depth_stencil_target* = SdlGpuTextureUsageFlags(1'u32 shl 2)
  sdl_gpu_buffer_usage_vertex* = SdlGpuBufferUsageFlags(1'u32 shl 0)
  sdl_gpu_transfer_buffer_usage_upload* = SdlGpuTransferBufferUsage(0)
  sdl_gpu_transfer_buffer_usage_download* = SdlGpuTransferBufferUsage(1)
  sdl_gpu_shader_stage_vertex* = SdlGpuShaderStage(0)
  sdl_gpu_shader_stage_fragment* = SdlGpuShaderStage(1)

  sdl_gpu_vertex_element_format_invalid* = SdlGpuVertexElementFormat(0)
  sdl_gpu_vertex_element_format_int* = SdlGpuVertexElementFormat(1)
  sdl_gpu_vertex_element_format_int2* = SdlGpuVertexElementFormat(2)
  sdl_gpu_vertex_element_format_int3* = SdlGpuVertexElementFormat(3)
  sdl_gpu_vertex_element_format_int4* = SdlGpuVertexElementFormat(4)
  sdl_gpu_vertex_element_format_uint* = SdlGpuVertexElementFormat(5)
  sdl_gpu_vertex_element_format_uint2* = SdlGpuVertexElementFormat(6)
  sdl_gpu_vertex_element_format_uint3* = SdlGpuVertexElementFormat(7)
  sdl_gpu_vertex_element_format_uint4* = SdlGpuVertexElementFormat(8)
  sdl_gpu_vertex_element_format_float* = SdlGpuVertexElementFormat(9)
  sdl_gpu_vertex_element_format_float2* = SdlGpuVertexElementFormat(10)
  sdl_gpu_vertex_element_format_float3* = SdlGpuVertexElementFormat(11)
  sdl_gpu_vertex_element_format_float4* = SdlGpuVertexElementFormat(12)
  sdl_gpu_vertex_element_format_byte2* = SdlGpuVertexElementFormat(13)
  sdl_gpu_vertex_element_format_byte4* = SdlGpuVertexElementFormat(14)
  sdl_gpu_vertex_element_format_ubyte2* = SdlGpuVertexElementFormat(15)
  sdl_gpu_vertex_element_format_ubyte4* = SdlGpuVertexElementFormat(16)
  sdl_gpu_vertex_element_format_byte2_norm* = SdlGpuVertexElementFormat(17)
  sdl_gpu_vertex_element_format_byte4_norm* = SdlGpuVertexElementFormat(18)
  sdl_gpu_vertex_element_format_ubyte2_norm* = SdlGpuVertexElementFormat(19)
  sdl_gpu_vertex_element_format_ubyte4_norm* = SdlGpuVertexElementFormat(20)
  sdl_gpu_vertex_element_format_short2* = SdlGpuVertexElementFormat(21)
  sdl_gpu_vertex_element_format_short4* = SdlGpuVertexElementFormat(22)
  sdl_gpu_vertex_element_format_ushort2* = SdlGpuVertexElementFormat(23)
  sdl_gpu_vertex_element_format_ushort4* = SdlGpuVertexElementFormat(24)
  sdl_gpu_vertex_element_format_short2_norm* = SdlGpuVertexElementFormat(25)
  sdl_gpu_vertex_element_format_short4_norm* = SdlGpuVertexElementFormat(26)
  sdl_gpu_vertex_element_format_ushort2_norm* = SdlGpuVertexElementFormat(27)
  sdl_gpu_vertex_element_format_ushort4_norm* = SdlGpuVertexElementFormat(28)
  sdl_gpu_vertex_element_format_half2* = SdlGpuVertexElementFormat(29)
  sdl_gpu_vertex_element_format_half4* = SdlGpuVertexElementFormat(30)
  sdl_gpu_vertex_input_rate_vertex* = SdlGpuVertexInputRate(0)
  sdl_gpu_vertex_input_rate_instance* = SdlGpuVertexInputRate(1)

  sdl_gpu_fill_mode_fill* = SdlGpuFillMode(0)
  sdl_gpu_fill_mode_line* = SdlGpuFillMode(1)
  sdl_gpu_cull_mode_none* = SdlGpuCullMode(0)
  sdl_gpu_cull_mode_front* = SdlGpuCullMode(1)
  sdl_gpu_cull_mode_back* = SdlGpuCullMode(2)
  sdl_gpu_front_face_counter_clockwise* = SdlGpuFrontFace(0)
  sdl_gpu_front_face_clockwise* = SdlGpuFrontFace(1)
  sdl_gpu_compare_op_invalid* = SdlGpuCompareOp(0)
  sdl_gpu_compare_op_never* = SdlGpuCompareOp(1)
  sdl_gpu_compare_op_less* = SdlGpuCompareOp(2)
  sdl_gpu_compare_op_equal* = SdlGpuCompareOp(3)
  sdl_gpu_compare_op_less_or_equal* = SdlGpuCompareOp(4)
  sdl_gpu_compare_op_greater* = SdlGpuCompareOp(5)
  sdl_gpu_compare_op_not_equal* = SdlGpuCompareOp(6)
  sdl_gpu_compare_op_greater_or_equal* = SdlGpuCompareOp(7)
  sdl_gpu_compare_op_always* = SdlGpuCompareOp(8)
  sdl_gpu_stencil_op_invalid* = SdlGpuStencilOp(0)
  sdl_gpu_stencil_op_keep* = SdlGpuStencilOp(1)
  sdl_gpu_stencil_op_zero* = SdlGpuStencilOp(2)
  sdl_gpu_stencil_op_replace* = SdlGpuStencilOp(3)
  sdl_gpu_stencil_op_increment_and_clamp* = SdlGpuStencilOp(4)
  sdl_gpu_stencil_op_decrement_and_clamp* = SdlGpuStencilOp(5)
  sdl_gpu_stencil_op_invert* = SdlGpuStencilOp(6)
  sdl_gpu_stencil_op_increment_and_wrap* = SdlGpuStencilOp(7)
  sdl_gpu_stencil_op_decrement_and_wrap* = SdlGpuStencilOp(8)
  sdl_gpu_blend_op_invalid* = SdlGpuBlendOp(0)
  sdl_gpu_blend_op_add* = SdlGpuBlendOp(1)
  sdl_gpu_blend_op_subtract* = SdlGpuBlendOp(2)
  sdl_gpu_blend_op_reverse_subtract* = SdlGpuBlendOp(3)
  sdl_gpu_blend_op_min* = SdlGpuBlendOp(4)
  sdl_gpu_blend_op_max* = SdlGpuBlendOp(5)
  sdl_gpu_blend_factor_invalid* = SdlGpuBlendFactor(0)
  sdl_gpu_blend_factor_zero* = SdlGpuBlendFactor(1)
  sdl_gpu_blend_factor_one* = SdlGpuBlendFactor(2)
  sdl_gpu_blend_factor_src_color* = SdlGpuBlendFactor(3)
  sdl_gpu_blend_factor_one_minus_src_color* = SdlGpuBlendFactor(4)
  sdl_gpu_blend_factor_dst_color* = SdlGpuBlendFactor(5)
  sdl_gpu_blend_factor_one_minus_dst_color* = SdlGpuBlendFactor(6)
  sdl_gpu_blend_factor_src_alpha* = SdlGpuBlendFactor(7)
  sdl_gpu_blend_factor_one_minus_src_alpha* = SdlGpuBlendFactor(8)
  sdl_gpu_blend_factor_dst_alpha* = SdlGpuBlendFactor(9)
  sdl_gpu_blend_factor_one_minus_dst_alpha* = SdlGpuBlendFactor(10)
  sdl_gpu_blend_factor_constant_color* = SdlGpuBlendFactor(11)
  sdl_gpu_blend_factor_one_minus_constant_color* = SdlGpuBlendFactor(12)
  sdl_gpu_blend_factor_src_alpha_saturate* = SdlGpuBlendFactor(13)
  sdl_gpu_filter_nearest* = SdlGpuFilter(0)
  sdl_gpu_filter_linear* = SdlGpuFilter(1)
  sdl_gpu_sampler_mipmap_mode_nearest* = SdlGpuSamplerMipmapMode(0)
  sdl_gpu_sampler_mipmap_mode_linear* = SdlGpuSamplerMipmapMode(1)
  sdl_gpu_sampler_address_mode_repeat* = SdlGpuSamplerAddressMode(0)
  sdl_gpu_sampler_address_mode_mirrored_repeat* = SdlGpuSamplerAddressMode(1)
  sdl_gpu_sampler_address_mode_clamp_to_edge* = SdlGpuSamplerAddressMode(2)
  sdl_gpu_present_mode_vsync* = SdlGpuPresentMode(0)
  sdl_gpu_present_mode_immediate* = SdlGpuPresentMode(1)
  sdl_gpu_present_mode_mailbox* = SdlGpuPresentMode(2)
  sdl_gpu_swapchain_composition_sdr* = SdlGpuSwapchainComposition(0)
  sdl_gpu_swapchain_composition_sdr_linear* = SdlGpuSwapchainComposition(1)
  sdl_gpu_swapchain_composition_hdr_extended_linear* = SdlGpuSwapchainComposition(2)
  sdl_gpu_swapchain_composition_hdr10_st2084* = SdlGpuSwapchainComposition(3)

  sdl_gpu_shader_format_invalid* = SdlGpuShaderFormat(0)
  sdl_gpu_shader_format_private* = SdlGpuShaderFormat(1'u32 shl 0)
  sdl_gpu_shader_format_spirv* = SdlGpuShaderFormat(1'u32 shl 1)
  sdl_gpu_shader_format_dxbc* = SdlGpuShaderFormat(1'u32 shl 2)
  sdl_gpu_shader_format_dxil* = SdlGpuShaderFormat(1'u32 shl 3)
  sdl_gpu_shader_format_msl* = SdlGpuShaderFormat(1'u32 shl 4)

  sdl_gpu_texture_format_invalid* = SdlGpuTextureFormat(0)
  sdl_gpu_texture_format_a8_unorm* = SdlGpuTextureFormat(1)
  sdl_gpu_texture_format_r8_unorm* = SdlGpuTextureFormat(2)
  sdl_gpu_texture_format_r8g8_unorm* = SdlGpuTextureFormat(3)
  sdl_gpu_texture_format_r8g8b8a8_unorm* = SdlGpuTextureFormat(4)
  sdl_gpu_texture_format_r16_unorm* = SdlGpuTextureFormat(5)
  sdl_gpu_texture_format_r16g16_unorm* = SdlGpuTextureFormat(6)
  sdl_gpu_texture_format_r16g16b16a16_unorm* = SdlGpuTextureFormat(7)
  sdl_gpu_texture_format_r10g10b10a2_unorm* = SdlGpuTextureFormat(8)
  sdl_gpu_texture_format_b5g6r5_unorm* = SdlGpuTextureFormat(9)
  sdl_gpu_texture_format_b5g5r5a1_unorm* = SdlGpuTextureFormat(10)
  sdl_gpu_texture_format_b4g4r4a4_unorm* = SdlGpuTextureFormat(11)
  sdl_gpu_texture_format_b8g8r8a8_unorm* = SdlGpuTextureFormat(12)
  sdl_gpu_texture_format_bc1_rgba_unorm* = SdlGpuTextureFormat(13)
  sdl_gpu_texture_format_bc2_rgba_unorm* = SdlGpuTextureFormat(14)
  sdl_gpu_texture_format_bc3_rgba_unorm* = SdlGpuTextureFormat(15)
  sdl_gpu_texture_format_bc4_r_unorm* = SdlGpuTextureFormat(16)
  sdl_gpu_texture_format_bc5_rg_unorm* = SdlGpuTextureFormat(17)
  sdl_gpu_texture_format_bc7_rgba_unorm* = SdlGpuTextureFormat(18)
  sdl_gpu_texture_format_bc6h_rgb_float* = SdlGpuTextureFormat(19)
  sdl_gpu_texture_format_bc6h_rgb_ufloat* = SdlGpuTextureFormat(20)
  sdl_gpu_texture_format_r8_snorm* = SdlGpuTextureFormat(21)
  sdl_gpu_texture_format_r8g8_snorm* = SdlGpuTextureFormat(22)
  sdl_gpu_texture_format_r8g8b8a8_snorm* = SdlGpuTextureFormat(23)
  sdl_gpu_texture_format_r16_snorm* = SdlGpuTextureFormat(24)
  sdl_gpu_texture_format_r16g16_snorm* = SdlGpuTextureFormat(25)
  sdl_gpu_texture_format_r16g16b16a16_snorm* = SdlGpuTextureFormat(26)
  sdl_gpu_texture_format_r16_float* = SdlGpuTextureFormat(27)
  sdl_gpu_texture_format_r16g16_float* = SdlGpuTextureFormat(28)
  sdl_gpu_texture_format_r16g16b16a16_float* = SdlGpuTextureFormat(29)
  sdl_gpu_texture_format_r32_float* = SdlGpuTextureFormat(30)
  sdl_gpu_texture_format_r32g32_float* = SdlGpuTextureFormat(31)
  sdl_gpu_texture_format_r32g32b32a32_float* = SdlGpuTextureFormat(32)
  sdl_gpu_texture_format_r11g11b10_ufloat* = SdlGpuTextureFormat(33)
  sdl_gpu_texture_format_r8_uint* = SdlGpuTextureFormat(34)
  sdl_gpu_texture_format_r8g8_uint* = SdlGpuTextureFormat(35)
  sdl_gpu_texture_format_r8g8b8a8_uint* = SdlGpuTextureFormat(36)
  sdl_gpu_texture_format_r16_uint* = SdlGpuTextureFormat(37)
  sdl_gpu_texture_format_r16g16_uint* = SdlGpuTextureFormat(38)
  sdl_gpu_texture_format_r16g16b16a16_uint* = SdlGpuTextureFormat(39)
  sdl_gpu_texture_format_r32_uint* = SdlGpuTextureFormat(40)
  sdl_gpu_texture_format_r32g32_uint* = SdlGpuTextureFormat(41)
  sdl_gpu_texture_format_r32g32b32a32_uint* = SdlGpuTextureFormat(42)
  sdl_gpu_texture_format_r8_int* = SdlGpuTextureFormat(43)
  sdl_gpu_texture_format_r8g8_int* = SdlGpuTextureFormat(44)
  sdl_gpu_texture_format_r8g8b8a8_int* = SdlGpuTextureFormat(45)
  sdl_gpu_texture_format_r16_int* = SdlGpuTextureFormat(46)
  sdl_gpu_texture_format_r16g16_int* = SdlGpuTextureFormat(47)
  sdl_gpu_texture_format_r16g16b16a16_int* = SdlGpuTextureFormat(48)
  sdl_gpu_texture_format_r32_int* = SdlGpuTextureFormat(49)
  sdl_gpu_texture_format_r32g32_int* = SdlGpuTextureFormat(50)
  sdl_gpu_texture_format_r32g32b32a32_int* = SdlGpuTextureFormat(51)
  sdl_gpu_texture_format_r8g8b8a8_unorm_srgb* = SdlGpuTextureFormat(52)
  sdl_gpu_texture_format_b8g8r8a8_unorm_srgb* = SdlGpuTextureFormat(53)
  sdl_gpu_texture_format_bc1_rgba_unorm_srgb* = SdlGpuTextureFormat(54)
  sdl_gpu_texture_format_bc2_rgba_unorm_srgb* = SdlGpuTextureFormat(55)
  sdl_gpu_texture_format_bc3_rgba_unorm_srgb* = SdlGpuTextureFormat(56)
  sdl_gpu_texture_format_bc7_rgba_unorm_srgb* = SdlGpuTextureFormat(57)
  sdl_gpu_texture_format_d16_unorm* = SdlGpuTextureFormat(58)
  sdl_gpu_texture_format_d24_unorm* = SdlGpuTextureFormat(59)
  sdl_gpu_texture_format_d32_float* = SdlGpuTextureFormat(60)
  sdl_gpu_texture_format_d24_unorm_s8_uint* = SdlGpuTextureFormat(61)
  sdl_gpu_texture_format_d32_float_s8_uint* = SdlGpuTextureFormat(62)
  sdl_gpu_texture_format_astc_4x4_unorm* = SdlGpuTextureFormat(63)
  sdl_gpu_texture_format_astc_5x4_unorm* = SdlGpuTextureFormat(64)
  sdl_gpu_texture_format_astc_5x5_unorm* = SdlGpuTextureFormat(65)
  sdl_gpu_texture_format_astc_6x5_unorm* = SdlGpuTextureFormat(66)
  sdl_gpu_texture_format_astc_6x6_unorm* = SdlGpuTextureFormat(67)
  sdl_gpu_texture_format_astc_8x5_unorm* = SdlGpuTextureFormat(68)
  sdl_gpu_texture_format_astc_8x6_unorm* = SdlGpuTextureFormat(69)
  sdl_gpu_texture_format_astc_8x8_unorm* = SdlGpuTextureFormat(70)
  sdl_gpu_texture_format_astc_10x5_unorm* = SdlGpuTextureFormat(71)
  sdl_gpu_texture_format_astc_10x6_unorm* = SdlGpuTextureFormat(72)
  sdl_gpu_texture_format_astc_10x8_unorm* = SdlGpuTextureFormat(73)
  sdl_gpu_texture_format_astc_10x10_unorm* = SdlGpuTextureFormat(74)
  sdl_gpu_texture_format_astc_12x10_unorm* = SdlGpuTextureFormat(75)
  sdl_gpu_texture_format_astc_12x12_unorm* = SdlGpuTextureFormat(76)
  sdl_gpu_texture_format_astc_4x4_unorm_srgb* = SdlGpuTextureFormat(77)
  sdl_gpu_texture_format_astc_5x4_unorm_srgb* = SdlGpuTextureFormat(78)
  sdl_gpu_texture_format_astc_5x5_unorm_srgb* = SdlGpuTextureFormat(79)
  sdl_gpu_texture_format_astc_6x5_unorm_srgb* = SdlGpuTextureFormat(80)
  sdl_gpu_texture_format_astc_6x6_unorm_srgb* = SdlGpuTextureFormat(81)
  sdl_gpu_texture_format_astc_8x5_unorm_srgb* = SdlGpuTextureFormat(82)
  sdl_gpu_texture_format_astc_8x6_unorm_srgb* = SdlGpuTextureFormat(83)
  sdl_gpu_texture_format_astc_8x8_unorm_srgb* = SdlGpuTextureFormat(84)
  sdl_gpu_texture_format_astc_10x5_unorm_srgb* = SdlGpuTextureFormat(85)
  sdl_gpu_texture_format_astc_10x6_unorm_srgb* = SdlGpuTextureFormat(86)
  sdl_gpu_texture_format_astc_10x8_unorm_srgb* = SdlGpuTextureFormat(87)
  sdl_gpu_texture_format_astc_10x10_unorm_srgb* = SdlGpuTextureFormat(88)
  sdl_gpu_texture_format_astc_12x10_unorm_srgb* = SdlGpuTextureFormat(89)
  sdl_gpu_texture_format_astc_12x12_unorm_srgb* = SdlGpuTextureFormat(90)
  sdl_gpu_texture_format_astc_4x4_float* = SdlGpuTextureFormat(91)
  sdl_gpu_texture_format_astc_5x4_float* = SdlGpuTextureFormat(92)
  sdl_gpu_texture_format_astc_5x5_float* = SdlGpuTextureFormat(93)
  sdl_gpu_texture_format_astc_6x5_float* = SdlGpuTextureFormat(94)
  sdl_gpu_texture_format_astc_6x6_float* = SdlGpuTextureFormat(95)
  sdl_gpu_texture_format_astc_8x5_float* = SdlGpuTextureFormat(96)
  sdl_gpu_texture_format_astc_8x6_float* = SdlGpuTextureFormat(97)
  sdl_gpu_texture_format_astc_8x8_float* = SdlGpuTextureFormat(98)
  sdl_gpu_texture_format_astc_10x5_float* = SdlGpuTextureFormat(99)
  sdl_gpu_texture_format_astc_10x6_float* = SdlGpuTextureFormat(100)
  sdl_gpu_texture_format_astc_10x8_float* = SdlGpuTextureFormat(101)
  sdl_gpu_texture_format_astc_10x10_float* = SdlGpuTextureFormat(102)
  sdl_gpu_texture_format_astc_12x10_float* = SdlGpuTextureFormat(103)
  sdl_gpu_texture_format_astc_12x12_float* = SdlGpuTextureFormat(104)

  sdl_flip_none* = SdlFlipMode(0)
  sdl_flip_horizontal* = SdlFlipMode(1)
  sdl_flip_vertical* = SdlFlipMode(2)
  sdl_flip_horizontal_and_vertical* = SdlFlipMode(3)

  sdl_pixel_format_unknown* = SdlPixelFormat(0)
  sdl_pixel_format_rgb565* = SdlPixelFormat(0x15151002'u32)
  sdl_pixel_format_rgb24* = SdlPixelFormat(0x17101803'u32)
  sdl_pixel_format_bgr24* = SdlPixelFormat(0x17401803'u32)
  sdl_pixel_format_xrgb8888* = SdlPixelFormat(0x16161804'u32)
  sdl_pixel_format_rgbx8888* = SdlPixelFormat(0x16261804'u32)
  sdl_pixel_format_xbgr8888* = SdlPixelFormat(0x16561804'u32)
  sdl_pixel_format_bgrx8888* = SdlPixelFormat(0x16661804'u32)
  sdl_pixel_format_argb8888* = SdlPixelFormat(0x16362004'u32)
  sdl_pixel_format_rgba8888* = SdlPixelFormat(0x16462004'u32)
  sdl_pixel_format_abgr8888* = SdlPixelFormat(0x16762004'u32)
  sdl_pixel_format_bgra8888* = SdlPixelFormat(0x16862004'u32)
  sdl_pixel_format_xrgb2101010* = SdlPixelFormat(0x16172004'u32)
  sdl_pixel_format_xbgr2101010* = SdlPixelFormat(0x16572004'u32)
  sdl_pixel_format_argb2101010* = SdlPixelFormat(0x16372004'u32)
  sdl_pixel_format_abgr2101010* = SdlPixelFormat(0x16772004'u32)
  sdl_pixel_format_rgba32* = sdl_pixel_format_rgba8888
  sdl_pixel_format_argb32* = sdl_pixel_format_argb8888
  sdl_pixel_format_bgra32* = sdl_pixel_format_bgra8888
  sdl_pixel_format_abgr32* = sdl_pixel_format_abgr8888
  sdl_pixel_format_rgbx32* = sdl_pixel_format_rgbx8888
  sdl_pixel_format_xrgb32* = sdl_pixel_format_xrgb8888
  sdl_pixel_format_bgrx32* = sdl_pixel_format_bgrx8888
  sdl_pixel_format_xbgr32* = sdl_pixel_format_xbgr8888

type
  SdlFColor* {.importc: "SDL_FColor", header: "SDL3/SDL_pixels.h".} = object
    r*: cfloat
    g*: cfloat
    b*: cfloat
    a*: cfloat
  SdlRect* {.importc: "SDL_Rect", header: "SDL3/SDL_rect.h".} = object
    x*: cint
    y*: cint
    w*: cint
    h*: cint
  SdlGpuViewport* {.importc: "SDL_GPUViewport", header: "SDL3/SDL_gpu.h".} = object
    x*: cfloat
    y*: cfloat
    w*: cfloat
    h*: cfloat
    min_depth*: cfloat
    max_depth*: cfloat
  SdlGpuTextureTransferInfo* {.importc: "SDL_GPUTextureTransferInfo", header: "SDL3/SDL_gpu.h".} = object
    transfer_buffer*: ptr SdlGpuTransferBuffer
    offset*: uint32
    pixels_per_row*: uint32
    rows_per_layer*: uint32
  SdlGpuTransferBufferLocation* {.importc: "SDL_GPUTransferBufferLocation", header: "SDL3/SDL_gpu.h".} = object
    transfer_buffer*: ptr SdlGpuTransferBuffer
    offset*: uint32
  SdlGpuTextureLocation* {.importc: "SDL_GPUTextureLocation", header: "SDL3/SDL_gpu.h".} = object
    texture*: ptr SdlGpuTexture
    mip_level*: uint32
    layer*: uint32
    x*: uint32
    y*: uint32
    z*: uint32
  SdlGpuTextureRegion* {.importc: "SDL_GPUTextureRegion", header: "SDL3/SDL_gpu.h".} = object
    texture*: ptr SdlGpuTexture
    mip_level*: uint32
    layer*: uint32
    x*: uint32
    y*: uint32
    z*: uint32
    w*: uint32
    h*: uint32
    d*: uint32
  SdlGpuBlitRegion* {.importc: "SDL_GPUBlitRegion", header: "SDL3/SDL_gpu.h".} = object
    texture*: ptr SdlGpuTexture
    mip_level*: uint32
    layer_or_depth_plane*: uint32
    x*: uint32
    y*: uint32
    w*: uint32
    h*: uint32
  SdlGpuBufferLocation* {.importc: "SDL_GPUBufferLocation", header: "SDL3/SDL_gpu.h".} = object
    buffer*: ptr SdlGpuBuffer
    offset*: uint32
  SdlGpuBufferRegion* {.importc: "SDL_GPUBufferRegion", header: "SDL3/SDL_gpu.h".} = object
    buffer*: ptr SdlGpuBuffer
    offset*: uint32
    size*: uint32
  SdlGpuSamplerCreateInfo* {.importc: "SDL_GPUSamplerCreateInfo", header: "SDL3/SDL_gpu.h".} = object
    min_filter*: SdlGpuFilter
    mag_filter*: SdlGpuFilter
    mipmap_mode*: SdlGpuSamplerMipmapMode
    address_mode_u*: SdlGpuSamplerAddressMode
    address_mode_v*: SdlGpuSamplerAddressMode
    address_mode_w*: SdlGpuSamplerAddressMode
    mip_lod_bias*: cfloat
    max_anisotropy*: cfloat
    compare_op*: SdlGpuCompareOp
    min_lod*: cfloat
    max_lod*: cfloat
    enable_anisotropy*: bool
    enable_compare*: bool
    padding1*: uint8
    padding2*: uint8
    props*: SdlPropertiesId
  SdlGpuVertexBufferDescription* {.importc: "SDL_GPUVertexBufferDescription", header: "SDL3/SDL_gpu.h".} = object
    slot*: uint32
    pitch*: uint32
    input_rate*: SdlGpuVertexInputRate
    instance_step_rate*: uint32
  SdlGpuVertexAttribute* {.importc: "SDL_GPUVertexAttribute", header: "SDL3/SDL_gpu.h".} = object
    location*: uint32
    buffer_slot*: uint32
    format*: SdlGpuVertexElementFormat
    offset*: uint32
  SdlGpuVertexInputState* {.importc: "SDL_GPUVertexInputState", header: "SDL3/SDL_gpu.h".} = object
    vertex_buffer_descriptions*: ptr SdlGpuVertexBufferDescription
    num_vertex_buffers*: uint32
    vertex_attributes*: ptr SdlGpuVertexAttribute
    num_vertex_attributes*: uint32
  SdlGpuStencilOpState* {.importc: "SDL_GPUStencilOpState", header: "SDL3/SDL_gpu.h".} = object
    fail_op*: SdlGpuStencilOp
    pass_op*: SdlGpuStencilOp
    depth_fail_op*: SdlGpuStencilOp
    compare_op*: SdlGpuCompareOp
  SdlGpuColorTargetBlendState* {.importc: "SDL_GPUColorTargetBlendState", header: "SDL3/SDL_gpu.h".} = object
    src_color_blendfactor*: SdlGpuBlendFactor
    dst_color_blendfactor*: SdlGpuBlendFactor
    color_blend_op*: SdlGpuBlendOp
    src_alpha_blendfactor*: SdlGpuBlendFactor
    dst_alpha_blendfactor*: SdlGpuBlendFactor
    alpha_blend_op*: SdlGpuBlendOp
    color_write_mask*: SdlGpuColorComponentFlags
    enable_blend*: bool
    enable_color_write_mask*: bool
    padding1*: uint8
    padding2*: uint8
  SdlGpuShaderCreateInfo* {.importc: "SDL_GPUShaderCreateInfo", header: "SDL3/SDL_gpu.h".} = object
    code_size*: csize_t
    code*: ptr uint8
    entrypoint*: cstring
    format*: SdlGpuShaderFormat
    stage*: SdlGpuShaderStage
    num_samplers*: uint32
    num_storage_textures*: uint32
    num_storage_buffers*: uint32
    num_uniform_buffers*: uint32
    props*: SdlPropertiesId
  SdlGpuTextureCreateInfo* {.importc: "SDL_GPUTextureCreateInfo", header: "SDL3/SDL_gpu.h".} = object
    `type`* {.importc: "type".}: SdlGpuTextureType
    format*: SdlGpuTextureFormat
    usage*: SdlGpuTextureUsageFlags
    width*: uint32
    height*: uint32
    layer_count_or_depth*: uint32
    num_levels*: uint32
    sample_count*: SdlGpuSampleCount
    props*: SdlPropertiesId
  SdlGpuBufferCreateInfo* {.importc: "SDL_GPUBufferCreateInfo", header: "SDL3/SDL_gpu.h".} = object
    usage*: SdlGpuBufferUsageFlags
    size*: uint32
    props*: SdlPropertiesId
  SdlGpuTransferBufferCreateInfo* {.importc: "SDL_GPUTransferBufferCreateInfo", header: "SDL3/SDL_gpu.h".} = object
    usage*: SdlGpuTransferBufferUsage
    size*: uint32
    props*: SdlPropertiesId
  SdlGpuRasterizerState* {.importc: "SDL_GPURasterizerState", header: "SDL3/SDL_gpu.h".} = object
    fill_mode*: SdlGpuFillMode
    cull_mode*: SdlGpuCullMode
    front_face*: SdlGpuFrontFace
    depth_bias_constant_factor*: cfloat
    depth_bias_clamp*: cfloat
    depth_bias_slope_factor*: cfloat
    enable_depth_bias*: bool
    enable_depth_clip*: bool
    padding1*: uint8
    padding2*: uint8
  SdlGpuMultisampleState* {.importc: "SDL_GPUMultisampleState", header: "SDL3/SDL_gpu.h".} = object
    sample_count*: SdlGpuSampleCount
    sample_mask*: uint32
    enable_mask*: bool
    enable_alpha_to_coverage*: bool
    padding2*: uint8
    padding3*: uint8
  SdlGpuDepthStencilState* {.importc: "SDL_GPUDepthStencilState", header: "SDL3/SDL_gpu.h".} = object
    compare_op*: SdlGpuCompareOp
    back_stencil_state*: SdlGpuStencilOpState
    front_stencil_state*: SdlGpuStencilOpState
    compare_mask*: uint8
    write_mask*: uint8
    enable_depth_test*: bool
    enable_depth_write*: bool
    enable_stencil_test*: bool
    padding1*: uint8
    padding2*: uint8
    padding3*: uint8
  SdlGpuColorTargetDescription* {.importc: "SDL_GPUColorTargetDescription", header: "SDL3/SDL_gpu.h".} = object
    format*: SdlGpuTextureFormat
    blend_state*: SdlGpuColorTargetBlendState
  SdlGpuGraphicsPipelineTargetInfo* {.importc: "SDL_GPUGraphicsPipelineTargetInfo", header: "SDL3/SDL_gpu.h".} = object
    color_target_descriptions*: ptr SdlGpuColorTargetDescription
    num_color_targets*: uint32
    depth_stencil_format*: SdlGpuTextureFormat
    has_depth_stencil_target*: bool
    padding1*: uint8
    padding2*: uint8
    padding3*: uint8
  SdlGpuGraphicsPipelineCreateInfo* {.importc: "SDL_GPUGraphicsPipelineCreateInfo", header: "SDL3/SDL_gpu.h".} = object
    vertex_shader*: ptr SdlGpuShader
    fragment_shader*: ptr SdlGpuShader
    vertex_input_state*: SdlGpuVertexInputState
    primitive_type*: SdlGpuPrimitiveType
    rasterizer_state*: SdlGpuRasterizerState
    multisample_state*: SdlGpuMultisampleState
    depth_stencil_state*: SdlGpuDepthStencilState
    target_info*: SdlGpuGraphicsPipelineTargetInfo
    props*: SdlPropertiesId
  SdlGpuColorTargetInfo* {.importc: "SDL_GPUColorTargetInfo", header: "SDL3/SDL_gpu.h".} = object
    texture*: ptr SdlGpuTexture
    mip_level*: uint32
    layer_or_depth_plane*: uint32
    clear_color*: SdlFColor
    load_op*: SdlGpuLoadOp
    store_op*: SdlGpuStoreOp
    resolve_texture*: ptr SdlGpuTexture
    resolve_mip_level*: uint32
    resolve_layer*: uint32
    cycle*: bool
    cycle_resolve_texture*: bool
    padding1*: uint8
    padding2*: uint8
  SdlGpuDepthStencilTargetInfo* {.importc: "SDL_GPUDepthStencilTargetInfo", header: "SDL3/SDL_gpu.h".} = object
    texture*: ptr SdlGpuTexture
    clear_depth*: cfloat
    load_op*: SdlGpuLoadOp
    store_op*: SdlGpuStoreOp
    stencil_load_op*: SdlGpuLoadOp
    stencil_store_op*: SdlGpuStoreOp
    cycle*: bool
    clear_stencil*: uint8
    mip_level*: uint8
    layer*: uint8
  SdlGpuBufferBinding* {.importc: "SDL_GPUBufferBinding", header: "SDL3/SDL_gpu.h".} = object
    buffer*: ptr SdlGpuBuffer
    offset*: uint32
  SdlGpuTextureSamplerBinding* {.importc: "SDL_GPUTextureSamplerBinding", header: "SDL3/SDL_gpu.h".} = object
    texture*: ptr SdlGpuTexture
    sampler*: ptr SdlGpuSampler
  SdlGpuBlitInfo* {.importc: "SDL_GPUBlitInfo", header: "SDL3/SDL_gpu.h".} = object
    source*: SdlGpuBlitRegion
    destination*: SdlGpuBlitRegion
    load_op*: SdlGpuLoadOp
    clear_color*: SdlFColor
    flip_mode*: SdlFlipMode
    filter*: SdlGpuFilter
    cycle*: bool
    padding1*: uint8
    padding2*: uint8
    padding3*: uint8

  SdlAppInitFunc* = proc(appstate: ptr pointer; argc: cint; argv: ptr ptr char): SdlAppResult {.cdecl.}
  SdlAppIterateFunc* = proc(appstate: pointer): SdlAppResult {.cdecl.}
  SdlAppEventFunc* = proc(appstate: pointer; event: ptr SdlEvent): SdlAppResult {.cdecl.}
  SdlAppQuitFunc* = proc(appstate: pointer; result: SdlAppResult) {.cdecl.}
  SdlMainFunc* = proc(argc: cint; argv: ptr ptr char): cint {.cdecl.}

var sdl_event_quit* {.importc: "SDL_EVENT_QUIT", header: "SDL3/SDL_events.h".}: uint32
var sdl_window_resizable* {.importc: "SDL_WINDOW_RESIZABLE", header: "SDL3/SDL_video.h".}: uint64
var sdl_window_borderless* {.importc: "SDL_WINDOW_BORDERLESS", header: "SDL3/SDL_video.h".}: uint64

proc enter_app_main_callbacks*(argc: cint; argv: ptr ptr char; appinit: SdlAppInitFunc; appiterate: SdlAppIterateFunc; appevent: SdlAppEventFunc; appquit: SdlAppQuitFunc): cint {.importc: "SDL_EnterAppMainCallbacks", header: "SDL3/SDL_main.h".}
proc set_app_metadata*(name, version, identifier: cstring): bool {.importc: "SDL_SetAppMetadata", header: "SDL3/SDL_init.h".}
proc run_app*(argc: cint; argv: ptr ptr char; main_function: SdlMainFunc; reserved: pointer): cint {.importc: "SDL_RunApp", header: "SDL3/SDL_main.h".}
proc create_window*(title: cstring; width, height: cint; flags: uint64): ptr SdlWindow {.importc: "SDL_CreateWindow", header: "SDL3/SDL_video.h".}
proc destroy_window*(window: ptr SdlWindow) {.importc: "SDL_DestroyWindow", header: "SDL3/SDL_video.h".}

proc gpu_supports_shader_formats*(format_flags: SdlGpuShaderFormat; name: cstring): bool {.importc: "SDL_GPUSupportsShaderFormats", header: "SDL3/SDL_gpu.h".}
proc gpu_supports_properties*(props: SdlPropertiesId): bool {.importc: "SDL_GPUSupportsProperties", header: "SDL3/SDL_gpu.h".}
proc create_gpu_device*(format_flags: SdlGpuShaderFormat; debug_mode: bool; name: cstring): ptr SdlGpuDevice {.importc: "SDL_CreateGPUDevice", header: "SDL3/SDL_gpu.h".}
proc create_gpu_device_with_properties*(props: SdlPropertiesId): ptr SdlGpuDevice {.importc: "SDL_CreateGPUDeviceWithProperties", header: "SDL3/SDL_gpu.h".}
proc get_num_gpu_drivers*(): cint {.importc: "SDL_GetNumGPUDrivers", header: "SDL3/SDL_gpu.h".}
proc get_gpu_driver*(index: cint): cstring {.importc: "SDL_GetGPUDriver", header: "SDL3/SDL_gpu.h".}
proc get_gpu_device_driver*(device: ptr SdlGpuDevice): cstring {.importc: "SDL_GetGPUDeviceDriver", header: "SDL3/SDL_gpu.h".}
proc get_gpu_shader_formats*(device: ptr SdlGpuDevice): SdlGpuShaderFormat {.importc: "SDL_GetGPUShaderFormats", header: "SDL3/SDL_gpu.h".}
proc get_gpu_device_properties*(device: ptr SdlGpuDevice): SdlPropertiesId {.importc: "SDL_GetGPUDeviceProperties", header: "SDL3/SDL_gpu.h".}
proc claim_window_for_gpu_device*(device: ptr SdlGpuDevice; window: ptr SdlWindow): bool {.importc: "SDL_ClaimWindowForGPUDevice", header: "SDL3/SDL_gpu.h".}
proc release_window_from_gpu_device*(device: ptr SdlGpuDevice; window: ptr SdlWindow) {.importc: "SDL_ReleaseWindowFromGPUDevice", header: "SDL3/SDL_gpu.h".}
proc destroy_gpu_device*(device: ptr SdlGpuDevice) {.importc: "SDL_DestroyGPUDevice", header: "SDL3/SDL_gpu.h".}

proc create_gpu_shader*(device: ptr SdlGpuDevice; createinfo: ptr SdlGpuShaderCreateInfo): ptr SdlGpuShader {.importc: "SDL_CreateGPUShader", header: "SDL3/SDL_gpu.h".}
proc create_gpu_graphics_pipeline*(device: ptr SdlGpuDevice; createinfo: ptr SdlGpuGraphicsPipelineCreateInfo): ptr SdlGpuGraphicsPipeline {.importc: "SDL_CreateGPUGraphicsPipeline", header: "SDL3/SDL_gpu.h".}
proc create_gpu_sampler*(device: ptr SdlGpuDevice; createinfo: ptr SdlGpuSamplerCreateInfo): ptr SdlGpuSampler {.importc: "SDL_CreateGPUSampler", header: "SDL3/SDL_gpu.h".}
proc create_gpu_texture*(device: ptr SdlGpuDevice; createinfo: ptr SdlGpuTextureCreateInfo): ptr SdlGpuTexture {.importc: "SDL_CreateGPUTexture", header: "SDL3/SDL_gpu.h".}
proc create_gpu_buffer*(device: ptr SdlGpuDevice; createinfo: ptr SdlGpuBufferCreateInfo): ptr SdlGpuBuffer {.importc: "SDL_CreateGPUBuffer", header: "SDL3/SDL_gpu.h".}
proc create_gpu_transfer_buffer*(device: ptr SdlGpuDevice; createinfo: ptr SdlGpuTransferBufferCreateInfo): ptr SdlGpuTransferBuffer {.importc: "SDL_CreateGPUTransferBuffer", header: "SDL3/SDL_gpu.h".}
proc set_gpu_buffer_name*(device: ptr SdlGpuDevice; buffer: ptr SdlGpuBuffer; text: cstring) {.importc: "SDL_SetGPUBufferName", header: "SDL3/SDL_gpu.h".}
proc set_gpu_texture_name*(device: ptr SdlGpuDevice; texture: ptr SdlGpuTexture; text: cstring) {.importc: "SDL_SetGPUTextureName", header: "SDL3/SDL_gpu.h".}
proc insert_gpu_debug_label*(command_buffer: ptr SdlGpuCommandBuffer; text: cstring) {.importc: "SDL_InsertGPUDebugLabel", header: "SDL3/SDL_gpu.h".}
proc push_gpu_debug_group*(command_buffer: ptr SdlGpuCommandBuffer; name: cstring) {.importc: "SDL_PushGPUDebugGroup", header: "SDL3/SDL_gpu.h".}
proc pop_gpu_debug_group*(command_buffer: ptr SdlGpuCommandBuffer) {.importc: "SDL_PopGPUDebugGroup", header: "SDL3/SDL_gpu.h".}
proc release_gpu_texture*(device: ptr SdlGpuDevice; texture: ptr SdlGpuTexture) {.importc: "SDL_ReleaseGPUTexture", header: "SDL3/SDL_gpu.h".}
proc release_gpu_sampler*(device: ptr SdlGpuDevice; sampler: ptr SdlGpuSampler) {.importc: "SDL_ReleaseGPUSampler", header: "SDL3/SDL_gpu.h".}
proc release_gpu_buffer*(device: ptr SdlGpuDevice; buffer: ptr SdlGpuBuffer) {.importc: "SDL_ReleaseGPUBuffer", header: "SDL3/SDL_gpu.h".}
proc release_gpu_transfer_buffer*(device: ptr SdlGpuDevice; transfer_buffer: ptr SdlGpuTransferBuffer) {.importc: "SDL_ReleaseGPUTransferBuffer", header: "SDL3/SDL_gpu.h".}
proc release_gpu_shader*(device: ptr SdlGpuDevice; shader: ptr SdlGpuShader) {.importc: "SDL_ReleaseGPUShader", header: "SDL3/SDL_gpu.h".}
proc release_gpu_graphics_pipeline*(device: ptr SdlGpuDevice; graphics_pipeline: ptr SdlGpuGraphicsPipeline) {.importc: "SDL_ReleaseGPUGraphicsPipeline", header: "SDL3/SDL_gpu.h".}

proc map_gpu_transfer_buffer*(device: ptr SdlGpuDevice; transfer_buffer: ptr SdlGpuTransferBuffer; cycle: bool): pointer {.importc: "SDL_MapGPUTransferBuffer", header: "SDL3/SDL_gpu.h".}
proc unmap_gpu_transfer_buffer*(device: ptr SdlGpuDevice; transfer_buffer: ptr SdlGpuTransferBuffer) {.importc: "SDL_UnmapGPUTransferBuffer", header: "SDL3/SDL_gpu.h".}
proc begin_gpu_copy_pass*(command_buffer: ptr SdlGpuCommandBuffer): ptr SdlGpuCopyPass {.importc: "SDL_BeginGPUCopyPass", header: "SDL3/SDL_gpu.h".}
proc upload_to_gpu_texture*(copy_pass: ptr SdlGpuCopyPass; source: ptr SdlGpuTextureTransferInfo; destination: ptr SdlGpuTextureRegion; cycle: bool) {.importc: "SDL_UploadToGPUTexture", header: "SDL3/SDL_gpu.h".}
proc upload_to_gpu_buffer*(copy_pass: ptr SdlGpuCopyPass; source: ptr SdlGpuTransferBufferLocation; destination: ptr SdlGpuBufferRegion; cycle: bool) {.importc: "SDL_UploadToGPUBuffer", header: "SDL3/SDL_gpu.h".}
proc copy_gpu_texture_to_texture*(copy_pass: ptr SdlGpuCopyPass; source, destination: ptr SdlGpuTextureLocation; w, h, d: uint32; cycle: bool) {.importc: "SDL_CopyGPUTextureToTexture", header: "SDL3/SDL_gpu.h".}
proc copy_gpu_buffer_to_buffer*(copy_pass: ptr SdlGpuCopyPass; source, destination: ptr SdlGpuBufferLocation; size: uint32; cycle: bool) {.importc: "SDL_CopyGPUBufferToBuffer", header: "SDL3/SDL_gpu.h".}
proc download_from_gpu_texture*(copy_pass: ptr SdlGpuCopyPass; source: ptr SdlGpuTextureRegion; destination: ptr SdlGpuTextureTransferInfo) {.importc: "SDL_DownloadFromGPUTexture", header: "SDL3/SDL_gpu.h".}
proc download_from_gpu_buffer*(copy_pass: ptr SdlGpuCopyPass; source: ptr SdlGpuBufferRegion; destination: ptr SdlGpuTransferBufferLocation) {.importc: "SDL_DownloadFromGPUBuffer", header: "SDL3/SDL_gpu.h".}
proc end_gpu_copy_pass*(copy_pass: ptr SdlGpuCopyPass) {.importc: "SDL_EndGPUCopyPass", header: "SDL3/SDL_gpu.h".}
proc generate_mipmaps_for_gpu_texture*(command_buffer: ptr SdlGpuCommandBuffer; texture: ptr SdlGpuTexture) {.importc: "SDL_GenerateMipmapsForGPUTexture", header: "SDL3/SDL_gpu.h".}
proc blit_gpu_texture*(command_buffer: ptr SdlGpuCommandBuffer; info: ptr SdlGpuBlitInfo) {.importc: "SDL_BlitGPUTexture", header: "SDL3/SDL_gpu.h".}

proc acquire_gpu_command_buffer*(device: ptr SdlGpuDevice): ptr SdlGpuCommandBuffer {.importc: "SDL_AcquireGPUCommandBuffer", header: "SDL3/SDL_gpu.h".}
proc set_gpu_swapchain_parameters*(device: ptr SdlGpuDevice; window: ptr SdlWindow; swapchain_composition: SdlGpuSwapchainComposition; present_mode: SdlGpuPresentMode): bool {.importc: "SDL_SetGPUSwapchainParameters", header: "SDL3/SDL_gpu.h".}
proc window_supports_gpu_swapchain_composition*(device: ptr SdlGpuDevice; window: ptr SdlWindow; swapchain_composition: SdlGpuSwapchainComposition): bool {.importc: "SDL_WindowSupportsGPUSwapchainComposition", header: "SDL3/SDL_gpu.h".}
proc window_supports_gpu_present_mode*(device: ptr SdlGpuDevice; window: ptr SdlWindow; present_mode: SdlGpuPresentMode): bool {.importc: "SDL_WindowSupportsGPUPresentMode", header: "SDL3/SDL_gpu.h".}
proc get_gpu_swapchain_texture_format*(device: ptr SdlGpuDevice; window: ptr SdlWindow): SdlGpuTextureFormat {.importc: "SDL_GetGPUSwapchainTextureFormat", header: "SDL3/SDL_gpu.h".}
proc acquire_gpu_swapchain_texture*(command_buffer: ptr SdlGpuCommandBuffer; window: ptr SdlWindow; swapchain_texture: ptr ptr SdlGpuTexture; width, height: ptr uint32): bool {.importc: "SDL_AcquireGPUSwapchainTexture", header: "SDL3/SDL_gpu.h".}
proc wait_and_acquire_gpu_swapchain_texture*(command_buffer: ptr SdlGpuCommandBuffer; window: ptr SdlWindow; swapchain_texture: ptr ptr SdlGpuTexture; width, height: ptr uint32): bool {.importc: "SDL_WaitAndAcquireGPUSwapchainTexture", header: "SDL3/SDL_gpu.h".}
proc wait_for_gpu_swapchain*(device: ptr SdlGpuDevice; window: ptr SdlWindow): bool {.importc: "SDL_WaitForGPUSwapchain", header: "SDL3/SDL_gpu.h".}
proc set_gpu_allowed_frames_in_flight*(device: ptr SdlGpuDevice; allowed_frames_in_flight: uint32): bool {.importc: "SDL_SetGPUAllowedFramesInFlight", header: "SDL3/SDL_gpu.h".}
proc begin_gpu_render_pass*(command_buffer: ptr SdlGpuCommandBuffer; color_target_infos: ptr SdlGpuColorTargetInfo; num_color_targets: uint32; depth_stencil_target_info: ptr SdlGpuDepthStencilTargetInfo): ptr SdlGpuRenderPass {.importc: "SDL_BeginGPURenderPass", header: "SDL3/SDL_gpu.h".}
proc bind_gpu_graphics_pipeline*(render_pass: ptr SdlGpuRenderPass; graphics_pipeline: ptr SdlGpuGraphicsPipeline) {.importc: "SDL_BindGPUGraphicsPipeline", header: "SDL3/SDL_gpu.h".}
proc set_gpu_viewport*(render_pass: ptr SdlGpuRenderPass; viewport: ptr SdlGpuViewport) {.importc: "SDL_SetGPUViewport", header: "SDL3/SDL_gpu.h".}
proc set_gpu_scissor*(render_pass: ptr SdlGpuRenderPass; scissor: ptr SdlRect) {.importc: "SDL_SetGPUScissor", header: "SDL3/SDL_gpu.h".}
proc set_gpu_blend_constants*(render_pass: ptr SdlGpuRenderPass; blend_constants: SdlFColor) {.importc: "SDL_SetGPUBlendConstants", header: "SDL3/SDL_gpu.h".}
proc set_gpu_stencil_reference*(render_pass: ptr SdlGpuRenderPass; reference: uint8) {.importc: "SDL_SetGPUStencilReference", header: "SDL3/SDL_gpu.h".}
proc bind_gpu_vertex_buffers*(render_pass: ptr SdlGpuRenderPass; first_slot: uint32; bindings: ptr SdlGpuBufferBinding; num_bindings: uint32) {.importc: "SDL_BindGPUVertexBuffers", header: "SDL3/SDL_gpu.h".}
proc bind_gpu_index_buffer*(render_pass: ptr SdlGpuRenderPass; binding: ptr SdlGpuBufferBinding; index_element_size: SdlGpuIndexElementSize) {.importc: "SDL_BindGPUIndexBuffer", header: "SDL3/SDL_gpu.h".}
proc bind_gpu_vertex_samplers*(render_pass: ptr SdlGpuRenderPass; first_slot: uint32; texture_sampler_bindings: ptr SdlGpuTextureSamplerBinding; num_bindings: uint32) {.importc: "SDL_BindGPUVertexSamplers", header: "SDL3/SDL_gpu.h".}
proc bind_gpu_fragment_samplers*(render_pass: ptr SdlGpuRenderPass; first_slot: uint32; texture_sampler_bindings: ptr SdlGpuTextureSamplerBinding; num_bindings: uint32) {.importc: "SDL_BindGPUFragmentSamplers", header: "SDL3/SDL_gpu.h".}
proc bind_gpu_vertex_storage_textures*(render_pass: ptr SdlGpuRenderPass; first_slot: uint32; storage_textures: ptr ptr SdlGpuTexture; num_bindings: uint32) {.importc: "SDL_BindGPUVertexStorageTextures", header: "SDL3/SDL_gpu.h".}
proc bind_gpu_vertex_storage_buffers*(render_pass: ptr SdlGpuRenderPass; first_slot: uint32; storage_buffers: ptr ptr SdlGpuBuffer; num_bindings: uint32) {.importc: "SDL_BindGPUVertexStorageBuffers", header: "SDL3/SDL_gpu.h".}
proc bind_gpu_fragment_storage_textures*(render_pass: ptr SdlGpuRenderPass; first_slot: uint32; storage_textures: ptr ptr SdlGpuTexture; num_bindings: uint32) {.importc: "SDL_BindGPUFragmentStorageTextures", header: "SDL3/SDL_gpu.h".}
proc bind_gpu_fragment_storage_buffers*(render_pass: ptr SdlGpuRenderPass; first_slot: uint32; storage_buffers: ptr ptr SdlGpuBuffer; num_bindings: uint32) {.importc: "SDL_BindGPUFragmentStorageBuffers", header: "SDL3/SDL_gpu.h".}
proc push_gpu_vertex_uniform_data*(command_buffer: ptr SdlGpuCommandBuffer; slot_index: uint32; data: pointer; length: uint32) {.importc: "SDL_PushGPUVertexUniformData", header: "SDL3/SDL_gpu.h".}
proc push_gpu_fragment_uniform_data*(command_buffer: ptr SdlGpuCommandBuffer; slot_index: uint32; data: pointer; length: uint32) {.importc: "SDL_PushGPUFragmentUniformData", header: "SDL3/SDL_gpu.h".}
proc draw_gpu_primitives*(render_pass: ptr SdlGpuRenderPass; num_vertices, num_instances, first_vertex, first_instance: uint32) {.importc: "SDL_DrawGPUPrimitives", header: "SDL3/SDL_gpu.h".}
proc draw_gpu_indexed_primitives*(render_pass: ptr SdlGpuRenderPass; num_indices, num_instances, first_index: uint32; vertex_offset: cint; first_instance: uint32) {.importc: "SDL_DrawGPUIndexedPrimitives", header: "SDL3/SDL_gpu.h".}
proc draw_gpu_primitives_indirect*(render_pass: ptr SdlGpuRenderPass; buffer: ptr SdlGpuBuffer; offset, draw_count: uint32) {.importc: "SDL_DrawGPUPrimitivesIndirect", header: "SDL3/SDL_gpu.h".}
proc draw_gpu_indexed_primitives_indirect*(render_pass: ptr SdlGpuRenderPass; buffer: ptr SdlGpuBuffer; offset, draw_count: uint32) {.importc: "SDL_DrawGPUIndexedPrimitivesIndirect", header: "SDL3/SDL_gpu.h".}
proc end_gpu_render_pass*(render_pass: ptr SdlGpuRenderPass) {.importc: "SDL_EndGPURenderPass", header: "SDL3/SDL_gpu.h".}
proc submit_gpu_command_buffer*(command_buffer: ptr SdlGpuCommandBuffer): bool {.importc: "SDL_SubmitGPUCommandBuffer", header: "SDL3/SDL_gpu.h".}
proc submit_gpu_command_buffer_and_acquire_fence*(command_buffer: ptr SdlGpuCommandBuffer): ptr SdlGpuFence {.importc: "SDL_SubmitGPUCommandBufferAndAcquireFence", header: "SDL3/SDL_gpu.h".}
proc cancel_gpu_command_buffer*(command_buffer: ptr SdlGpuCommandBuffer): bool {.importc: "SDL_CancelGPUCommandBuffer", header: "SDL3/SDL_gpu.h".}
proc wait_for_gpu_idle*(device: ptr SdlGpuDevice): bool {.importc: "SDL_WaitForGPUIdle", header: "SDL3/SDL_gpu.h".}
proc wait_for_gpu_fences*(device: ptr SdlGpuDevice; wait_all: bool; fences: ptr ptr SdlGpuFence; num_fences: uint32): bool {.importc: "SDL_WaitForGPUFences", header: "SDL3/SDL_gpu.h".}
proc query_gpu_fence*(device: ptr SdlGpuDevice; fence: ptr SdlGpuFence): bool {.importc: "SDL_QueryGPUFence", header: "SDL3/SDL_gpu.h".}
proc release_gpu_fence*(device: ptr SdlGpuDevice; fence: ptr SdlGpuFence) {.importc: "SDL_ReleaseGPUFence", header: "SDL3/SDL_gpu.h".}
proc gpu_texture_format_texel_block_size*(format: SdlGpuTextureFormat): uint32 {.importc: "SDL_GPUTextureFormatTexelBlockSize", header: "SDL3/SDL_gpu.h".}
proc gpu_texture_supports_format*(device: ptr SdlGpuDevice; format: SdlGpuTextureFormat; texture_type: SdlGpuTextureType; usage: SdlGpuTextureUsageFlags): bool {.importc: "SDL_GPUTextureSupportsFormat", header: "SDL3/SDL_gpu.h".}
proc gpu_texture_supports_sample_count*(device: ptr SdlGpuDevice; format: SdlGpuTextureFormat; sample_count: SdlGpuSampleCount): bool {.importc: "SDL_GPUTextureSupportsSampleCount", header: "SDL3/SDL_gpu.h".}
proc calculate_gpu_texture_format_size*(format: SdlGpuTextureFormat; width, height, depth_or_layer_count: uint32): uint32 {.importc: "SDL_CalculateGPUTextureFormatSize", header: "SDL3/SDL_gpu.h".}
proc get_pixel_format_from_gpu_texture_format*(format: SdlGpuTextureFormat): SdlPixelFormat {.importc: "SDL_GetPixelFormatFromGPUTextureFormat", header: "SDL3/SDL_gpu.h".}
proc get_gpu_texture_format_from_pixel_format*(format: SdlPixelFormat): SdlGpuTextureFormat {.importc: "SDL_GetGPUTextureFormatFromPixelFormat", header: "SDL3/SDL_gpu.h".}
