#include "d3d11.h"

#include <assert.h>

static uint32_t get_reduce_compute_id(uint32_t thread_group_x);
static void cleanup_compute_shader_context(ID3D11DeviceContext *ctx);

#define OPERATOR_MIN(a, b) ((a < b) ? a : b);
#define OPERATOR_MAX(a, b) ((a > b) ? a : b);

struct ParallelReductionConstantBuffer
{
    float m_first_pass;
    uint32_t m_buffer_width;
    uint32_t m_buffer_height;
    uint32_t m_operator;
};

static uint32_t k_max_thread_groups_per_dimension = 65535;
static uint32_t k_parallel_reduction_magic_value = 1024;

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
    sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;

    IDXGIFactory1 *factory = nullptr;
    CreateDXGIFactory1(IID_PPV_ARGS(&factory));

    IDXGIAdapter1 *adapter = nullptr;
    uint64_t i = 0;
    uint64_t best_adapter_index = 0;
    size_t max_vram_size = 0;
    while (factory->EnumAdapters1(i, &adapter) != DXGI_ERROR_NOT_FOUND)
    {
        DXGI_ADAPTER_DESC desc{};
        adapter->GetDesc(&desc);
        if (desc.DedicatedVideoMemory > max_vram_size)
        {
            max_vram_size = desc.DedicatedVideoMemory;
            best_adapter_index = i;
        }
        i++;
    }

    factory->EnumAdapters1(best_adapter_index, &adapter);
    DXGI_ADAPTER_DESC desc{};
    adapter->GetDesc(&desc);
    OutputDebugStringW(L"Selected GPU: ");
    OutputDebugStringW(desc.Description);
    OutputDebugStringW(L"\n");

    UINT create_device_flags = 0;
#if defined(_DEBUG)
    create_device_flags |= D3D11_CREATE_DEVICE_DEBUG;
