#include "d3d11.h"

#include <assert.h>

void Texture2D::update_content(ID3D11DeviceContext *device_context, unsigned char *data)
{
    D3D11_BOX box;
    box.front = 0;
    box.back = 1;
    box.left = 0;
    box.top = 0;
    box.right = width;
    box.bottom = height;
    device_context->UpdateSubresource((ID3D11Resource *)texture, 0, &box, data, width * channel_count, 0);
}

bool D3D11::create_device(HWND hwnd)
{
    // Setup swap chain
    DXGI_SWAP_CHAIN_DESC sd;
    ZeroMemory(&sd, sizeof(sd));
    sd.BufferCount = 2;
    sd.BufferDesc.Width = 0;
    sd.BufferDesc.Height = 0;
    sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.BufferDesc.RefreshRate.Numerator = 60;
    sd.BufferDesc.RefreshRate.Denominator = 1;
    sd.Flags = DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.OutputWindow = hwnd;
    sd.SampleDesc.Count = 1;
    sd.SampleDesc.Quality = 0;
    sd.Windowed = TRUE;
    sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

    UINT create_device_flags = 0;
#if defined(_DEBUG)
    create_device_flags |= D3D11_CREATE_DEVICE_DEBUG;
#endif
    D3D_FEATURE_LEVEL feature_level;
    const D3D_FEATURE_LEVEL feature_level_array[2] = {
        D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_0,
    };
    HRESULT res = D3D11CreateDeviceAndSwapChain(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, create_device_flags, feature_level_array, 2, D3D11_SDK_VERSION, &sd, &swapchain, &device, &feature_level, &device_context);
    if (res == DXGI_ERROR_UNSUPPORTED) // Try high-performance WARP software driver if hardware is not available.
        res = D3D11CreateDeviceAndSwapChain(nullptr, D3D_DRIVER_TYPE_WARP, nullptr, create_device_flags, feature_level_array, 2, D3D11_SDK_VERSION, &sd, &swapchain, &device, &feature_level, &device_context);
    if (res != S_OK)
        return false;

    create_render_target();

    compile_compute_shader(L"shaders/Remap.hlsl", "CSRemap", &remap_shader);
    assert(remap_shader.compute_shader);
    assert(remap_shader.reflection);

    return true;
}

void D3D11::cleanup_device()
{
    cleanup_render_target();
    SAFE_RELEASE(remap_shader.compute_shader);
    SAFE_RELEASE(remap_shader.reflection);
    SAFE_RELEASE(swapchain);
    SAFE_RELEASE(device_context);
    SAFE_RELEASE(device);
}

void D3D11::create_render_target()
{
    ID3D11Texture2D *back_buffer;
    swapchain->GetBuffer(0, IID_PPV_ARGS(&back_buffer));
    device->CreateRenderTargetView(back_buffer, nullptr, &main_render_target_view);
    SAFE_RELEASE(back_buffer);
}

void D3D11::cleanup_render_target()
{
    SAFE_RELEASE(main_render_target_view);
}

void D3D11::resize_render_target(int32_t width, int32_t height)
{
    if (width != 0 && height != 0 && (width != render_target_width || height != render_target_height))
    {
        render_target_width = width;
        render_target_height = height;

        cleanup_render_target();
        swapchain->ResizeBuffers(0, render_target_width, render_target_height, DXGI_FORMAT_UNKNOWN, 0);
        create_render_target();
    }
}

void D3D11::bind_render_target(const float clear_color[4])
{
    device_context->OMSetRenderTargets(1, &main_render_target_view, nullptr);
    device_context->ClearRenderTargetView(main_render_target_view, clear_color);
}

void D3D11::create_texture(int32_t width, int32_t height, Texture2D *out_texture)
{
    D3D11_TEXTURE2D_DESC desc;
    memset(&desc, 0, sizeof(D3D11_TEXTURE2D_DESC));
    desc.Width = width;
    desc.Height = height;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    desc.CPUAccessFlags = 0;
    device->CreateTexture2D(&desc, nullptr, &out_texture->texture);
    assert(out_texture->texture);

    D3D11_SHADER_RESOURCE_VIEW_DESC srv_desc;
    memset(&srv_desc, 0, sizeof(srv_desc));
    srv_desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    srv_desc.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D;
    srv_desc.Texture2D.MipLevels = desc.MipLevels;
    srv_desc.Texture2D.MostDetailedMip = 0;
    device->CreateShaderResourceView(out_texture->texture, &srv_desc, &out_texture->srv);

    out_texture->width = width;
    out_texture->height = height;
}

