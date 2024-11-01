#include "d3d11.h"

#include <assert.h>
#include <math.h>

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
    HRESULT res = D3D11CreateDeviceAndSwapChain(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, create_device_flags, feature_level_array, 2, D3D11_SDK_VERSION, &sd, &m_swapchain, &m_device, &feature_level, &m_device_context);
    if (res == DXGI_ERROR_UNSUPPORTED) // Try high-performance WARP software driver if hardware is not available.
        res = D3D11CreateDeviceAndSwapChain(nullptr, D3D_DRIVER_TYPE_WARP, nullptr, create_device_flags, feature_level_array, 2, D3D11_SDK_VERSION, &sd, &m_swapchain, &m_device, &feature_level, &m_device_context);
    if (res != S_OK)
        return false;

    create_render_target();

    m_compute_shader_count = 0;
    compile_compute_shader(L"shaders/remap.hlsl", "CSRemap", nullptr, &m_compute_shaders[m_compute_shader_count]);
    m_compute_shader_count++;
    compile_compute_shader(L"shaders/square.hlsl", "CSSquare", nullptr, &m_compute_shaders[m_compute_shader_count]);
    m_compute_shader_count++;
    compile_compute_shader(L"shaders/gradient.hlsl", "CSGradient", nullptr, &m_compute_shaders[m_compute_shader_count]);
    m_compute_shader_count++;

    // Parallel Reduction Min
    {
        D3D_SHADER_MACRO macro[] = {"REDUCTION_OPERATOR", "1", NULL, NULL};
        compile_compute_shader(L"shaders/reduce_to_1d.hlsl", "CSReduceTo1D", macro, &m_compute_shaders[m_compute_shader_count]);
        m_compute_shader_count++;
        compile_compute_shader(L"shaders/reduce_to_single.hlsl", "CSReduceToSingle", macro, &m_compute_shaders[m_compute_shader_count]);
        m_compute_shader_count++;
    }

    // Parallel Reduction Max
    {
        D3D_SHADER_MACRO macro[] = {"REDUCTION_OPERATOR", "2", NULL, NULL};
        compile_compute_shader(L"shaders/reduce_to_1d.hlsl", "CSReduceTo1D", macro, &m_compute_shaders[m_compute_shader_count]);
        m_compute_shader_count++;
        compile_compute_shader(L"shaders/reduce_to_single.hlsl", "CSReduceToSingle", macro, &m_compute_shaders[m_compute_shader_count]);
        m_compute_shader_count++;
    }

    // Parallel Reduction Sum
    {
        D3D_SHADER_MACRO macro[] = {"REDUCTION_OPERATOR", "3", NULL, NULL};
        compile_compute_shader(L"shaders/reduce_to_1d.hlsl", "CSReduceTo1D", macro, &m_compute_shaders[m_compute_shader_count]);
        m_compute_shader_count++;
        compile_compute_shader(L"shaders/reduce_to_single.hlsl", "CSReduceToSingle", macro, &m_compute_shaders[m_compute_shader_count]);
        m_compute_shader_count++;
    }

    return true;
}

void D3D11::cleanup_device()
{
    cleanup_render_target();
    for (unsigned i_cs = 0; i_cs < m_compute_shader_count; i_cs++)
    {
        SAFE_RELEASE(m_compute_shaders[i_cs].compute_shader);
        SAFE_RELEASE(m_compute_shaders[i_cs].reflection);
    }
    SAFE_RELEASE(m_swapchain);
    SAFE_RELEASE(m_device_context);
    SAFE_RELEASE(m_device);
}

void D3D11::create_render_target()
{
    ID3D11Texture2D *back_buffer;
    m_swapchain->GetBuffer(0, IID_PPV_ARGS(&back_buffer));
    m_device->CreateRenderTargetView(back_buffer, nullptr, &m_main_render_target_view);
    SAFE_RELEASE(back_buffer);
}

void D3D11::cleanup_render_target()
{
    SAFE_RELEASE(m_main_render_target_view);
}

void D3D11::resize_render_target(int32_t width, int32_t height)
{
    if (width != 0 && height != 0 && (width != m_render_target_width || height != m_render_target_height))
    {
        m_render_target_width = width;
        m_render_target_height = height;

        cleanup_render_target();
        m_swapchain->ResizeBuffers(0, m_render_target_width, m_render_target_height, DXGI_FORMAT_UNKNOWN, 0);
        create_render_target();
    }
}