#endif

    D3D_FEATURE_LEVEL feature_level;
    const D3D_FEATURE_LEVEL feature_level_array[2] = {
        D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_0,
    };
    HRESULT res = D3D11CreateDeviceAndSwapChain(adapter, D3D_DRIVER_TYPE_UNKNOWN, nullptr, create_device_flags, feature_level_array, 2, D3D11_SDK_VERSION, &sd, &m_swapchain, &m_device, &feature_level, &m_device_context);
    if (res != S_OK)
        return false;

    create_render_target();

    m_compute_shader_count = 0;
    compile_compute_shader(L"shaders/remap.hlsl", "CSRemap", nullptr, &m_compute_shaders[m_compute_shader_count]);
    m_compute_shader_count++;
    compile_compute_shader(L"shaders/square.hlsl", "CSSquare", nullptr, &m_compute_shaders[m_compute_shader_count]);
    m_compute_shader_count++;
    compile_compute_shader(L"shaders/multiply.hlsl", "CSMultiply", nullptr, &m_compute_shaders[m_compute_shader_count]);
    m_compute_shader_count++;
    compile_compute_shader(L"shaders/gradient.hlsl", "CSGradient", nullptr, &m_compute_shaders[m_compute_shader_count]);
    m_compute_shader_count++;
    compile_compute_shader(L"shaders/fbm.hlsl", "CSGenerateFBM", nullptr, &m_compute_shaders[m_compute_shader_count]);
    m_compute_shader_count++;
    compile_compute_shader(L"shaders/upsample_blur.hlsl", "CSUpsampleBlur", nullptr, &m_compute_shaders[m_compute_shader_count]);
    m_compute_shader_count++;
    compile_compute_shader(L"shaders/upsample_bilinear.hlsl", "CSUpsampleBilinear", nullptr, &m_compute_shaders[m_compute_shader_count]);
    m_compute_shader_count++;
    compile_compute_shader(L"shaders/downsample.hlsl", "CSDownsample", nullptr, &m_compute_shaders[m_compute_shader_count]);
    m_compute_shader_count++;
    compile_compute_shader(L"shaders/terrace.hlsl", "CSTerrace", nullptr, &m_compute_shaders[m_compute_shader_count]);
    m_compute_shader_count++;

    assert(m_compute_shader_count + 10 < 32);

    // Parallel Reduce (Min/Max)
    {
        {
            compile_compute_shader(L"shaders/parallel_reduce.hlsl", "CSReduceSum", nullptr, &m_compute_shaders[m_compute_shader_count]);
            m_compute_shader_count++;
        }

        // `#define GROUP_DIMENSION_X 256`
        {
            D3D_SHADER_MACRO macros[] = {"GROUP_DIMENSION_X", "256", nullptr, nullptr};
            compile_compute_shader(L"shaders/parallel_reduce.hlsl", "CSReduceSum", macros, &m_compute_shaders[m_compute_shader_count]);
            m_compute_shader_count++;
        }

        // `#define GROUP_DIMENSION_X 128`
        {
            D3D_SHADER_MACRO macros[] = {"GROUP_DIMENSION_X", "128", nullptr, nullptr};
            compile_compute_shader(L"shaders/parallel_reduce.hlsl", "CSReduceSum", macros, &m_compute_shaders[m_compute_shader_count]);
            m_compute_shader_count++;
        }

        // `#define GROUP_DIMENSION_X 64`
        {
            D3D_SHADER_MACRO macros[] = {"GROUP_DIMENSION_X", "64", nullptr, nullptr};
            compile_compute_shader(L"shaders/parallel_reduce.hlsl", "CSReduceSum", macros, &m_compute_shaders[m_compute_shader_count]);
            m_compute_shader_count++;
        }

        // `#define GROUP_DIMENSION_X 32`
        {
            D3D_SHADER_MACRO macros[] = {"GROUP_DIMENSION_X", "32", nullptr, nullptr};
            compile_compute_shader(L"shaders/parallel_reduce.hlsl", "CSReduceSum", macros, &m_compute_shaders[m_compute_shader_count]);
            m_compute_shader_count++;
        }

        // `#define GROUP_DIMENSION_X 16`
        {
            D3D_SHADER_MACRO macros[] = {"GROUP_DIMENSION_X", "16", nullptr, nullptr};
            compile_compute_shader(L"shaders/parallel_reduce.hlsl", "CSReduceSum", macros, &m_compute_shaders[m_compute_shader_count]);
            m_compute_shader_count++;
        }

        // `#define GROUP_DIMENSION_X 8`
        {
            D3D_SHADER_MACRO macros[] = {"GROUP_DIMENSION_X", "8", nullptr, nullptr};
            compile_compute_shader(L"shaders/parallel_reduce.hlsl", "CSReduceSum", macros, &m_compute_shaders[m_compute_shader_count]);
            m_compute_shader_count++;
        }

        // `#define GROUP_DIMENSION_X 4`
        {
            D3D_SHADER_MACRO macros[] = {"GROUP_DIMENSION_X", "4", nullptr, nullptr};
            compile_compute_shader(L"shaders/parallel_reduce.hlsl", "CSReduceSum", macros, &m_compute_shaders[m_compute_shader_count]);
            m_compute_shader_count++;
        }

        // `#define GROUP_DIMENSION_X 2`
        {
            D3D_SHADER_MACRO macros[] = {"GROUP_DIMENSION_X", "2", nullptr, nullptr};
            compile_compute_shader(L"shaders/parallel_reduce.hlsl", "CSReduceSum", macros, &m_compute_shaders[m_compute_shader_count]);
            m_compute_shader_count++;
        }

        // `#define GROUP_DIMENSION_X 1`
        {
            D3D_SHADER_MACRO macros[] = {"GROUP_DIMENSION_X", "1", nullptr, nullptr};
            compile_compute_shader(L"shaders/parallel_reduce.hlsl", "CSReduceSum", macros, &m_compute_shaders[m_compute_shader_count]);
            m_compute_shader_count++;
        }
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
        assert(false);
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

    // D3D11_SHADER_VARIABLE_DESC desc;
    // ID3D11ShaderReflectionVariable *var_use_input = out_compute_shader->reflection->GetVariableByName("use_input");
    // if (SUCCEEDED(var_use_input->GetDesc(&desc)))
    // {
    //     unsigned use_input = *(unsigned *)(desc.DefaultValue);
    //     use_input++;
    // }

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
    desc.Usage = D3D11_USAGE_DYNAMIC;
    desc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    desc.ByteWidth = buffer_size;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    desc.MiscFlags = 0;
    return create_buffer(desc, initial_data, debug_name, out_buffer);
}

