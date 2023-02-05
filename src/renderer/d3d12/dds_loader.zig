// Ported from DirectXTK
// https://github.com/microsoft/DirectXTK12/blob/main/Src/DDSTextureLoader.cpp
const std = @import("std");
const assert = std.debug.assert;
const zwin32 = @import("zwin32");
const w32 = zwin32.w32;
const dxgi = zwin32.dxgi;
const d3d12 = zwin32.d3d12;

const DDS_MAGIC: u32 = 0x20534444; // "DDS "

const DDS_FOURCC: u32 = 0x00000004; // DDPF_FOURCC
const DDS_RGB: u32 = 0x00000040; // DDPF_RGB
const DDS_RGBA: u32 = 0x00000041; // DDPF_RGB | DDPF_ALPHAPIXELS
const DDS_LUMINANCE: u32 = 0x00020000; // DDPF_LUMINANCE
const DDS_LUMINANCEA: u32 = 0x00020001; // DDPF_LUMINANCE | DDPF_ALPHAPIXELS
const DDS_ALPHA: u32 = 0x00000002; // DDPF_ALPHA
const DDS_PAL8: u32 = 0x00000020; // DDPF_PALETTEINDEXED8
const DDS_BUMPDUDV: u32 = 0x00080000; // DDPF_BUMPDUDV

inline fn makeFourCC(ch0: u8, ch1: u8, ch2: u8, ch3: u8) u32 {
    return (@intCast(u32, ch0)) | (@intCast(u32, ch1) << 8) | (@intCast(u32, ch2) << 16) | (@intCast(u32, ch3) << 24);
}

inline fn isBitMask(pixelFormat: DDS_PIXELFORMAT, r: u32, g: u32, b: u32, a: u32) bool {
    return (pixelFormat.dwRBitMask == r and pixelFormat.dwGBitMask == g and pixelFormat.dwBBitMask == b and pixelFormat.dwABitMask == a);
}

pub const DDS_PIXELFORMAT = extern struct {
    dwSize: u32,
    dwFlags: u32,
    dwFourCC: u32,
    dwRGBBitCount: u32,
    dwRBitMask: u32,
    dwGBitMask: u32,
    dwBBitMask: u32,
    dwABitMask: u32,
};

pub const DDS_HEADER = extern struct {
    dwSize: u32,
    dwFlags: u32,
    dwHeight: u32,
    dwWidth: u32,
    dwPitchOrLinearSize: u32,
    dwDepth: u32, // only if DDS_HEADER_FLAGS_VOLUME is set in dwFlags
    dwMipMapCount: u32,
    dwReserved1: [11]u32,
    ddspf: DDS_PIXELFORMAT,
    dwCaps: u32,
    dwCaps2: u32,
    dwCaps3: u32,
    dwCaps4: u32,
    dwReserved2: u32,
};

pub const DDS_HEADER_DXT10 = extern struct {
    dxgiFormat: dxgi.FORMAT,
    resourceDimension: u32,
    miscFlag: u32, // see DDS_RESOURCE_MISC_FLAG
    arraySize: u32,
    miscFlags2: u32, // see DDS_MISC_FLAGS2
};

pub const DdsImageInfo = struct {
    width: u32,
    height: u32,
    depth: u32,
    arraySize: u32,
    mip_map_count: u32,
    format: dxgi.FORMAT,
    resourceDimension: d3d12.RESOURCE_DIMENSION,
};