void D3D11::bind_render_target(const float clear_color[4])
{
    m_device_context->OMSetRenderTargets(1, &m_main_render_target_view, nullptr);
    m_device_context->ClearRenderTargetView(m_main_render_target_view, clear_color);
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
    m_device->CreateTexture2D(&desc, nullptr, &out_texture->texture);
    assert(out_texture->texture);

    D3D11_SHADER_RESOURCE_VIEW_DESC srv_desc;
    memset(&srv_desc, 0, sizeof(srv_desc));
    srv_desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    srv_desc.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D;
    srv_desc.Texture2D.MipLevels = desc.MipLevels;
    srv_desc.Texture2D.MostDetailedMip = 0;
    m_device->CreateShaderResourceView(out_texture->texture, &srv_desc, &out_texture->srv);

    out_texture->width = width;
    out_texture->height = height;
}

HRESULT D3D11::compile_compute_shader(LPCWSTR path, const char *entry, const D3D_SHADER_MACRO *defines, ComputeShader *out_compute_shader)
{
    assert(path);
    assert(entry);
    assert(m_device);

    UINT flags = D3DCOMPILE_ENABLE_STRICTNESS;
#if defined(_DEBUG)
    flags |= D3DCOMPILE_DEBUG;
#endif

    const char *profile = "cs_5_0";

    ID3DBlob *shader_blob = nullptr;
    ID3DBlob *error_blob = nullptr;
    HRESULT hr = D3DCompileFromFile(path, defines, D3D_COMPILE_STANDARD_FILE_INCLUDE, entry, profile, flags, 0, &shader_blob, &error_blob);

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

    hr = m_device->CreateComputeShader(shader_blob->GetBufferPointer(), shader_blob->GetBufferSize(), nullptr, &out_compute_shader->compute_shader);

#if defined(_DEBUG)
    if (SUCCEEDED(hr))
    {
        out_compute_shader->compute_shader->SetPrivateData(WKPDID_D3DDebugObjectName, lstrlenA(entry), entry);
    }
#endif

    D3DReflect(shader_blob->GetBufferPointer(), shader_blob->GetBufferSize(), IID_ID3D11ShaderReflection, (void **)&out_compute_shader->reflection);
    assert(out_compute_shader->reflection);

    out_compute_shader->reflection->GetThreadGroupSize(&out_compute_shader->thread_group_size[0], &out_compute_shader->thread_group_size[1], &out_compute_shader->thread_group_size[2]);
    out_compute_shader->name = entry;

    return hr;
}

HRESULT D3D11::create_buffer(D3D11_BUFFER_DESC desc, void *initial_data, const char *debug_name, ID3D11Buffer **out_buffer)
{
    *out_buffer = nullptr;

    HRESULT hr;

    if (initial_data)
    {
        D3D11_SUBRESOURCE_DATA subresource_data;
        subresource_data.pSysMem = initial_data;
        hr = m_device->CreateBuffer(&desc, &subresource_data, out_buffer);
    }
    else
    {
        hr = m_device->CreateBuffer(&desc, nullptr, out_buffer);
    }

#if defined(_DEBUG)
    if (hr == S_OK)
    {
        (*out_buffer)->SetPrivateData(WKPDID_D3DDebugObjectName, sizeof(debug_name) - 1, debug_name);
    }
#endif

    return hr;
}

HRESULT D3D11::create_constant_buffer(uint32_t buffer_size, void *initial_data, const char *debug_name, ID3D11Buffer **out_buffer)
{
    D3D11_BUFFER_DESC desc = {};
    desc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    desc.ByteWidth = buffer_size;
    return create_buffer(desc, initial_data, debug_name, out_buffer);
}

HRESULT D3D11::create_structured_buffer(uint32_t element_size, uint32_t element_count, void *initial_data, const char *debug_name, ID3D11Buffer **out_buffer)
{
    D3D11_BUFFER_DESC desc = {};
    desc.BindFlags = D3D11_BIND_UNORDERED_ACCESS | D3D11_BIND_SHADER_RESOURCE;
    desc.ByteWidth = element_size * element_count;
    desc.MiscFlags = D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;
    desc.StructureByteStride = element_size;
    return create_buffer(desc, initial_data, debug_name, out_buffer);
}