HRESULT D3D11::compile_compute_shader(LPCWSTR path, const char *entry, ComputeShader *out_compute_shader)
{
    assert(path);
    assert(entry);
    assert(device);

    UINT flags = D3DCOMPILE_ENABLE_STRICTNESS;
#if defined(_DEBUG)
    flags |= D3DCOMPILE_DEBUG;
#endif

    const char *profile = "cs_5_0";

    ID3DBlob *shader_blob = nullptr;
    ID3DBlob *error_blob = nullptr;
    HRESULT hr = D3DCompileFromFile(path, nullptr, D3D_COMPILE_STANDARD_FILE_INCLUDE, entry, profile, flags, 0, &shader_blob, &error_blob);

    if (FAILED(hr))
    {
        if (error_blob)
        {
            OutputDebugStringA((char *)error_blob->GetBufferPointer());
            error_blob->Release();
        }

        SAFE_RELEASE(shader_blob);
        return hr;
    }

    hr = device->CreateComputeShader(shader_blob->GetBufferPointer(), shader_blob->GetBufferSize(), nullptr, &out_compute_shader->compute_shader);

#if defined(_DEBUG)
    if (SUCCEEDED(hr))
    {
        out_compute_shader->compute_shader->SetPrivateData(WKPDID_D3DDebugObjectName, lstrlenA(entry), entry);
    }
#endif

    D3DReflect(shader_blob->GetBufferPointer(), shader_blob->GetBufferSize(), IID_ID3D11ShaderReflection, (void **)&out_compute_shader->reflection);
    assert(out_compute_shader->reflection);

    out_compute_shader->reflection->GetThreadGroupSize(&out_compute_shader->thread_group_size[0], &out_compute_shader->thread_group_size[1], &out_compute_shader->thread_group_size[2]);

    return hr;
}

HRESULT D3D11::create_constant_buffer(uint32_t buffer_size, void *data, ID3D11Buffer **out_buffer)
{
    *out_buffer = nullptr;

    D3D11_BUFFER_DESC desc = {};
    desc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    desc.ByteWidth = buffer_size;

    D3D11_SUBRESOURCE_DATA subresource_data;
    subresource_data.pSysMem = data;
    return device->CreateBuffer(&desc, &subresource_data, out_buffer);
}

HRESULT D3D11::create_structured_buffer(uint32_t element_size, uint32_t element_count, void *initial_data, ID3D11Buffer **out_buffer)
{
    *out_buffer = nullptr;

    D3D11_BUFFER_DESC desc = {};
    desc.BindFlags = D3D11_BIND_UNORDERED_ACCESS | D3D11_BIND_SHADER_RESOURCE;
    desc.ByteWidth = element_size * element_count;
    desc.MiscFlags = D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;
    desc.StructureByteStride = element_size;

    if (initial_data)
    {
        D3D11_SUBRESOURCE_DATA subresource_data;
        subresource_data.pSysMem = initial_data;
        return device->CreateBuffer(&desc, &subresource_data, out_buffer);
    }
    else
    {
        return device->CreateBuffer(&desc, nullptr, out_buffer);
    }
}

HRESULT D3D11::create_readback_buffer(uint32_t element_size, uint32_t element_count, ID3D11Buffer **out_buffer)
{
    *out_buffer = nullptr;

    D3D11_BUFFER_DESC desc = {};
    desc.ByteWidth = element_size * element_count;
    desc.MiscFlags = D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;
    desc.StructureByteStride = element_size;
    desc.Usage = D3D11_USAGE_STAGING;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;

    return device->CreateBuffer(&desc, nullptr, out_buffer);
}

HRESULT D3D11::create_buffer_srv(ID3D11Buffer *buffer, ID3D11ShaderResourceView **out_srv)
{
    D3D11_BUFFER_DESC buffer_desc = {};
    buffer->GetDesc(&buffer_desc);

    D3D11_SHADER_RESOURCE_VIEW_DESC desc = {};
    desc.ViewDimension = D3D11_SRV_DIMENSION_BUFFEREX;
    desc.BufferEx.FirstElement = 0;

    if (buffer_desc.MiscFlags & D3D11_RESOURCE_MISC_BUFFER_ALLOW_RAW_VIEWS)
    {
        // This is a Raw Buffer
        desc.Format = DXGI_FORMAT_R32_TYPELESS;
        desc.BufferEx.Flags = D3D11_BUFFEREX_SRV_FLAG_RAW;
        desc.BufferEx.NumElements = buffer_desc.ByteWidth / 4;
    }
    else if (buffer_desc.MiscFlags & D3D11_RESOURCE_MISC_BUFFER_STRUCTURED)
    {
        // This is a Structured Buffer
        desc.Format = DXGI_FORMAT_UNKNOWN;
        desc.BufferEx.NumElements = buffer_desc.ByteWidth / buffer_desc.StructureByteStride;
    }
    else
    {
        return E_INVALIDARG;
    }

    return device->CreateShaderResourceView(buffer, &desc, out_srv);
}

