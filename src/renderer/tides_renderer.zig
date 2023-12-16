// Tides Renderer Zig Bindings
// ===========================
const std = @import("std");

pub const Slice = extern struct {
    data: ?*const anyopaque,
    size: u64,
};

pub const AppSettings = extern struct {
    width: i32,
    height: i32,
    window_native_handle: *anyopaque,
    v_sync_enabled: bool,
};

pub const buffered_frames_count: u32 = 2;

pub fn initRenderer(app_settings: *AppSettings) i32 {
    return TR_initRenderer(app_settings);
}
extern fn TR_initRenderer(app_settings: *AppSettings) i32;

pub fn exitRenderer() void {
    TR_exitRenderer();
}
extern fn TR_exitRenderer() void;

pub fn frameIndex() u32 {
    return TR_frameIndex();
}
extern fn TR_frameIndex() u32;

pub fn onLoad(reload_desc: *ReloadDesc) bool {
    return TR_onLoad(reload_desc);
}
extern fn TR_onLoad(reload_desc: *ReloadDesc) bool;

pub fn onUnload(reload_desc: *ReloadDesc) void {
    TR_onUnload(reload_desc);
}
extern fn TR_onUnload(reload_desc: *ReloadDesc) void;

pub const Camera = extern struct {
    view_matrix: [16]f32,
    proj_matrix: [16]f32,
};

pub fn draw(camera: Camera) void {
    TR_draw(camera);
}
extern fn TR_draw(camera: Camera) void;

pub const ReloadType = packed struct(u32) {
    RESIZE: bool = false, // 0x1
    SHADER: bool = false, // 0x2
    RENDERTARGET: bool = false, // 0x4
    __unused: u29 = 0,

    pub const ALL = ReloadType{
        .RESIZE = true,
        .SHADER = true,
        .RENDERTARGET = true,
    };
};

pub const ReloadDesc = extern struct {
    reload_type: ReloadType,
};

pub const MeshHandle = extern struct {
    id: u32,
};
pub fn loadMesh(path: [:0]const u8) MeshHandle {
    return TR_loadMesh(path);
}
extern fn TR_loadMesh(path: [*:0]const u8) MeshHandle;

pub const Renderable = extern struct {
    id: u64,
    mesh_handle: MeshHandle,
    // NOTE(gmodarelli): These are here just as a test
    transform_buffer_index: u32,
    heightmap_index: u32,
    start_instanceLocation: u32,
};

pub fn registerRenderable(renderable: Renderable) void {
    TR_registerRenderable(renderable);
}
extern fn TR_registerRenderable(renderable: Renderable) void;

pub fn updateRenderable(renderable: Renderable) void {
    TR_updateRenderable(renderable);
}
extern fn TR_updateRenderable(renderable: Renderable) void;

pub const BufferHandle = extern struct {
    id: u32,
};
pub fn createBuffer(initial_data: Slice, data_stride: u32, debug_name: [:0]const u8) BufferHandle {
    return TR_createBuffer(initial_data, data_stride, debug_name);
}
extern fn TR_createBuffer(initial_data: Slice, data_stride: u32, debug_name: [*:0]const u8) BufferHandle;

pub fn updateBuffer(data: Slice, buffer_handle: BufferHandle) void {
    TR_updateBuffer(data, buffer_handle);
}
extern fn TR_updateBuffer(data: Slice, buffer_handle: BufferHandle) void;

pub fn bufferBindlessIndex(buffer_handle: BufferHandle) u32 {
    return TR_bufferBindlessIndex(buffer_handle);
}
extern fn TR_bufferBindlessIndex(buffer_handle: BufferHandle) u32;

pub const TextureHandle = extern struct {
    id: u32,
};

pub fn loadTexture(path: [:0]const u8) TextureHandle {
    return TR_loadTexture(path);
}
extern fn TR_loadTexture(path: [*:0]const u8) TextureHandle;