pub fn loadTextureFromFile(
    path: []const u8,
    arena: std.mem.Allocator,
    resources: *std.ArrayList(d3d12.SUBRESOURCE_DATA),
) !DdsImageInfo {
    var file = std.fs.cwd().openFile(path, .{}) catch |err| {
        std.log.warn("Unable to open file: {s}", .{@errorName(err)});
        return err;
    };
    defer file.close();

    const metadata = file.metadata() catch unreachable;

    const file_size = metadata.size();
    assert(file_size > @sizeOf(u32) + @sizeOf(DDS_HEADER));

    // Read all file
    var file_data = arena.alloc(u8, file_size) catch unreachable;
    var read_bytes = file.readAll(file_data) catch unreachable;
    assert(read_bytes == file_size);

    // Create a stream
    var stream = std.io.StreamSource{ .buffer = std.io.fixedBufferStream(file_data) };
    var reader = stream.reader();

    // Check DDS_MAGIC
    const magic = try reader.readIntNative(u32);
    assert(magic == DDS_MAGIC);

    // Extract DDS_HEADER
    const header = try reader.readStruct(DDS_HEADER);
    assert(header.dwSize == @intCast(u32, @sizeOf(DDS_HEADER)));
    assert(header.ddspf.dwSize == @intCast(u32, @sizeOf(DDS_PIXELFORMAT)));

    // Check for DX10 Extension
    var has_dx10_extension = false;
    var dx10: DDS_HEADER_DXT10 = undefined;
    if ((header.ddspf.dwFlags & DDS_FOURCC) == DDS_FOURCC and makeFourCC('D', 'X', '1', '0') == header.ddspf.dwFourCC) {
        assert(file_size > @sizeOf(u32) + @sizeOf(DDS_HEADER) + @sizeOf(DDS_HEADER_DXT10));

        has_dx10_extension = true;
        dx10 = try reader.readStruct(DDS_HEADER_DXT10);
    }

    var data_size = file_size - (@sizeOf(u32) + @sizeOf(DDS_HEADER));
    if (has_dx10_extension) {
        data_size -= @sizeOf(DDS_HEADER_DXT10);
    }

    var data = arena.alloc(u8, data_size) catch unreachable;
    try reader.readNoEof(data);

    var format = dxgi.FORMAT.UNKNOWN;
    var arraySize: u32 = 1;
    var depth: u32 = 1;
    var resourceDimension = d3d12.RESOURCE_DIMENSION.TEXTURE2D;

    // NOTE(gmodarelli): We're only supporting 2D Textures
    if (has_dx10_extension) {
        assert(dx10.arraySize != 0);

        arraySize = dx10.arraySize;
        depth = 1;
        format = getDXGIFormatFromDX10(dx10);
    } else {
        arraySize = 1;
        depth = 1;
        format = getDXGIFormat(header.ddspf);
    }

    // TODO(gmodarelli): Take into account arraySize and planes
    var total_width: u32 = 0;
    var total_height: u32 = 0;
    var total_depth: u32 = 0;
    var max_size: u32 = 0;

    var skip_mip: u32 = 0;
    var width: u32 = header.dwWidth;
    var height: u32 = header.dwHeight;
    var data_offset: u32 = 0;
    var mip_map_index: u32 = 0;
    while (mip_map_index < header.dwMipMapCount) : (mip_map_index += 1) {
        const surface_info = getSurfaceInfo(width, height, format);
        assert(surface_info.num_bytes < std.math.maxInt(u32));
        assert(surface_info.row_bytes < std.math.maxInt(u32));

        if (header.dwMipMapCount <= 1 or max_size == 0 or (width <= max_size and height <= max_size and depth <= max_size)) {
            if (total_width == 0) {
                total_width = width;
                total_height = height;
                total_depth = depth;
            }

            var resource = d3d12.SUBRESOURCE_DATA{
                .pData = @ptrCast([*]u8, data[data_offset..]),
                .RowPitch = @intCast(c_uint, surface_info.row_bytes),
                .SlicePitch = @intCast(c_uint, surface_info.num_bytes),
            };

            // TODO(gmodarelli): AdjustPlaneResources (only needed for a couple of formats)
            resources.append(resource) catch unreachable;
        } else if (mip_map_index == 0) {
            skip_mip += 1;
        }

        data_offset += @intCast(u32, surface_info.num_bytes) * depth;

        width = width >> 1;
        height = height >> 1;
        depth = depth >> 1;

        if (width == 0) {
            width = 1;
        }

        if (height == 0) {
            height = 1;
        }

        if (depth == 0) {
            depth = 1;
        }
    }

    return .{
        .width = header.dwWidth,
        .height = header.dwHeight,
        .depth = depth,
        .arraySize = arraySize,
        .mip_map_count = header.dwMipMapCount,
        .resourceDimension = resourceDimension,
        .format = format,
    };
}

fn getDXGIFormatFromDX10(header: DDS_HEADER_DXT10) dxgi.FORMAT {
    // TODO(gmodarelli): Perform format validation
    return header.dxgiFormat;
}

