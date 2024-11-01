#pragma once

#include <d3d11.h>
#include <d3dcompiler.h>
#include <inttypes.h>

#define SAFE_RELEASE(ptr)     \
    do                        \
    {                         \
        if ((ptr))            \
        {                     \
            (ptr)->Release(); \
            ptr = NULL;       \
        }                     \
    } while (0)

// Thank you Jeremy
// Inherit to disallow copies.
struct NoCopy
{
    NoCopy() = default;
    ~NoCopy() = default;
    NoCopy(NoCopy &&) = default;
    NoCopy &operator=(NoCopy &&) = default;

    NoCopy(const NoCopy &) = delete;
    NoCopy &operator=(const NoCopy &) = delete;
};

struct Texture2D : NoCopy
{
    ID3D11Texture2D *texture = nullptr;
    ID3D11ShaderResourceView *srv = nullptr;
    int32_t width = 0;
    int32_t height = 0;
    int32_t channel_count = 0;

    void update_content(ID3D11DeviceContext *device_context, unsigned char *data);
};

struct ComputeShader : NoCopy
{
    ID3D11ComputeShader *compute_shader;
    ID3D11ShaderReflection *reflection;
    uint32_t thread_group_size[3];
    unsigned id;
    const char *name;
};

struct ComputeInfo
{
    unsigned compute_id;
    unsigned compute_operator_id;
    float *input_datas;
    float *output_datas;
    uint32_t buffer_width;
    uint32_t buffer_height;
    void *shader_settings;
    unsigned shader_settings_size;
};

struct D3D11 : NoCopy
{
    ID3D11Device *m_device = nullptr;
    ID3D11DeviceContext *m_device_context = nullptr;
    IDXGISwapChain *m_swapchain = nullptr;
    ID3D11RenderTargetView *m_main_render_target_view = nullptr;
    uint32_t m_render_target_width = 0;
    uint32_t m_render_target_height = 0;

    ComputeShader m_compute_shaders[16];
    unsigned m_compute_shader_count = 0;

    bool create_device(HWND hwnd);
    void cleanup_device();

    void create_render_target();
    void cleanup_render_target();
    void resize_render_target(int32_t width, int32_t height);
    void bind_render_target(const float clear_color[4]);

    void create_texture(int32_t width, int32_t height, Texture2D *out_texture);
    HRESULT compile_compute_shader(LPCWSTR path, const char *entry, const D3D_SHADER_MACRO *defines, ComputeShader *out_compute_shader);

    HRESULT create_buffer(D3D11_BUFFER_DESC desc, void *data, const char *debug_name, ID3D11Buffer **out_buffer);
    HRESULT create_constant_buffer(uint32_t buffer_size, void *data, const char *debug_name, ID3D11Buffer **out_buffer);
    HRESULT update_constant_buffer(uint32_t buffer_size, void *data, ID3D11Buffer *buffer);
    HRESULT create_structured_buffer(uint32_t element_size, uint32_t element_count, void *initial_data, const char *debug_name, ID3D11Buffer **out_buffer);
    HRESULT create_readback_buffer(uint32_t element_size, uint32_t element_count, const char *debug_name, ID3D11Buffer **out_buffer);
    HRESULT create_buffer_srv(ID3D11Buffer *buffer, ID3D11ShaderResourceView **out_srv);
    HRESULT create_buffer_uav(ID3D11Buffer *buffer, ID3D11UnorderedAccessView **out_uav);

    // Higher-level API
    void dispatch_float_shader(ComputeInfo job);
    void dispatch_float_reduce(ComputeInfo job);
};