HRESULT D3D11::create_readback_buffer(uint32_t element_size, uint32_t element_count, const char *debug_name, ID3D11Buffer **out_buffer)
{
    D3D11_BUFFER_DESC desc = {};
    desc.ByteWidth = element_size * element_count;
    desc.MiscFlags = D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;
    desc.StructureByteStride = element_size;
    desc.Usage = D3D11_USAGE_STAGING;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    return create_buffer(desc, nullptr, debug_name, out_buffer);
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

    return m_device->CreateShaderResourceView(buffer, &desc, out_srv);
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

    return m_device->CreateUnorderedAccessView(buffer, &desc, out_uav);
}

void D3D11::dispatch_float_shader(ComputeInfo job)
{
    OutputDebugStringA("dispatch_float_shader START\n");
    void *shader_settings = job.shader_settings;
    size_t shader_settings_size = job.shader_settings_size;
    int32_t buffer_width = job.buffer_width;
    int32_t buffer_height = job.buffer_height;
    float *input_data = &job.input_datas[0];
    float *output_data = &job.output_datas[0];

    ComputeShader &shader = m_compute_shaders[job.compute_id];
    assert(m_device);
    assert(m_device_context);
    assert(shader.compute_shader);

    assert(input_data);
    assert(output_data);

    ID3D11Buffer *shader_settings_buffer = nullptr;
    ID3D11Buffer *input_buffer = nullptr;
    ID3D11Buffer *output_buffer = nullptr;
    ID3D11Buffer *readback_buffer = nullptr;

    create_constant_buffer(shader_settings_size, shader_settings, "User CB", &shader_settings_buffer);
    create_structured_buffer(sizeof(float), buffer_width * buffer_height, (void *)input_data, "Input Buffer", &input_buffer);
    create_structured_buffer(sizeof(float), buffer_width * buffer_height, nullptr, "Output Buffer", &output_buffer);
    create_readback_buffer(sizeof(float), buffer_width * buffer_height, "Readback Buffer", &readback_buffer);

    assert(shader_settings_buffer);
    assert(input_buffer);
    assert(output_buffer);
    assert(readback_buffer);

    ID3D11ShaderResourceView *input_buffer_srv = nullptr;
    ID3D11UnorderedAccessView *output_buffer_uav = nullptr;
    create_buffer_srv(input_buffer, &input_buffer_srv);
    create_buffer_uav(output_buffer, &output_buffer_uav);

    assert(input_buffer_srv);
    assert(output_buffer_uav);

    // Run the compute shader
    {
        m_device_context->CSSetShader(shader.compute_shader, nullptr, 0);
        m_device_context->CSSetConstantBuffers(0, 1, &shader_settings_buffer);
        m_device_context->CSSetShaderResources(0, 1, &input_buffer_srv);
        m_device_context->CSSetUnorderedAccessViews(0, 1, &output_buffer_uav, nullptr);
        m_device_context->Dispatch(buffer_width / shader.thread_group_size[0] + 1, buffer_height / shader.thread_group_size[1] + 1, shader.thread_group_size[2]);
    }

    // Cleanup context
    {
        m_device_context->CSSetShader(nullptr, nullptr, 0);
        ID3D11UnorderedAccessView *ppUAViewnullptr[1] = {nullptr};
        m_device_context->CSSetUnorderedAccessViews(0, 1, ppUAViewnullptr, nullptr);

        ID3D11ShaderResourceView *ppSRVnullptr[2] = {nullptr, nullptr};
        m_device_context->CSSetShaderResources(0, 2, ppSRVnullptr);

        ID3D11Buffer *ppCBnullptr[1] = {nullptr};
        m_device_context->CSSetConstantBuffers(0, 1, ppCBnullptr);
    }

    // Read back data
    {
        m_device_context->CopyResource(readback_buffer, output_buffer);

        D3D11_MAPPED_SUBRESOURCE subresource = {};
        subresource.RowPitch = buffer_width * sizeof(float);
        subresource.DepthPitch = buffer_height * sizeof(float);
        m_device_context->Map(readback_buffer, 0, D3D11_MAP_READ, 0, &subresource);

        if (subresource.pData)
        {
            memcpy((void *)output_data, subresource.pData, buffer_width * buffer_height * sizeof(float));
        }

        m_device_context->Unmap(readback_buffer, 0);
    }

    // Cleanup GPU Resources
    {
        SAFE_RELEASE(input_buffer_srv);
        SAFE_RELEASE(output_buffer_uav);
        SAFE_RELEASE(input_buffer);
        SAFE_RELEASE(output_buffer);
        SAFE_RELEASE(shader_settings_buffer);
        SAFE_RELEASE(readback_buffer);
    }
    OutputDebugStringA("dispatch_float_shader DONE\n");
}