fn getDXGIFormat(pixelFormat: DDS_PIXELFORMAT) dxgi.FORMAT {
    if ((pixelFormat.dwFlags & DDS_RGB) == DDS_RGB) {
        // Note that sRGB formats are written using the "DX10" extended header
        if (pixelFormat.dwRGBBitCount == 32) {
            if (isBitMask(pixelFormat, 0x000000ff, 0x0000ff00, 0x00ff0000, 0xff000000)) {
                return .R8G8B8A8_UNORM;
            }

            if (isBitMask(pixelFormat, 0x00ff0000, 0x0000ff00, 0x000000ff, 0xff000000)) {
                return .B8G8R8A8_UNORM;
            }

            if (isBitMask(pixelFormat, 0x00ff0000, 0x0000ff00, 0x000000ff, 0)) {
                return .B8G8R8X8_UNORM;
            }

            // No DXGI format maps to (0x000000ff,0x0000ff00,0x00ff0000,0) aka D3DFMT_X8B8G8R8

            // Note that many common DDS reader/writers (including D3DX) swap the
            // the RED/BLUE masks for 10:10:10:2 formats. We assume
            // below that the 'backwards' header mask is being used since it is most
            // likely written by D3DX. The more robust solution is to use the 'DX10'
            // header extension and specify the DXGI_FORMAT_R10G10B10A2_UNORM format directly

            // For 'correct' writers, this should be (0x000003ff,0x000ffc00,0x3ff00000) for RGB data
            if (isBitMask(pixelFormat, 0x3ff00000, 0x000ffc00, 0x000003ff, 0xc0000000)) {
                return .R10G10B10A2_UNORM;
            }

            // No DXGI format maps to (0x000003ff,0x000ffc00,0x3ff00000,0xc0000000) aka D3DFMT_A2R10G10B10

            if (isBitMask(pixelFormat, 0x0000ffff, 0xffff0000, 0, 0)) {
                return .R16G16_UNORM;
            }

            if (isBitMask(pixelFormat, 0xffffffff, 0, 0, 0)) {
                // Only 32-bit color channel format in D3D9 was R32F
                return .R32_FLOAT; // D3DX writes this out as a FourCC of 114
            }
        } else if (pixelFormat.dwRGBBitCount == 16) {
            if (isBitMask(pixelFormat, 0x7c00, 0x03e0, 0x001f, 0x8000)) {
                return .B5G5R5A1_UNORM;
            }
            if (isBitMask(pixelFormat, 0xf800, 0x07e0, 0x001f, 0)) {
                return .B5G6R5_UNORM;
            }

            // No DXGI format maps to (0x7c00,0x03e0,0x001f,0) aka D3DFMT_X1R5G5B5

            if (isBitMask(pixelFormat, 0x0f00, 0x00f0, 0x000f, 0xf000)) {
                return .B4G4R4A4_UNORM;
            }

            // NVTT versions 1.x wrote this as RGB instead of LUMINANCE
            if (isBitMask(pixelFormat, 0x00ff, 0, 0, 0xff00)) {
                return .R8G8_UNORM;
            }
            if (isBitMask(pixelFormat, 0xffff, 0, 0, 0)) {
                return .R16_UNORM;
            }

            // No DXGI format maps to (0x0f00,0x00f0,0x000f,0) aka D3DFMT_X4R4G4B4

            // No 3:3:2:8 or paletted DXGI formats aka D3DFMT_A8R3G3B2, D3DFMT_A8P8, etc.
        } else if (pixelFormat.dwRGBBitCount == 8) {
            // NVTT versions 1.x wrote this as RGB instead of LUMINANCE
            if (isBitMask(pixelFormat, 0xff, 0, 0, 0)) {
                return .R8_UNORM;
            }

            // No 3:3:2 or paletted DXGI formats aka D3DFMT_R3G3B2, D3DFMT_P8
        }
    } else if ((pixelFormat.dwFlags & DDS_LUMINANCE) == DDS_LUMINANCE) {
        if (pixelFormat.dwRGBBitCount == 16) {
            if (isBitMask(pixelFormat, 0xffff, 0, 0, 0)) {
                return .R16_UNORM; // D3DX10/11 writes this out as DX10 extension
            }
            if (isBitMask(pixelFormat, 0x00ff, 0, 0, 0xff00)) {
                return .R8G8_UNORM; // D3DX10/11 writes this out as DX10 extension
            }
        } else if (pixelFormat.dwRGBBitCount == 8) {
            if (isBitMask(pixelFormat, 0xff, 0, 0, 0)) {
                return .R8_UNORM; // D3DX10/11 writes this out as DX10 extension
            }

            // No DXGI format maps to isBitMask(pixelFormat, 0x0f,0,0,0xf0) aka D3DFMT_A4L4

            if (isBitMask(pixelFormat, 0x00ff, 0, 0, 0xff00)) {
                return .R8G8_UNORM; // Some DDS writers assume the bitcount should be 8 instead of 16
            }
        }
    } else if ((pixelFormat.dwFlags & DDS_ALPHA) == DDS_ALPHA) {
        if (pixelFormat.dwRGBBitCount == 8) {
            return .A8_UNORM;
        }
    } else if ((pixelFormat.dwFlags & DDS_BUMPDUDV) == DDS_BUMPDUDV) {
        if (pixelFormat.dwRGBBitCount == 32) {
            if (isBitMask(pixelFormat, 0x000000ff, 0x0000ff00, 0x00ff0000, 0xff000000)) {
                return .R8G8B8A8_SNORM; // D3DX10/11 writes this out as DX10 extension
            }
            if (isBitMask(pixelFormat, 0x0000ffff, 0xffff0000, 0, 0)) {
                return .R16G16_SNORM; // D3DX10/11 writes this out as DX10 extension
            }
        } else if (pixelFormat.dwRGBBitCount == 16) {
            if (isBitMask(pixelFormat, 0x00ff, 0xff00, 0, 0)) {
                return .R8G8_SNORM; // D3DX10/11 writes this out as DX10 extension
            }
        }
    } else if ((pixelFormat.dwFlags & DDS_FOURCC) == DDS_FOURCC) {
        if (makeFourCC('D', 'X', 'T', '1') == pixelFormat.dwFourCC) {
            return .BC1_UNORM;
        }
        if (makeFourCC('D', 'X', 'T', '3') == pixelFormat.dwFourCC) {
            return .BC2_UNORM;
        }
        if (makeFourCC('D', 'X', 'T', '5') == pixelFormat.dwFourCC) {
            return .BC3_UNORM;
        }

        // While pre-multiplied alpha isn't directly supported by the DXGI formats,
        // they are basically the same as these BC formats so they can be mapped
        if (makeFourCC('D', 'X', 'T', '2') == pixelFormat.dwFourCC) {
            return .BC2_UNORM;
        }
        if (makeFourCC('D', 'X', 'T', '4') == pixelFormat.dwFourCC) {
            return .BC3_UNORM;
        }
        if (makeFourCC('A', 'T', 'I', '1') == pixelFormat.dwFourCC) {
            return .BC4_UNORM;
        }
        if (makeFourCC('B', 'C', '4', 'U') == pixelFormat.dwFourCC) {
            return .BC4_UNORM;
        }
        if (makeFourCC('B', 'C', '4', 'S') == pixelFormat.dwFourCC) {
            return .BC4_SNORM;
        }
        if (makeFourCC('A', 'T', 'I', '2') == pixelFormat.dwFourCC) {
            return .BC5_UNORM;
        }
        if (makeFourCC('B', 'C', '5', 'U') == pixelFormat.dwFourCC) {
            return .BC5_UNORM;
        }
        if (makeFourCC('B', 'C', '5', 'S') == pixelFormat.dwFourCC) {
            return .BC5_SNORM;
        }

        // BC6H and BC7 are written using the "DX10" extended header
        if (makeFourCC('R', 'G', 'B', 'G') == pixelFormat.dwFourCC) {
            return .R8G8_B8G8_UNORM;
        }
        if (makeFourCC('G', 'R', 'G', 'B') == pixelFormat.dwFourCC) {
            return .G8R8_G8B8_UNORM;
        }
        if (makeFourCC('Y', 'U', 'Y', '2') == pixelFormat.dwFourCC) {
            return .YUY2;
        }

        // Check for D3DFORMAT enums being set here
        if (pixelFormat.dwFourCC == 36) {
            return .R16G16B16A16_UNORM;
        } else if (pixelFormat.dwFourCC == 110) {
            return .R16G16B16A16_SNORM;
        } else if (pixelFormat.dwFourCC == 111) {
            return .R16_FLOAT;
        } else if (pixelFormat.dwFourCC == 112) {
            return .R16G16_FLOAT;
        } else if (pixelFormat.dwFourCC == 113) {
            return .R16G16B16A16_FLOAT;
        } else if (pixelFormat.dwFourCC == 114) {
            return .R32_FLOAT;
        } else if (pixelFormat.dwFourCC == 115) {
            return .R32G32_FLOAT;
        } else if (pixelFormat.dwFourCC == 116) {
            return .R32G32B32A32_FLOAT;
        }
    }

    return .UNKNOWN;
}