HRESULT D3D11::update_constant_buffer(uint32_t size, void *data, ID3D11Buffer *buffer)
{
    D3D11_MAPPED_SUBRESOURCE mapped_resource;
    HRESULT hr = m_device_context->Map(buffer, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped_resource);
    assert(hr == S_OK);
    if (hr == S_OK)
    {
        memcpy(mapped_resource.pData, data, size);
        m_device_context->Unmap(buffer, 0);
    }

    return hr;
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

    ComputeShader &shader = m_compute_shaders[job.compute_id];
    assert(m_device);
    assert(m_device_context);
    assert(shader.compute_shader);

    ID3D11Buffer *shader_settings_buffer = nullptr;
    ID3D11Buffer *input_buffers[8];
    ID3D11Buffer *output_buffers[8];
    ID3D11Buffer *readback_buffers[8];

    create_constant_buffer(shader_settings_size, shader_settings, "User CB", &shader_settings_buffer);
    for (unsigned i_buf = 0; i_buf < job.in_count; i_buf++)
    {
        ComputeBuffer &buffer = job.in_buffers[i_buf];
        create_structured_buffer(sizeof(float), buffer.width * buffer.height, (void *)buffer.data, "Input Buffer", &input_buffers[i_buf]);
        assert(input_buffers[i_buf]);
    }
    for (unsigned i_buf = 0; i_buf < job.out_count; i_buf++)
    {
        ComputeBuffer &buffer = job.out_buffers[i_buf];
        create_structured_buffer(sizeof(float), buffer.width * buffer.height, nullptr, "Output Buffer", &output_buffers[i_buf]);
        create_readback_buffer(sizeof(float), buffer.width * buffer.height, "Readback Buffer", &readback_buffers[i_buf]);
        assert(output_buffers[i_buf]);
        assert(readback_buffers[i_buf]);
    }

    assert(shader_settings_buffer);

    ID3D11ShaderResourceView *input_buffers_srv[8];
    ID3D11UnorderedAccessView *output_buffers_uav[8];

    for (unsigned i_buf = 0; i_buf < job.in_count; i_buf++)
    {
        create_buffer_srv(input_buffers[i_buf], &input_buffers_srv[i_buf]);
        assert(input_buffers_srv[i_buf]);
    }
    for (unsigned i_buf = 0; i_buf < job.out_count; i_buf++)
    {
        create_buffer_uav(output_buffers[i_buf], &output_buffers_uav[i_buf]);
        assert(output_buffers_uav[i_buf]);
    }

    // Run the compute shader
    {
        m_device_context->CSSetShader(shader.compute_shader, nullptr, 0);
        m_device_context->CSSetConstantBuffers(0, 1, &shader_settings_buffer);
        for (unsigned i_buf = 0; i_buf < job.in_count; i_buf++)
        {
            m_device_context->CSSetShaderResources(i_buf, 1, &input_buffers_srv[i_buf]);
        }
        for (unsigned i_buf = 0; i_buf < job.out_count; i_buf++)
        {
            m_device_context->CSSetUnorderedAccessViews(i_buf, 1, &output_buffers_uav[i_buf], nullptr);
        }

        // unsigned width = shader.use_input ? job.in_buffers[shader.buffer_width_index] : job.out_buffers[shader.buffer_width_index];

        // What should be passed in here? 👇👇
        m_device_context->Dispatch(
            job.in_buffers[0].width / shader.thread_group_size[0],
            job.in_buffers[0].height / shader.thread_group_size[1],
            // width / shader.thread_group_size[0] + 1,
            // job.out_buffers[0].height / shader.thread_group_size[1] + 1,
            shader.thread_group_size[2]);

        cleanup_compute_shader_context(m_device_context);
    }

    // Read back data
    {
        for (unsigned i_buf = 0; i_buf < job.out_count; i_buf++)
        {
            ComputeBuffer &buffer = job.out_buffers[i_buf];
            m_device_context->CopyResource(readback_buffers[i_buf], output_buffers[i_buf]);

            D3D11_MAPPED_SUBRESOURCE subresource = {};
            subresource.RowPitch = buffer.width * sizeof(float);
            subresource.DepthPitch = buffer.height * sizeof(float);
            m_device_context->Map(readback_buffers[i_buf], 0, D3D11_MAP_READ, 0, &subresource);

            if (subresource.pData)
            {
                memcpy((void *)buffer.data, subresource.pData, buffer.width * buffer.height * sizeof(float));
            }

            m_device_context->Unmap(readback_buffers[i_buf], 0);
        }
    }

    // Cleanup GPU Resources
    {
        for (unsigned i_buf = 0; i_buf < job.in_count; i_buf++)
        {
            SAFE_RELEASE(input_buffers_srv[i_buf]);
            SAFE_RELEASE(input_buffers[i_buf]);
        }
        for (unsigned i_buf = 0; i_buf < job.out_count; i_buf++)
        {
            SAFE_RELEASE(output_buffers_uav[i_buf]);
            SAFE_RELEASE(output_buffers[i_buf]);
            SAFE_RELEASE(readback_buffers[i_buf]);
        }
        SAFE_RELEASE(shader_settings_buffer);
    }
    OutputDebugStringA("dispatch_float_shader DONE\n");
}