pub fn loadTextureFromMemory(width: u32, height: u32, format: TinyImageFormat, data_slice: Slice, debug_name: [:0]const u8) TextureHandle {
    return TR_loadTextureFromMemory(width, height, format, data_slice, debug_name);
}
extern fn TR_loadTextureFromMemory(width: u32, height: u32, format: TinyImageFormat, data_slice: Slice, debug_name: [*:0]const u8) TextureHandle;

pub fn textureBindlessIndex(texture_handle: TextureHandle) u32 {
    return TR_textureBindlessIndex(texture_handle);
}
extern fn TR_textureBindlessIndex(texture_handle: TextureHandle) u32;

pub const DrawCallTerrainInstanced = struct {
    mesh_handle: MeshHandle,
    start_instance_location: u32,
    instance_count: u32,
};

pub const TerrainPushConstants = struct {
    start_instance_location: u32,
    instance_data_buffer_index: u32,
    material_buffer_index: u32,
};

pub fn registerTerrainDrawCalls(draw_calls_slice: Slice, push_constants_slice: Slice) void {
    TR_registerTerrainDrawCalls(draw_calls_slice, push_constants_slice);
}
extern fn TR_registerTerrainDrawCalls(draw_calls_slice: Slice, push_constants_slice: Slice) void;

// pub const TextureDesc = extern struct {
//     /// Optional placement (addTexture will place/bind buffer in this memory instead of allocating space)
//     placement: *ResourcePlacement, // NOTE(gmodarelli): This requires D3D12-specific data, so I'm gonna ignore it for now
//     /// Optimized clear value (recommended to use this same value when clearing the rendertarget)
//     clear_value: ClearValue,
//     /// Pointer to native texture handle if the texture does not own underlying resource
//     native_handle: *anyopaque,
//     /// Debug name used in gpu profile
//     name: [*:0]const u8,
//     /// GPU indices to share this texture
//     shared_node_indices: *u32,
//     /// Texture creation flags (decides memory allocation strategy, sharing access,...)
//     flags: TextureCreationFlags,
//     /// Width
//     width: u32,
//     /// Height
//     height: u32,
//     /// Depth (Should be 1 if not a mType is not TEXTURE_TYPE_3D)
//     depth: u32,
//     /// Texture array size (Should be 1 if texture is not a texture array or cubemap)
//     array_size: u32,
//     /// Number of mip levels
//     mip_levels: u32,
//     /// Number of multisamples per pixel (currently Textures created with mUsage TEXTURE_USAGE_SAMPLED_IMAGE only support SAMPLE_COUNT_1)
//     sample_count: SampleCount,
//     /// The image quality level. The higher the quality, the lower the performance. The valid range is between zero and the value appropriate for mSampleCount
//     sample_quality: u32,
//     ///  image format
//     format: TinyImageFormat,
//     /// What state will the texture get created in
//     start_state: ResourceState,
//     /// Descriptor creation
//     descriptors: DescriptorType,
//     /// Number of GPUs to share this texture
//     shared_node_index_count: u32,
//     /// GPU which will own this texture
//     node_index: u32,
// };
//
// pub const ResourcePlacement = extern struct {
//     heap: u64, // NOTE(gmodarelli): Faking a ptr size so that TextureDesc has the same memory alignment as its CPP counterpart
//     offset: u64,
// }