const FormatData = struct {
    bc: bool = false,
    @"packed": bool = false,
    planar: bool = false,
    bpe: u32 = 0,
};

fn getSurfaceInfo(
    width: u32,
    height: u32,
    format: dxgi.FORMAT,
) struct { num_bytes: u64, row_bytes: u64, num_rows: u64 } {
    var num_bytes: u64 = 0;
    var row_bytes: u64 = 0;
    var num_rows: u64 = 0;

    var format_data = switch (format) {
        .BC1_TYPELESS, .BC1_UNORM, .BC1_UNORM_SRGB, .BC4_TYPELESS, .BC4_UNORM, .BC4_SNORM => FormatData{
            .bc = true,
            .@"packed" = false,
            .planar = false,
            .bpe = 8,
        },

        .BC2_TYPELESS, .BC2_UNORM, .BC2_UNORM_SRGB, .BC3_TYPELESS, .BC3_UNORM, .BC3_UNORM_SRGB, .BC5_TYPELESS, .BC5_UNORM, .BC5_SNORM, .BC6H_TYPELESS, .BC6H_UF16, .BC6H_SF16, .BC7_TYPELESS, .BC7_UNORM, .BC7_UNORM_SRGB => FormatData{
            .bc = true,
            .@"packed" = false,
            .planar = false,
            .bpe = 16,
        },

        .R8G8_B8G8_UNORM, .G8R8_G8B8_UNORM, .YUY2 => FormatData{
            .bc = false,
            .@"packed" = true,
            .planar = false,
            .bpe = 4,
        },

        .Y210, .Y216 => FormatData{
            .bc = false,
            .@"packed" = true,
            .planar = false,
            .bpe = 8,
        },

        .NV12, .@"420_OPAQUE" => blk: {
            // Requires a height alignment of 2.
            // return E_INVALIDARG;
            assert(height % 2 == 0);
            break :blk FormatData{
                .bc = false,
                .@"packed" = false,
                .planar = true,
                .bpe = 2,
            };
        },

        .P208 => FormatData{
            .bc = false,
            .@"packed" = false,
            .planar = true,
            .bpe = 2,
        },

        .P010, .P016 => blk: {
            // Requires a height alignment of 2.
            // return E_INVALIDARG;
            assert(height % 2 == 0);
            break :blk FormatData{
                .bc = false,
                .@"packed" = false,
                .planar = true,
                .bpe = 4,
            };
        },

        else => FormatData{
            .bc = false,
            .@"packed" = false,
            .planar = false,
            .bpe = 0,
        },
    };

    if (format_data.bc) {
        var num_blocks_wide: u64 = 0;
        if (width > 0) {
            num_blocks_wide = std.math.max(1, @divTrunc(@intCast(u64, width) + 3, 4));
        }
        var num_blocks_high: u64 = 0;
        if (height > 0) {
            num_blocks_high = std.math.max(1, @divTrunc(@intCast(u64, height) + 3, 4));
        }
        row_bytes = num_blocks_wide * format_data.bpe;
        num_rows = num_blocks_high;
        num_bytes = row_bytes * num_blocks_high;
    } else if (format_data.@"packed") {
        row_bytes = ((@intCast(u64, width) + 1) >> 1) * format_data.bpe;
        num_rows = @intCast(u64, height);
        num_bytes = row_bytes * height;
    } else if (format == .NV11) {
        row_bytes = ((@intCast(u64, width) + 3) >> 2) * 4;
        num_rows = @intCast(u64, height) * 2; // Direct3D makes this simplifying assumption, although it is larger than the 4:1:1 data
        num_bytes = row_bytes * num_rows;
    } else if (format_data.planar) {
        row_bytes = ((@intCast(u64, width) + 1) >> 1) * format_data.bpe;
        num_bytes = (row_bytes * @intCast(u64, height)) + ((row_bytes * @intCast(u64, height) + 1) >> 1);
        num_rows = height + ((@intCast(u64, height) + 1) >> 1);
    } else {
        const bpp = bitsPerPixel(format);
        assert(bpp > 0);

        row_bytes = @divFloor(@intCast(u64, width) * bpp + 7, 8); // round up to nearest byte
        num_rows = @intCast(u64, height);
        num_bytes = row_bytes * height;
    }

    return .{
        .num_bytes = num_bytes,
        .row_bytes = row_bytes,
        .num_rows = num_rows,
    };
}