void D3D11::dispatch_float_reduce(ComputeInfo job)
{
    OutputDebugStringA("dispatch_float_reduce START\n");
    assert(m_device);
    assert(m_device_context);

    int32_t buffer_width = job.in_buffers[0].width;
    int32_t buffer_height = job.in_buffers[0].height;

    uint32_t buffer_elements = buffer_width * buffer_height;
    uint32_t thread_groups_size = buffer_elements / k_parallel_reduction_magic_value;
    uint32_t reduction_iterations = 1;
    uint32_t buffer_adjusted_size = buffer_width;

    while (thread_groups_size > k_max_thread_groups_per_dimension)
    {
        buffer_adjusted_size >>= 1;
        buffer_elements = buffer_adjusted_size * buffer_adjusted_size;
        thread_groups_size = buffer_elements / k_parallel_reduction_magic_value;
        reduction_iterations++;
    }

    float reductions[16];
    memset(&reductions, 0.0, sizeof(float) * 16);

    for (uint32_t reduction_index = 0; reduction_index < reduction_iterations; reduction_index++)
    {
        const float *input_data = job.in_buffers[0].data + (reduction_index * buffer_adjusted_size * buffer_adjusted_size);
        float *output_data = job.out_buffers[0].data + (reduction_index * buffer_adjusted_size * buffer_adjusted_size);
        assert(input_data);
        assert(output_data);

        ID3D11Buffer *constant_buffer = nullptr;
        ID3D11Buffer *data_buffer = nullptr;
        ID3D11Buffer *output_buffer = nullptr;
        ID3D11Buffer *readback_buffer = nullptr;

        create_constant_buffer(sizeof(ParallelReductionConstantBuffer), nullptr, "Constant Buffer", &constant_buffer);
        create_structured_buffer(sizeof(float), buffer_elements, (void *)input_data, "Data Buffer", &data_buffer);
        create_structured_buffer(sizeof(float), buffer_elements / k_parallel_reduction_magic_value, nullptr, "Output Buffer", &output_buffer);
        create_readback_buffer(sizeof(float), buffer_elements / k_parallel_reduction_magic_value, "Readback Buffer", &readback_buffer);

        assert(constant_buffer);
        assert(data_buffer);
        assert(output_buffer);
        assert(readback_buffer);

        ID3D11ShaderResourceView *data_buffer_srv = nullptr;
        ID3D11UnorderedAccessView *output_buffer_uav = nullptr;
        create_buffer_srv(data_buffer, &data_buffer_srv);
        create_buffer_uav(output_buffer, &output_buffer_uav);
        assert(data_buffer_srv);
        assert(output_buffer_uav);

        ComputeShader *parallel_reduce_shader = &m_compute_shaders[job.compute_id];
        assert(parallel_reduce_shader->compute_shader);

        for (uint32_t thread_group_x = buffer_elements; thread_group_x >= k_parallel_reduction_magic_value;)
        {
            ParallelReductionConstantBuffer constant_buffer_data = {
                .m_first_pass = thread_group_x == buffer_elements ? 1.0f : 0.0f,
                .m_buffer_width = (uint32_t)buffer_width,
                .m_buffer_height = (uint32_t)buffer_height,
                .m_operator = (uint32_t)job.compute_operator_id,
            };

            thread_group_x /= k_parallel_reduction_magic_value;
            update_constant_buffer(sizeof(constant_buffer_data), &constant_buffer_data, constant_buffer);

            m_device_context->CSSetShader(parallel_reduce_shader->compute_shader, nullptr, 0);
            m_device_context->CSSetConstantBuffers(0, 1, &constant_buffer);
            m_device_context->CSSetShaderResources(0, 1, &data_buffer_srv);
            m_device_context->CSSetUnorderedAccessViews(0, 1, &output_buffer_uav, nullptr);
            m_device_context->Dispatch(thread_group_x, 1, 1);
            cleanup_compute_shader_context(m_device_context);

            if (thread_group_x < k_parallel_reduction_magic_value && thread_group_x != 1)
            {
                parallel_reduce_shader = &m_compute_shaders[get_reduce_compute_id(thread_group_x)];
                constant_buffer_data.m_first_pass = 0.0f;
                update_constant_buffer(sizeof(constant_buffer_data), &constant_buffer_data, constant_buffer);

                m_device_context->CSSetShader(parallel_reduce_shader->compute_shader, nullptr, 0);
                m_device_context->CSSetConstantBuffers(0, 1, &constant_buffer);
                m_device_context->CSSetShaderResources(0, 1, &data_buffer_srv);
                m_device_context->CSSetUnorderedAccessViews(0, 1, &output_buffer_uav, nullptr);
                m_device_context->Dispatch(1, 1, 1);
                cleanup_compute_shader_context(m_device_context);
            }
        }

        // Read back data
        {
            m_device_context->CopyResource(readback_buffer, output_buffer);

            D3D11_MAPPED_SUBRESOURCE subresource = {};
            subresource.RowPitch = buffer_adjusted_size / k_parallel_reduction_magic_value * sizeof(float);
            subresource.DepthPitch = 1;
            m_device_context->Map(readback_buffer, 0, D3D11_MAP_READ, 0, &subresource);

            if (subresource.pData)
            {
                memcpy((void *)output_data, subresource.pData, sizeof(float));
            }

            m_device_context->Unmap(readback_buffer, 0);
        }

        // Cleanup GPU Resources
        {
            SAFE_RELEASE(data_buffer_srv);
            SAFE_RELEASE(output_buffer_uav);
            SAFE_RELEASE(data_buffer);
            SAFE_RELEASE(output_buffer);
            SAFE_RELEASE(constant_buffer);
            SAFE_RELEASE(readback_buffer);
        }

        reductions[reduction_index] = output_data[0];
    }

    // Calculate the final value
    float final_reduction = reductions[0];
    for (uint32_t i = 1; i < reduction_iterations; i++)
    {
        if (job.compute_operator_id == 1) // MIN
        {
            final_reduction = OPERATOR_MIN(final_reduction, reductions[i]);
        }
        else if (job.compute_operator_id == 2) // MAX
        {
            final_reduction = OPERATOR_MAX(final_reduction, reductions[i]);
        }
    }

    job.out_buffers[0].data[0] = final_reduction;

    OutputDebugStringA("dispatch_float_reduce DONE\n");
}