// pub const ClearValue = extern union {
//     color: extern struct {
//         r: f32,
//         g: f32,
//         b: f32,
//         a: f32,
//     },
//
//     depth: extern struct {
//         depth: f32,
//         stencil: u32,
//     },
// };
//
// pub const TextureCreationFlags = packed struct(u32) {
//     /// Texture will allocate its own memory (COMMITTED resource)
//     OWN_MEMORY_BIT: bool = false, // 0x01
//     /// Texture will be allocated in memory which can be shared among multiple processes
//     EXPORT_BIT: bool = false, // 0x02,
//     /// Texture will be allocated in memory which can be shared among multiple gpus
//     EXPORT_ADAPTER_BIT: bool = false, // 0x04,
//     /// Texture will be imported from a handle created in another process
//     IMPORT_BIT: bool = false, // 0x08,
//     /// Use ESRAM to store this texture
//     ESRAM: bool = false, // 0x10,
//     /// Use on-tile memory to store this texture
//     ON_TILE: bool = false, // 0x20,
//     /// Prevent compression meta data from generating (XBox)
//     NO_COMPRESSION: bool = false, // 0x40,
//     /// Force 2D instead of automatically determining dimension based on width, height, depth
//     FORCE_2D: bool = false, // 0x80,
//     /// Force 3D instead of automatically determining dimension based on width, height, depth
//     FORCE_3D: bool = false, // 0x100,
//     /// Display target
//     ALLOW_DISPLAY_TARGET: bool = false, // 0x200,
//     /// Create an sRGB texture.
//     SRGB: bool = false, // 0x400,
//     /// Create a normal map texture
//     NORMAL_MAP: bool = false, // 0x800,
//     /// Fast clear
//     FAST_CLEAR: bool = false, // 0x1000,
//     /// Fragment mask
//     FRAG_MASK: bool = false, // 0x2000,
//     /// Doubles the amount of array layers of the texture when rendering VR. Also forces the texture to be a 2D Array texture.
//     VR_MULTIVIEW: bool = false, // 0x4000,
//     /// Binds the FFR fragment density if this texture is used as a render target.
//     VR_FOVEATED_RENDERING: bool = false, // 0x8000,
//     /// Creates resolve attachment for auto resolve (MSAA on tiled architecture - Resolve can be done on tile through render pass)
//     CREATE_RESOLVE_ATTACHMENT: bool = false, // 0x10000,
//
//     __unused: u15 = 0,
//
//     /// Default flag (Texture will use default allocation strategy decided by the api specific allocator)
//     pub const NONE = TextureCreationFlags{};
// };
//
// pub const SampleCount = enum(u32) {
//     COUNT_1 = 1,
//     COUNT_2 = 2,
//     COUNT_4 = 4,
//     COUNT_8 = 8,
//     COUNT_16 = 16,
//     COUNT_COUNT = 5,
// };
//
// pub const ResourceState = packed struct(u32) {
//     VERTEX_AND_CONSTANT_BUFFER: bool = false, // 0x1,
//     INDEX_BUFFER: bool = false, // 0x2,
//     RENDER_TARGET: bool = false, // 0x4,
//     UNORDERED_ACCESS: bool = false, // 0x8,
//     DEPTH_WRITE: bool = false, // 0x10,
//     DEPTH_READ: bool = false, // 0x20,
//     NON_PIXEL_SHADER_RESOURCE: bool = false, // 0x40,
//     PIXEL_SHADER_RESOURCE: bool = false, // 0x80,
//     STREAM_OUT: bool = false, // 0x100,
//     INDIRECT_ARGUMENT: bool = false, // 0x200,
//     COPY_DEST: bool = false, // 0x400,
//     COPY_SOURCE: bool = false, // 0x800,
//     PRESENT: bool = false, // 0x1000,
//     COMMON: bool = false, // 0x2000,
//     ACCELERATION_STRUCTURE_READ: bool = false, // 0x4000,
//     ACCELERATION_STRUCTURE_WRITE: bool = false, // 0x8000,
//     SHADING_RATE_SOURCE: bool = false, // 0x10000,
//     __unused: u15 = 0,
//
//     pub const SHADER_RESOURCE = ResourceState{
//         .NON_PIXEL_SHADER_RESOURCE = true,
//         .PIXEL_SHADER_RESOURCE = true,
//     }; // 0x40 | 0x80,
//
//     pub const GENERIC_READ = ResourceState{
//         .VERTEX_AND_CONSTANT_BUFFER = true,
//         .INDEX_BUFFER = true,
//         .NON_PIXEL_SHADER_RESOURCE = true,
//         .PIXEL_SHADER_RESOURCE = true,
//         .INDIRECT_ARGUMENT = true,
//         .COPY_SOURCE = true,
//     }; // (((((0x1 | 0x2) | 0x40) | 0x80) | 0x200) | 0x800),
// };
//
// pub const DescriptorType = packed struct(u32) {
//     SAMPLER: bool = false, // 0x01,
//     // SRV Read only texture
//     TEXTURE: bool = false, // (SAMPLER << 1),
//     /// UAV Texture
//     RW_TEXTURE: bool = false, // (TEXTURE << 1),
//     // SRV Read only buffer
//     BUFFER: bool = false, // (RW_TEXTURE << 1),
//     _BUFFER_RAW: bool = false, // (BUFFER << 1)
//     /// UAV Buffer
//     RW_BUFFER: bool = false, // (BUFFER << 2),
//     _RW_BUFFER_RAW: bool = false, // (RW_BUFFER << 1)
//     /// Uniform buffer
//     UNIFORM_BUFFER: bool = false, // (RW_BUFFER << 2),
//     /// Push constant / Root constant
//     ROOT_CONSTANT: bool = false, // (UNIFORM_BUFFER << 1),
//     /// IA
//     VERTEX_BUFFER: bool = false, // (ROOT_CONSTANT << 1),
//     INDEX_BUFFER: bool = false, // (VERTEX_BUFFER << 1),
//     INDIRECT_BUFFER: bool = false, // (INDEX_BUFFER << 1),
//     /// Cubemap SRV
//     _TEXTURE_CUBE: bool = false, // (INDIRECT_BUFFER << 1),
//     /// RTV / DSV per mip slice
//     RENDER_TARGET_MIP_SLICES: bool = false, // (INDIRECT_BUFFER << 2),
//     /// RTV / DSV per array slice
//     RENDER_TARGET_ARRAY_SLICES: bool = false, // (RENDER_TARGET_MIP_SLICES << 1),
//     /// RTV / DSV per depth slice
//     RENDER_TARGET_DEPTH_SLICES: bool = false, // (RENDER_TARGET_ARRAY_SLICES << 1),
//     INDIRECT_COMMAND_BUFFER: bool = false, // (RENDER_TARGET_DEPTH_SLICES << 1),
//     /// Raytracing acceleration structure
//     ACCELERATION_STRUCTURE: bool = false, // (INDIRECT_COMMAND_BUFFER << 1),
//
//     /// Subpass input (descriptor type only available in Vulkan)
//     INPUT_ATTACHMENT: bool = false, // (ACCELERATION_STRUCTURE << 1),
//     TEXEL_BUFFER: bool = false, // (INPUT_ATTACHMENT << 1),
//     RW_TEXEL_BUFFER: bool = false, // (TEXEL_BUFFER << 1),
//     COMBINED_IMAGE_SAMPLER: bool = false, // (RW_TEXEL_BUFFER << 1),
//     __unused: u10 = 0,
//
//     pub const UNDEFINED = DescriptorType{};
//
//     pub const BUFFER_RAW = DescriptorType{ ._BUFFER_RAW = true, .BUFFER = true }; // (BUFFER | (BUFFER << 1))
//     pub const RW_BUFFER_RAW = DescriptorType{ ._RW_BUFFER_RAW = true, .RW_BUFFER = true }; // (RW_BUFFER | (RW_BUFFER << 1))
//
//     pub const TEXTURE_CUBE = DescriptorType{ ._TEXTURE_CUBE = true, .TEXTURE = true }; // (TEXTURE | (INDIRECT_BUFFER << 1)),
// };