HRESULT D3D11::create_buffer_uav(ID3D11Buffer *buffer, ID3D11UnorderedAccessView **out_uav)
{
    D3D11_BUFFER_DESC buffer_desc = {};
    buffer->GetDesc(&buffer_desc);

    D3D11_UNORDERED_ACCESS_VIEW_DESC desc = {};
    desc.ViewDimension = D3D11_UAV_DIMENSION_BUFFER;
    desc.Buffer.FirstElement = 0;

    if (buffer_desc.MiscFlags & D3D11_RESOURCE_MISC_BUFFER_ALLOW_RAW_VIEWS)
    {
        // This is a Raw Buffer
        desc.Format = DXGI_FORMAT_R32_TYPELESS; // Format must be DXGI_FORMAT_R32_TYPELESS, when creating Raw Unordered Access View
        desc.Buffer.Flags = D3D11_BUFFER_UAV_FLAG_RAW;
        desc.Buffer.NumElements = buffer_desc.ByteWidth / 4;
    }
    else if (buffer_desc.MiscFlags & D3D11_RESOURCE_MISC_BUFFER_STRUCTURED)
    {
        // This is a Structured Buffer
        desc.Format = DXGI_FORMAT_UNKNOWN; // Format must be must be DXGI_FORMAT_UNKNOWN, when creating a View of a Structured Buffer
        desc.Buffer.NumElements = buffer_desc.ByteWidth / buffer_desc.StructureByteStride;
    }
    else
    {
        return E_INVALIDARG;
    }

    return device->CreateUnorderedAccessView(buffer, &desc, out_uav);
}

void D3D11::dispatch_remap_float_shader(RemapSettings remap_settings, float *input_data, float *output_data)
{
    assert(device);
    assert(device_context);
    assert(remap_shader.compute_shader);

    assert(input_data);
    assert(output_data);

    ID3D11Buffer *remap_settings_buffer = nullptr;
    ID3D11Buffer *input_buffer = nullptr;
    ID3D11Buffer *output_buffer = nullptr;
    ID3D11Buffer *readback_buffer = nullptr;

    create_constant_buffer(sizeof(RemapSettings), &remap_settings, &remap_settings_buffer);
    create_structured_buffer(sizeof(float), remap_settings.width * remap_settings.height, (void *)input_data, &input_buffer);
    create_structured_buffer(sizeof(float), remap_settings.width * remap_settings.height, nullptr, &output_buffer);
    create_readback_buffer(sizeof(float), remap_settings.width * remap_settings.height, &readback_buffer);

    assert(remap_settings_buffer);
    assert(input_buffer);
    assert(output_buffer);
    assert(readback_buffer);

#if defined(_DEBUG)
    remap_settings_buffer->SetPrivateData(WKPDID_D3DDebugObjectName, sizeof("Remap Settings Buffer") - 1, "Remap Settings Buffer");
    input_buffer->SetPrivateData(WKPDID_D3DDebugObjectName, sizeof("Input Buffer") - 1, "Input Buffer");
    output_buffer->SetPrivateData(WKPDID_D3DDebugObjectName, sizeof("Output Buffer") - 1, "Output Buffer");
    readback_buffer->SetPrivateData(WKPDID_D3DDebugObjectName, sizeof("Readback Buffer") - 1, "Readback Buffer");
#endif

    ID3D11ShaderResourceView *input_buffer_srv = nullptr;
    ID3D11UnorderedAccessView *output_buffer_uav = nullptr;
    create_buffer_srv(input_buffer, &input_buffer_srv);
    create_buffer_uav(output_buffer, &output_buffer_uav);

    assert(input_buffer_srv);
    assert(output_buffer_uav);

    // Run the compute shader
    {
        device_context->CSSetShader(remap_shader.compute_shader, nullptr, 0);
        device_context->CSSetConstantBuffers(0, 1, &remap_settings_buffer);
        device_context->CSSetShaderResources(0, 1, &input_buffer_srv);
        device_context->CSSetUnorderedAccessViews(0, 1, &output_buffer_uav, nullptr);
        device_context->Dispatch(remap_settings.width / remap_shader.thread_group_size[0] + 1, remap_settings.height / remap_shader.thread_group_size[1] + 1, remap_shader.thread_group_size[2]);
    }

    // Cleanup context
    {
        device_context->CSSetShader(nullptr, nullptr, 0);
        ID3D11UnorderedAccessView *ppUAViewnullptr[1] = {nullptr};
        device_context->CSSetUnorderedAccessViews(0, 1, ppUAViewnullptr, nullptr);

        ID3D11ShaderResourceView *ppSRVnullptr[2] = {nullptr, nullptr};
        device_context->CSSetShaderResources(0, 2, ppSRVnullptr);

        ID3D11Buffer *ppCBnullptr[1] = {nullptr};
        device_context->CSSetConstantBuffers(0, 1, ppCBnullptr);
    }

    // Read back data
    {
        device_context->CopyResource(readback_buffer, output_buffer);

        D3D11_MAPPED_SUBRESOURCE subresource = {};
        subresource.RowPitch = remap_settings.width * sizeof(float);
        subresource.DepthPitch = remap_settings.height * sizeof(float);
        device_context->Map(readback_buffer, 0, D3D11_MAP_READ, 0, &subresource);

        if (subresource.pData)
        {
            memcpy((void *)output_data, subresource.pData, remap_settings.width * remap_settings.height * sizeof(float));
        }

        device_context->Unmap(readback_buffer, 0);
    }

    // Cleanup GPU Resources
    {
        SAFE_RELEASE(input_buffer_srv);
        SAFE_RELEASE(output_buffer_uav);
        SAFE_RELEASE(input_buffer);
        SAFE_RELEASE(output_buffer);
        SAFE_RELEASE(remap_settings_buffer);
        SAFE_RELEASE(readback_buffer);
    }
}