void D3D11::dispatch_float_generate(ComputeInfo job)
{
    OutputDebugStringA("dispatch_float_generate START\n");
    void *shader_settings = job.shader_settings;
    size_t shader_settings_size = job.shader_settings_size;
    int32_t buffer_width = job.out_buffers[0].width;
    int32_t buffer_height = job.out_buffers[0].height;
    float *output_data = job.out_buffers[0].data;

    ComputeShader &shader = m_compute_shaders[job.compute_id];
    assert(m_device);
    assert(m_device_context);
    assert(shader.compute_shader);

    assert(output_data);

    ID3D11Buffer *shader_settings_buffer = nullptr;
    ID3D11Buffer *output_buffer = nullptr;
    ID3D11Buffer *readback_buffer = nullptr;

    create_constant_buffer(shader_settings_size, shader_settings, "User CB", &shader_settings_buffer);
    create_structured_buffer(sizeof(float), buffer_width * buffer_height, nullptr, "Output Buffer", &output_buffer);
    create_readback_buffer(sizeof(float), buffer_width * buffer_height, "Readback Buffer", &readback_buffer);

    assert(shader_settings_buffer);
    assert(output_buffer);
    assert(readback_buffer);

    ID3D11UnorderedAccessView *output_buffer_uav = nullptr;
    create_buffer_uav(output_buffer, &output_buffer_uav);

    assert(output_buffer_uav);

    // Run the compute shader
    {
        m_device_context->CSSetShader(shader.compute_shader, nullptr, 0);
        m_device_context->CSSetConstantBuffers(0, 1, &shader_settings_buffer);
        m_device_context->CSSetUnorderedAccessViews(0, 1, &output_buffer_uav, nullptr);
        m_device_context->Dispatch(buffer_width / shader.thread_group_size[0], buffer_height / shader.thread_group_size[1], shader.thread_group_size[2]);
        cleanup_compute_shader_context(m_device_context);
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
        SAFE_RELEASE(output_buffer_uav);
        SAFE_RELEASE(output_buffer);
        SAFE_RELEASE(shader_settings_buffer);
        SAFE_RELEASE(readback_buffer);
    }
    OutputDebugStringA("dispatch_float_generate DONE\n");
}