pub const TinyImageFormat = enum(u32) {
    UNDEFINED = 0,
    R1_UNORM = 1,
    R2_UNORM = 2,
    R4_UNORM = 3,
    R4G4_UNORM = 4,
    G4R4_UNORM = 5,
    A8_UNORM = 6,
    R8_UNORM = 7,
    R8_SNORM = 8,
    R8_UINT = 9,
    R8_SINT = 10,
    R8_SRGB = 11,
    B2G3R3_UNORM = 12,
    R4G4B4A4_UNORM = 13,
    R4G4B4X4_UNORM = 14,
    B4G4R4A4_UNORM = 15,
    B4G4R4X4_UNORM = 16,
    A4R4G4B4_UNORM = 17,
    X4R4G4B4_UNORM = 18,
    A4B4G4R4_UNORM = 19,
    X4B4G4R4_UNORM = 20,
    R5G6B5_UNORM = 21,
    B5G6R5_UNORM = 22,
    R5G5B5A1_UNORM = 23,
    B5G5R5A1_UNORM = 24,
    A1B5G5R5_UNORM = 25,
    A1R5G5B5_UNORM = 26,
    R5G5B5X1_UNORM = 27,
    B5G5R5X1_UNORM = 28,
    X1R5G5B5_UNORM = 29,
    X1B5G5R5_UNORM = 30,
    B2G3R3A8_UNORM = 31,
    R8G8_UNORM = 32,
    R8G8_SNORM = 33,
    G8R8_UNORM = 34,
    G8R8_SNORM = 35,
    R8G8_UINT = 36,
    R8G8_SINT = 37,
    R8G8_SRGB = 38,
    R16_UNORM = 39,
    R16_SNORM = 40,
    R16_UINT = 41,
    R16_SINT = 42,
    R16_SFLOAT = 43,
    R16_SBFLOAT = 44,
    R8G8B8_UNORM = 45,
    R8G8B8_SNORM = 46,
    R8G8B8_UINT = 47,
    R8G8B8_SINT = 48,
    R8G8B8_SRGB = 49,
    B8G8R8_UNORM = 50,
    B8G8R8_SNORM = 51,
    B8G8R8_UINT = 52,
    B8G8R8_SINT = 53,
    B8G8R8_SRGB = 54,
    R8G8B8A8_UNORM = 55,
    R8G8B8A8_SNORM = 56,
    R8G8B8A8_UINT = 57,
    R8G8B8A8_SINT = 58,
    R8G8B8A8_SRGB = 59,
    B8G8R8A8_UNORM = 60,
    B8G8R8A8_SNORM = 61,
    B8G8R8A8_UINT = 62,
    B8G8R8A8_SINT = 63,
    B8G8R8A8_SRGB = 64,
    R8G8B8X8_UNORM = 65,
    B8G8R8X8_UNORM = 66,
    R16G16_UNORM = 67,
    G16R16_UNORM = 68,
    R16G16_SNORM = 69,
    G16R16_SNORM = 70,
    R16G16_UINT = 71,
    R16G16_SINT = 72,
    R16G16_SFLOAT = 73,
    R16G16_SBFLOAT = 74,
    R32_UINT = 75,
    R32_SINT = 76,
    R32_SFLOAT = 77,
    A2R10G10B10_UNORM = 78,
    A2R10G10B10_UINT = 79,
    A2R10G10B10_SNORM = 80,
    A2R10G10B10_SINT = 81,
    A2B10G10R10_UNORM = 82,
    A2B10G10R10_UINT = 83,
    A2B10G10R10_SNORM = 84,
    A2B10G10R10_SINT = 85,
    R10G10B10A2_UNORM = 86,
    R10G10B10A2_UINT = 87,
    R10G10B10A2_SNORM = 88,
    R10G10B10A2_SINT = 89,
    B10G10R10A2_UNORM = 90,
    B10G10R10A2_UINT = 91,
    B10G10R10A2_SNORM = 92,
    B10G10R10A2_SINT = 93,
    B10G11R11_UFLOAT = 94,
    E5B9G9R9_UFLOAT = 95,
    R16G16B16_UNORM = 96,
    R16G16B16_SNORM = 97,
    R16G16B16_UINT = 98,
    R16G16B16_SINT = 99,
    R16G16B16_SFLOAT = 100,
    R16G16B16_SBFLOAT = 101,
    R16G16B16A16_UNORM = 102,
    R16G16B16A16_SNORM = 103,
    R16G16B16A16_UINT = 104,
    R16G16B16A16_SINT = 105,
    R16G16B16A16_SFLOAT = 106,
    R16G16B16A16_SBFLOAT = 107,
    R32G32_UINT = 108,
    R32G32_SINT = 109,
    R32G32_SFLOAT = 110,
    R32G32B32_UINT = 111,
    R32G32B32_SINT = 112,
    R32G32B32_SFLOAT = 113,
    R32G32B32A32_UINT = 114,
    R32G32B32A32_SINT = 115,
    R32G32B32A32_SFLOAT = 116,
    R64_UINT = 117,
    R64_SINT = 118,
    R64_SFLOAT = 119,
    R64G64_UINT = 120,
    R64G64_SINT = 121,
    R64G64_SFLOAT = 122,
    R64G64B64_UINT = 123,
    R64G64B64_SINT = 124,
    R64G64B64_SFLOAT = 125,
    R64G64B64A64_UINT = 126,
    R64G64B64A64_SINT = 127,
    R64G64B64A64_SFLOAT = 128,
    D16_UNORM = 129,
    X8_D24_UNORM = 130,
    D32_SFLOAT = 131,
    S8_UINT = 132,
    D16_UNORM_S8_UINT = 133,
    D24_UNORM_S8_UINT = 134,
    D32_SFLOAT_S8_UINT = 135,
    DXBC1_RGB_UNORM = 136,
    DXBC1_RGB_SRGB = 137,
    DXBC1_RGBA_UNORM = 138,
    DXBC1_RGBA_SRGB = 139,
    DXBC2_UNORM = 140,
    DXBC2_SRGB = 141,
    DXBC3_UNORM = 142,
    DXBC3_SRGB = 143,
    DXBC4_UNORM = 144,
    DXBC4_SNORM = 145,
    DXBC5_UNORM = 146,
    DXBC5_SNORM = 147,
    DXBC6H_UFLOAT = 148,
    DXBC6H_SFLOAT = 149,
    DXBC7_UNORM = 150,
    DXBC7_SRGB = 151,
    PVRTC1_2BPP_UNORM = 152,
    PVRTC1_4BPP_UNORM = 153,
    PVRTC2_2BPP_UNORM = 154,
    PVRTC2_4BPP_UNORM = 155,
    PVRTC1_2BPP_SRGB = 156,
    PVRTC1_4BPP_SRGB = 157,
    PVRTC2_2BPP_SRGB = 158,
    PVRTC2_4BPP_SRGB = 159,
    ETC2_R8G8B8_UNORM = 160,
    ETC2_R8G8B8_SRGB = 161,
    ETC2_R8G8B8A1_UNORM = 162,
    ETC2_R8G8B8A1_SRGB = 163,
    ETC2_R8G8B8A8_UNORM = 164,
    ETC2_R8G8B8A8_SRGB = 165,
    ETC2_EAC_R11_UNORM = 166,
    ETC2_EAC_R11_SNORM = 167,
    ETC2_EAC_R11G11_UNORM = 168,
    ETC2_EAC_R11G11_SNORM = 169,
    ASTC_4x4_UNORM = 170,
    ASTC_4x4_SRGB = 171,
    ASTC_5x4_UNORM = 172,
    ASTC_5x4_SRGB = 173,
    ASTC_5x5_UNORM = 174,
    ASTC_5x5_SRGB = 175,
    ASTC_6x5_UNORM = 176,
    ASTC_6x5_SRGB = 177,
    ASTC_6x6_UNORM = 178,
    ASTC_6x6_SRGB = 179,
    ASTC_8x5_UNORM = 180,
    ASTC_8x5_SRGB = 181,
    ASTC_8x6_UNORM = 182,
    ASTC_8x6_SRGB = 183,
    ASTC_8x8_UNORM = 184,
    ASTC_8x8_SRGB = 185,
    ASTC_10x5_UNORM = 186,
    ASTC_10x5_SRGB = 187,
    ASTC_10x6_UNORM = 188,
    ASTC_10x6_SRGB = 189,
    ASTC_10x8_UNORM = 190,
    ASTC_10x8_SRGB = 191,
    ASTC_10x10_UNORM = 192,
    ASTC_10x10_SRGB = 193,
    ASTC_12x10_UNORM = 194,
    ASTC_12x10_SRGB = 195,
    ASTC_12x12_UNORM = 196,
    ASTC_12x12_SRGB = 197,
    CLUT_P4 = 198,
    CLUT_P4A4 = 199,
    CLUT_P8 = 200,
    CLUT_P8A8 = 201,
    R4G4B4A4_UNORM_PACK16 = 202,
    B4G4R4A4_UNORM_PACK16 = 203,
    R5G6B5_UNORM_PACK16 = 204,
    B5G6R5_UNORM_PACK16 = 205,
    R5G5B5A1_UNORM_PACK16 = 206,
    B5G5R5A1_UNORM_PACK16 = 207,
    A1R5G5B5_UNORM_PACK16 = 208,
    G16B16G16R16_422_UNORM = 209,
    B16G16R16G16_422_UNORM = 210,
    R12X4G12X4B12X4A12X4_UNORM_4PACK16 = 211,
    G12X4B12X4G12X4R12X4_422_UNORM_4PACK16 = 212,
    B12X4G12X4R12X4G12X4_422_UNORM_4PACK16 = 213,
    R10X6G10X6B10X6A10X6_UNORM_4PACK16 = 214,
    G10X6B10X6G10X6R10X6_422_UNORM_4PACK16 = 215,
    B10X6G10X6R10X6G10X6_422_UNORM_4PACK16 = 216,
    G8B8G8R8_422_UNORM = 217,
    B8G8R8G8_422_UNORM = 218,
    G8_B8_R8_3PLANE_420_UNORM = 219,
    G8_B8R8_2PLANE_420_UNORM = 220,
    G8_B8_R8_3PLANE_422_UNORM = 221,
    G8_B8R8_2PLANE_422_UNORM = 222,
    G8_B8_R8_3PLANE_444_UNORM = 223,
    G10X6_B10X6_R10X6_3PLANE_420_UNORM_3PACK16 = 224,
    G10X6_B10X6_R10X6_3PLANE_422_UNORM_3PACK16 = 225,
    G10X6_B10X6_R10X6_3PLANE_444_UNORM_3PACK16 = 226,
    G10X6_B10X6R10X6_2PLANE_420_UNORM_3PACK16 = 227,
    G10X6_B10X6R10X6_2PLANE_422_UNORM_3PACK16 = 228,
    G12X4_B12X4_R12X4_3PLANE_420_UNORM_3PACK16 = 229,
    G12X4_B12X4_R12X4_3PLANE_422_UNORM_3PACK16 = 230,
    G12X4_B12X4_R12X4_3PLANE_444_UNORM_3PACK16 = 231,
    G12X4_B12X4R12X4_2PLANE_420_UNORM_3PACK16 = 232,
    G12X4_B12X4R12X4_2PLANE_422_UNORM_3PACK16 = 233,
    G16_B16_R16_3PLANE_420_UNORM = 234,
    G16_B16_R16_3PLANE_422_UNORM = 235,
    G16_B16_R16_3PLANE_444_UNORM = 236,
    G16_B16R16_2PLANE_420_UNORM = 237,
    G16_B16R16_2PLANE_422_UNORM = 238,
};