inline fn bitsPerPixel(format: dxgi.FORMAT) usize {
    return switch (format) {
        .R32G32B32A32_TYPELESS, .R32G32B32A32_FLOAT, .R32G32B32A32_UINT, .R32G32B32A32_SINT => 128,

        .R32G32B32_TYPELESS, .R32G32B32_FLOAT, .R32G32B32_UINT, .R32G32B32_SINT => 96,

        .R16G16B16A16_TYPELESS, .R16G16B16A16_FLOAT, .R16G16B16A16_UNORM, .R16G16B16A16_UINT, .R16G16B16A16_SNORM, .R16G16B16A16_SINT, .R32G32_TYPELESS, .R32G32_FLOAT, .R32G32_UINT, .R32G32_SINT, .R32G8X24_TYPELESS, .D32_FLOAT_S8X24_UINT, .R32_FLOAT_X8X24_TYPELESS, .X32_TYPELESS_G8X24_UINT, .Y416, .Y210, .Y216 => 64,

        .R10G10B10A2_TYPELESS, .R10G10B10A2_UNORM, .R10G10B10A2_UINT, .R11G11B10_FLOAT, .R8G8B8A8_TYPELESS, .R8G8B8A8_UNORM, .R8G8B8A8_UNORM_SRGB, .R8G8B8A8_UINT, .R8G8B8A8_SNORM, .R8G8B8A8_SINT, .R16G16_TYPELESS, .R16G16_FLOAT, .R16G16_UNORM, .R16G16_UINT, .R16G16_SNORM, .R16G16_SINT, .R32_TYPELESS, .D32_FLOAT, .R32_FLOAT, .R32_UINT, .R32_SINT, .R24G8_TYPELESS, .D24_UNORM_S8_UINT, .R24_UNORM_X8_TYPELESS, .X24_TYPELESS_G8_UINT, .R9G9B9E5_SHAREDEXP, .R8G8_B8G8_UNORM, .G8R8_G8B8_UNORM, .B8G8R8A8_UNORM, .B8G8R8X8_UNORM, .R10G10B10_XR_BIAS_A2_UNORM, .B8G8R8A8_TYPELESS, .B8G8R8A8_UNORM_SRGB, .B8G8R8X8_TYPELESS, .B8G8R8X8_UNORM_SRGB, .AYUV, .Y410, .YUY2 => 32,

        .P010, .P016, .V408 => 24,

        .R8G8_TYPELESS, .R8G8_UNORM, .R8G8_UINT, .R8G8_SNORM, .R8G8_SINT, .R16_TYPELESS, .R16_FLOAT, .D16_UNORM, .R16_UNORM, .R16_UINT, .R16_SNORM, .R16_SINT, .B5G6R5_UNORM, .B5G5R5A1_UNORM, .A8P8, .B4G4R4A4_UNORM, .P208, .V208 => 16,

        .NV12, .@"420_OPAQUE", .NV11 => 12,

        .R8_TYPELESS, .R8_UNORM, .R8_UINT, .R8_SNORM, .R8_SINT, .A8_UNORM, .BC2_TYPELESS, .BC2_UNORM, .BC2_UNORM_SRGB, .BC3_TYPELESS, .BC3_UNORM, .BC3_UNORM_SRGB, .BC5_TYPELESS, .BC5_UNORM, .BC5_SNORM, .BC6H_TYPELESS, .BC6H_UF16, .BC6H_SF16, .BC7_TYPELESS, .BC7_UNORM, .BC7_UNORM_SRGB, .AI44, .IA44, .P8 => 8,

        .R1_UNORM => 1,

        .BC1_TYPELESS, .BC1_UNORM, .BC1_UNORM_SRGB, .BC4_TYPELESS, .BC4_UNORM, .BC4_SNORM => 4,

        else => 0,
    };
}