uint32_t get_reduce_compute_id(uint32_t thread_group_x)
{
    // NOTE(gmodarelli): This is the ID of the parallel reduce compute shader
    // variant with `#define GROUP_DIMENSION_X 512`.
    const uint32_t base_compute_id = 3;

    if (thread_group_x == 256)
    {
        // `#define GROUP_DIMENSION_X 128`
        return base_compute_id + 2;
    }

    if (thread_group_x == 128)
    {
        // `#define GROUP_DIMENSION_X 64`
        return base_compute_id + 3;
    }

    if (thread_group_x == 64)
    {
        // `#define GROUP_DIMENSION_X 32`
        return base_compute_id + 4;
    }

    if (thread_group_x == 32)
    {
        // `#define GROUP_DIMENSION_X 16`
        return base_compute_id + 5;
    }

    if (thread_group_x == 16)
    {
        // `#define GROUP_DIMENSION_X 8`
        return base_compute_id + 6;
    }

    if (thread_group_x == 8)
    {
        // `#define GROUP_DIMENSION_X 4`
        return base_compute_id + 7;
    }

    if (thread_group_x == 4)
    {
        // `#define GROUP_DIMENSION_X 2`
        return base_compute_id + 8;
    }

    // `#define GROUP_DIMENSION_X 2`
    return base_compute_id + 8;
}

static void cleanup_compute_shader_context(ID3D11DeviceContext *ctx)
{
    ctx->CSSetShader(nullptr, nullptr, 0);
    ID3D11UnorderedAccessView *ppUAViewnullptr[1] = {nullptr};
    ctx->CSSetUnorderedAccessViews(0, 1, ppUAViewnullptr, nullptr);

    ID3D11ShaderResourceView *ppSRVnullptr[2] = {nullptr, nullptr};
    ctx->CSSetShaderResources(0, 2, ppSRVnullptr);

    ID3D11Buffer *ppCBnullptr[1] = {nullptr};
    ctx->CSSetConstantBuffers(0, 1, ppCBnullptr);
}