struct ReduceTo1dShaderSettings
{
    uint32_t thread_group_count_x;
    uint32_t thread_group_count_y;
};

struct ReduceToSingleShaderSettings
{
    uint32_t element_count;
    uint32_t thread_group_count_x;
};

void D3D11::dispatch_float_reduce_shader(ComputeInfo job)
{
    OutputDebugStringA("dispatch_float_reduce START\n");
    void *shader_settings = job.shader_settings;
    size_t shader_settings_size = job.shader_settings_size;
    int32_t buffer_width = job.buffer_width;
    int32_t buffer_height = job.buffer_height;
    float *input_data = &job.input_datas[0];
    float *output_data = &job.output_datas[0];

    ComputeShader &reduce_to_1d_shader = m_compute_shaders[job.compute_id];
    ComputeShader &reduce_to_single_shader = m_compute_shaders[job.compute_id + 1];
    assert(m_device);
    assert(m_device_context);
    assert(reduce_to_1d_shader.compute_shader);
    assert(reduce_to_single_shader.compute_shader);

    assert(input_data);
    assert(output_data);

    ID3D11Buffer *reduce_to_1d_settings_buffer = nullptr;
    ID3D11Buffer *reduce_to_single_settings_buffer = nullptr;
    ID3D11Buffer *shader_settings_buffer = nullptr;
    ID3D11Buffer *input_buffer = nullptr;
    ID3D11Buffer *reduction_buffer_0 = nullptr;
    ID3D11Buffer *reduction_buffer_1 = nullptr;
    ID3D11Buffer *readback_buffer = nullptr;

    create_constant_buffer(shader_settings_size, shader_settings, "User CB", &shader_settings_buffer);
    create_structured_buffer(sizeof(float), buffer_width * buffer_height, (void *)input_data, "Input Buffer", &input_buffer);
    create_structured_buffer(sizeof(float), uint32_t(ceil(buffer_width * buffer_height / (float)reduce_to_1d_shader.thread_group_size[0])), nullptr, "Reduction Buffer 0", &reduction_buffer_0);
    create_structured_buffer(sizeof(float), uint32_t(ceil(buffer_width * buffer_height / (float)reduce_to_1d_shader.thread_group_size[0])), nullptr, "Reduction Buffer 1", &reduction_buffer_1);
    create_structured_buffer(sizeof(float), uint32_t(ceil(buffer_width * buffer_height / (float)reduce_to_1d_shader.thread_group_size[0])), nullptr, "Readback Buffer", &readback_buffer);

    assert(shader_settings_buffer);
    assert(input_buffer);
    assert(reduction_buffer_0);
    assert(reduction_buffer_1);
    assert(readback_buffer);

    uint32_t dimension_x = uint32_t(ceil((buffer_width / (float)reduce_to_1d_shader.thread_group_size[0]) / 2.0f));
    uint32_t dimension_y = uint32_t(ceil((buffer_height / (float)reduce_to_1d_shader.thread_group_size[1]) / 2.0f));

    ReduceTo1dShaderSettings redute_to_1d_shader_settings = {dimension_x, dimension_y};
    create_constant_buffer(sizeof(ReduceTo1dShaderSettings), &reduce_to_1d_settings_buffer, "Reduce to 1D CB", &reduce_to_1d_settings_buffer);
    assert(reduce_to_1d_settings_buffer);

    create_constant_buffer(sizeof(ReduceToSingleShaderSettings), nullptr, "Reduce to Single CB", &reduce_to_single_settings_buffer);
    assert(reduce_to_single_settings_buffer);

    ID3D11ShaderResourceView *input_buffer_srv = nullptr;
    create_buffer_srv(input_buffer, &input_buffer_srv);
    assert(input_buffer_srv);

    ID3D11ShaderResourceView *reduction_buffer_0_srv = nullptr;
    ID3D11ShaderResourceView *reduction_buffer_1_srv = nullptr;
    create_buffer_srv(reduction_buffer_0, &reduction_buffer_0_srv);
    create_buffer_srv(reduction_buffer_1, &reduction_buffer_1_srv);
    assert(reduction_buffer_0_srv);
    assert(reduction_buffer_1_srv);

    ID3D11UnorderedAccessView *reduction_buffer_0_uav = nullptr;
    ID3D11UnorderedAccessView *reduction_buffer_1_uav = nullptr;
    create_buffer_uav(reduction_buffer_0, &reduction_buffer_0_uav);
    create_buffer_uav(reduction_buffer_1, &reduction_buffer_1_uav);
    assert(reduction_buffer_0_uav);
    assert(reduction_buffer_1_uav);

    // First Pass: reduce input buffer (which contains 2D image data) to 1D
    {
        m_device_context->CSSetShader(reduce_to_1d_shader.compute_shader, nullptr, 0);
        m_device_context->CSSetConstantBuffers(0, 1, &reduce_to_1d_settings_buffer);
        m_device_context->CSSetConstantBuffers(1, 1, &shader_settings_buffer);
        m_device_context->CSSetShaderResources(0, 1, &input_buffer_srv);
        m_device_context->CSSetUnorderedAccessViews(0, 1, &reduction_buffer_0_uav, nullptr);
        m_device_context->Dispatch(dimension_x, dimension_y, reduce_to_1d_shader.thread_group_size[2]);
    }

    // Reduction Passes
    uint32_t reduction_passes = 0;
    {
        uint32_t thread_group_count = uint32_t(ceil((dimension_x * dimension_y) / 128.0f));
        uint32_t element_count = dimension_x * dimension_y;

        if (element_count > 1)
        {
            for (;;)
            {
                reduction_passes += 1;

                ReduceToSingleShaderSettings reduce_to_single_shader_settings = {element_count, thread_group_count};
                D3D11_MAPPED_SUBRESOURCE mapped_resource;
                m_device_context->Map(reduce_to_single_settings_buffer, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped_resource);
                memcpy(mapped_resource.pData, &reduce_to_single_shader_settings, sizeof(reduce_to_single_shader_settings));
                m_device_context->Unmap(reduce_to_single_settings_buffer, 0);

                m_device_context->CSSetShader(reduce_to_single_shader.compute_shader, nullptr, 0);
                m_device_context->CSSetConstantBuffers(0, 1, &reduce_to_single_settings_buffer);
                m_device_context->CSSetConstantBuffers(1, 1, &shader_settings_buffer);

                if (reduction_passes % 2 == 1)
                {
                    m_device_context->CSSetShaderResources(0, 1, &reduction_buffer_0_srv);
                    m_device_context->CSSetUnorderedAccessViews(0, 1, &reduction_buffer_1_uav, nullptr);
                }
                else
                {
                    m_device_context->CSSetShaderResources(0, 1, &reduction_buffer_1_srv);
                    m_device_context->CSSetUnorderedAccessViews(0, 1, &reduction_buffer_0_uav, nullptr);
                }

                m_device_context->Dispatch(thread_group_count, 1, 1);

                element_count = thread_group_count;
                thread_group_count = uint32_t(ceil(thread_group_count / 128.0f));

                if (element_count == 1)
                    break;
            }
        }
    }

    // Read back data
    {
        m_device_context->CopyResource(readback_buffer, reduction_passes % 2 == 0 ? reduction_buffer_0 : reduction_buffer_1);

        D3D11_MAPPED_SUBRESOURCE subresource = {};
        subresource.RowPitch = buffer_width * sizeof(float);
        subresource.DepthPitch = buffer_height * sizeof(float);
        m_device_context->Map(readback_buffer, 0, D3D11_MAP_READ, 0, &subresource);

        if (subresource.pData)
        {
            memcpy((void *)output_data, subresource.pData, sizeof(float));
        }

        m_device_context->Unmap(readback_buffer, 0);
    }

    // Cleanup GPU Resources
    {
        SAFE_RELEASE(input_buffer_srv);
        SAFE_RELEASE(reduction_buffer_0_srv);
        SAFE_RELEASE(reduction_buffer_0_uav);
        SAFE_RELEASE(reduction_buffer_1_srv);
        SAFE_RELEASE(reduction_buffer_1_uav);
        SAFE_RELEASE(input_buffer);
        SAFE_RELEASE(reduction_buffer_0);
        SAFE_RELEASE(reduction_buffer_1);
        SAFE_RELEASE(readback_buffer);
        SAFE_RELEASE(shader_settings_buffer);
        SAFE_RELEASE(reduce_to_1d_settings_buffer);
        SAFE_RELEASE(reduce_to_single_settings_buffer);
    }
    OutputDebugStringA("dispatch_reduce_shader DONE\n");
}