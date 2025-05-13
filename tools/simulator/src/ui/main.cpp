// Dear ImGui: standalone example application for DirectX 11

// Learn about Dear ImGui:
// - FAQ                  https://dearimgui.com/faq
// - Getting Started      https://dearimgui.com/getting-started
// - Documentation        https://dearimgui.com/docs (same as your local docs/ folder).
// - Introduction, links and more at the top of imgui.cpp

#include "imgui.h"
#include "imgui_internal.h"
#include "imgui_impl_win32.h"
#include "imgui_impl_dx11.h"
#include <assert.h>
#include <tchar.h>

#include "d3d11/d3d11.h"
#include "main_cpp.h"
#include "sim/api.h"

// https://stackoverflow.com/questions/49722736/how-to-use-critical-section
#include <stdlib.h>
#include <stdio.h>
#include <windows.h>
#include <psapi.h>

CRITICAL_SECTION CriticalSectionEnqueue;
CRITICAL_SECTION CriticalSectionDequeue;
ComputeInfo compute_job;
bool compute_do_it_now = false;

static int32_t g_resize_width = 0;
static int32_t g_resize_height = 0;
static D3D11 g_d3d11;

// Forward declarations of helper functions
LRESULT WINAPI WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);

constexpr const char *cWindowNameViewport = "Viewport";
constexpr const char *cWindowNameSettings = "Settings";

struct Preview
{
	const char *name;
	bool visible;
	Texture2D texture;
};

const unsigned preview_size = 512;
Preview gPreviews[] = {
	{.name = "GenerateVoronoiMap1.image", .visible = false, .texture = {.texture = nullptr, .srv = nullptr, .width = preview_size, .height = preview_size, .channel_count = 4}},
	{.name = "generate_landscape_from_image.image", .visible = false, .texture = {.texture = nullptr, .srv = nullptr, .width = preview_size, .height = preview_size, .channel_count = 4}},
	{.name = "generate_beaches.image", .visible = false, .texture = {.texture = nullptr, .srv = nullptr, .width = preview_size, .height = preview_size, .channel_count = 4}},
	{.name = "generate_voronoi_map.image", .visible = false, .texture = {.texture = nullptr, .srv = nullptr, .width = preview_size, .height = preview_size, .channel_count = 4}},
	{.name = "generate_fbm.image", .visible = false, .texture = {.texture = nullptr, .srv = nullptr, .width = preview_size, .height = preview_size, .channel_count = 4}},
	{.name = "fbm_to_heightmap.image", .visible = false, .texture = {.texture = nullptr, .srv = nullptr, .width = preview_size, .height = preview_size, .channel_count = 4}},
	{.name = "generate_heightmap_gradient.image", .visible = false, .texture = {.texture = nullptr, .srv = nullptr, .width = preview_size, .height = preview_size, .channel_count = 4}},
	{.name = "generate_terrace.image", .visible = false, .texture = {.texture = nullptr, .srv = nullptr, .width = preview_size, .height = preview_size, .channel_count = 4}},
	{.name = "generate_trees_fbm.image", .visible = false, .texture = {.texture = nullptr, .srv = nullptr, .width = preview_size, .height = preview_size, .channel_count = 4}},
	{.name = "trees_square.image", .visible = false, .texture = {.texture = nullptr, .srv = nullptr, .width = preview_size, .height = preview_size, .channel_count = 4}},
	{.name = "generate_water.image", .visible = false, .texture = {.texture = nullptr, .srv = nullptr, .width = preview_size, .height = preview_size, .channel_count = 4}},
	{.name = "beaches.image", .visible = false, .texture = {.texture = nullptr, .srv = nullptr, .width = preview_size, .height = preview_size, .channel_count = 4}},
	{.name = "beaches2.image", .visible = false, .texture = {.texture = nullptr, .srv = nullptr, .width = preview_size * 2, .height = preview_size * 2, .channel_count = 4}},
	{.name = "fbm.image", .visible = false, .texture = {.texture = nullptr, .srv = nullptr, .width = preview_size * 2, .height = preview_size * 2, .channel_count = 4}},
	{.name = "heightmap.image", .visible = false, .texture = {.texture = nullptr, .srv = nullptr, .width = preview_size, .height = preview_size, .channel_count = 4}},
	{.name = "heightmap_waterify.image", .visible = false, .texture = {.texture = nullptr, .srv = nullptr, .width = preview_size, .height = preview_size, .channel_count = 4}},
	{.name = "heightmap_terraced.image", .visible = false, .texture = {.texture = nullptr, .srv = nullptr, .width = preview_size, .height = preview_size, .channel_count = 4}},
	{.name = "gradient.image", .visible = false, .texture = {.texture = nullptr, .srv = nullptr, .width = preview_size, .height = preview_size, .channel_count = 4}},
	{.name = "fbm_trees.image", .visible = false, .texture = {.texture = nullptr, .srv = nullptr, .width = preview_size, .height = preview_size, .channel_count = 4}},
};
constexpr unsigned PREVIEW_COUNT = sizeof(gPreviews) / sizeof(gPreviews[0]);

bool gRanOnce = false;
bool gExit = false;
bool gVSync = false;
void gSetupDocking();
void gDrawViewport();
void gDrawSettings(const SimulatorAPI *api);
void gDrawMenuBar();

void gGeneratePreview(const SimulatorAPI *api, Preview &preview);

void runUI(const SimulatorAPI *api)
{
	InitializeCriticalSection(&CriticalSectionEnqueue);
	InitializeCriticalSection(&CriticalSectionDequeue);

	// Create application window
	ImGui_ImplWin32_EnableDpiAwareness();
	WNDCLASSEXW wc = {sizeof(wc), CS_CLASSDC, WndProc, 0L, 0L, GetModuleHandle(nullptr), nullptr, nullptr, nullptr, nullptr, L"Simulator", nullptr};
	::RegisterClassExW(&wc);
	HWND hwnd = ::CreateWindowW(wc.lpszClassName, L"Simulator", WS_OVERLAPPEDWINDOW, 100, 100, 1280, 800, nullptr, nullptr, wc.hInstance, nullptr);

	// Initialize Direct3D
	if (!g_d3d11.create_device(hwnd))
	{
		g_d3d11.cleanup_device();
		::UnregisterClassW(wc.lpszClassName, wc.hInstance);
		return;
	}

	// Show the window
	::ShowWindow(hwnd, SW_SHOWDEFAULT);
	::UpdateWindow(hwnd);

	// Setup Dear ImGui context
	IMGUI_CHECKVERSION();
	ImGui::CreateContext();
	ImGuiIO &io = ImGui::GetIO();
	(void)io;
	io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard; // Enable Keyboard Controls
	io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad;  // Enable Gamepad Controls
	io.ConfigFlags |= ImGuiConfigFlags_DockingEnable;	  // Enable Docking
	io.ConfigFlags |= ImGuiConfigFlags_ViewportsEnable;	  // Enable Multi-Viewport / Platform Windows

	// Setup Dear ImGui style
	ImGui::StyleColorsDark();

	// When viewports are enabled we tweak WindowRounding/WindowBg so platform windows can look identical to regular ones.
	ImGuiStyle &style = ImGui::GetStyle();
	if (io.ConfigFlags & ImGuiConfigFlags_ViewportsEnable)
	{
		style.WindowRounding = 0.0f;
		style.Colors[ImGuiCol_WindowBg].w = 1.0f;
	}

	// Setup Platform/Renderer backends
	ImGui_ImplWin32_Init(hwnd);
	ImGui_ImplDX11_Init(g_d3d11.m_device, g_d3d11.m_device_context);

	ImVec4 clear_color = ImVec4(0.0f, 0.0f, 0.0f, 1.0f);

	// Main loop
	while (!gExit)
	{
		// Poll and handle messages (inputs, window resize, etc.)
		// See the WndProc() function below for our to dispatch events to the Win32 backend.
		MSG msg;
		while (::PeekMessage(&msg, nullptr, 0U, 0U, PM_REMOVE))
		{
			::TranslateMessage(&msg);
			::DispatchMessage(&msg);
			if (msg.message == WM_QUIT)
				gExit = true;
		}
		if (gExit)
			break;

		// Handle window resize (we don't resize directly in the WM_SIZE handler)
		g_d3d11.resize_render_target(g_resize_width, g_resize_height);

		// Start the Dear ImGui frame
		ImGui_ImplDX11_NewFrame();
		ImGui_ImplWin32_NewFrame();
		ImGui::NewFrame();

		gSetupDocking();
		gDrawSettings(api);
		gDrawViewport();
		gDrawMenuBar();

		EnterCriticalSection(&CriticalSectionEnqueue);
		if (compute_do_it_now)
		{
			EnterCriticalSection(&CriticalSectionDequeue);
			compute_do_it_now = false;
			if (compute_job.compute_id == 3) // ComputeId.fbm
			{
				g_d3d11.dispatch_float_generate(compute_job);
			}
			else if (compute_job.compute_id == 8) // ComputeId.reduce
			{
				g_d3d11.dispatch_float_reduce(compute_job);
			}
			else
			{
				g_d3d11.dispatch_float_shader(compute_job);
			}
			LeaveCriticalSection(&CriticalSectionDequeue);
		}
		LeaveCriticalSection(&CriticalSectionEnqueue);

		if (!gRanOnce)
		{
			gRanOnce = true;
			for (unsigned i_preview = 0; i_preview < PREVIEW_COUNT; i_preview++)
			{
				Preview &preview = gPreviews[i_preview];
				preview.visible = false;
				g_d3d11.create_texture(preview.texture.width, preview.texture.height, &preview.texture);
			}
			api->simulate();
		}

		for (unsigned i_preview = 0; i_preview < PREVIEW_COUNT; i_preview++)
		{
			Preview &preview = gPreviews[i_preview];
			if (!preview.visible)
			{
				gGeneratePreview(api, preview);
				if (preview.visible)
				{
					break;
				}
			}
		}

		// Rendering
		ImGui::Render();
		const float clear_color_with_alpha[4] = {clear_color.x * clear_color.w, clear_color.y * clear_color.w, clear_color.z * clear_color.w, clear_color.w};
		g_d3d11.bind_render_target(clear_color_with_alpha);
		ImGui_ImplDX11_RenderDrawData(ImGui::GetDrawData());

		// Update and Render additional Platform Windows
		if (io.ConfigFlags & ImGuiConfigFlags_ViewportsEnable)
		{
			ImGui::UpdatePlatformWindows();
			ImGui::RenderPlatformWindowsDefault();
		}

		g_d3d11.m_swapchain->Present(gVSync ? 1 : 0, 0);
	}

	// Cleanup
	ImGui_ImplDX11_Shutdown();
	ImGui_ImplWin32_Shutdown();
	ImGui::DestroyContext();

	g_d3d11.cleanup_device();
	::DestroyWindow(hwnd);
	::UnregisterClassW(wc.lpszClassName, wc.hInstance);

	DeleteCriticalSection(&CriticalSectionEnqueue);
	DeleteCriticalSection(&CriticalSectionDequeue);
}

// https://gist.github.com/moebiussurfing/d7e6ec46a44985dd557d7678ddfeda99
void gSetupDocking()
{
	static ImGuiDockNodeFlags dockspace_flags = ImGuiDockNodeFlags_PassthruCentralNode;
	// We are using the ImGuiWindowFlags_NoDocking flag to make the parent window not dockable into,
	// because it would be confusing to have two docking targets within each others.
	ImGuiWindowFlags window_flags = ImGuiWindowFlags_MenuBar | ImGuiWindowFlags_NoDocking;

	ImGuiViewport *viewport = ImGui::GetMainViewport();
	ImGui::SetNextWindowPos(viewport->Pos);
	ImGui::SetNextWindowSize(viewport->Size);
	ImGui::SetNextWindowViewport(viewport->ID);
	ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 0.0f);
	ImGui::PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0.0f);
	window_flags |= ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoMove;
	window_flags |= ImGuiWindowFlags_NoBringToFrontOnFocus | ImGuiWindowFlags_NoNavFocus;

	// When using ImGuiDockNodeFlags_PassthruCentralNode, DockSpace() will render our background and handle the pass-thru hole, so we ask Begin() to not render a background.
	if (dockspace_flags & ImGuiDockNodeFlags_PassthruCentralNode)
	{
		window_flags |= ImGuiWindowFlags_NoBackground;
	}

	// Important: note that we proceed even if Begin() returns false (aka window is collapsed).
	// This is because we want to keep our DockSpace() active. If a DockSpace() is inactive,
	// all active windows docked into it will lose their parent and become undocked.
	// We cannot preserve the docking relationship between an active window and an inactive docking, otherwise
	// any change of dockspace/settings would lead to windows being stuck in limbo and never being visible.
	ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(0.0f, 0.0f));
	ImGui::Begin("DockSpace", nullptr, window_flags);
	ImGui::PopStyleVar();
	ImGui::PopStyleVar(2);

	// Dockspace
	ImGuiIO &io = ImGui::GetIO();
	if (io.ConfigFlags & ImGuiConfigFlags_DockingEnable)
	{
		ImGuiID dockspace_id = ImGui::GetID("MyDockSpace");
		ImGui::DockSpace(dockspace_id, ImVec2(0.0f, 0.0f), dockspace_flags);

		static bool first_time = true;
		if (first_time)
		{
			first_time = false;

			ImGui::DockBuilderRemoveNode(dockspace_id); // clean any previous layout
			ImGui::DockBuilderAddNode(dockspace_id, dockspace_flags | ImGuiDockNodeFlags_DockSpace);
			ImGui::DockBuilderSetNodeSize(dockspace_id, viewport->Size);

			// split the dockspace into 2 nodes -- DockBuilderSplitNode takes in the following args in the following order
			//   window ID to split, direction, fraction (between 0 and 1), the final two setting let's us choose which id we want (which ever one we DON'T set as NULL, will be returned by the function)
			//                                                              out_id_at_dir is the id of the node in the direction we specified earlier, out_id_at_opposite_dir is in the opposite direction
			ImGuiID dock_id_main;
			ImGuiID dock_id_settings = ImGui::DockBuilderSplitNode(dockspace_id, ImGuiDir_Left, 0.2f, nullptr, &dock_id_main);

			// we now dock our windows into the docking node we made above
			ImGui::DockBuilderDockWindow(cWindowNameViewport, dock_id_main);
			ImGui::DockBuilderDockWindow(cWindowNameSettings, dock_id_settings);
			ImGui::DockBuilderFinish(dockspace_id);
		}
	}

	ImGui::End();
}

void gDrawViewport()
{
	if (!ImGui::Begin(cWindowNameViewport))
	{
		ImGui::End();
		return;
	}

	for (unsigned i_preview = PREVIEW_COUNT; i_preview > 0;)
	{
		i_preview--;
		Preview &preview = gPreviews[i_preview];
		if (preview.visible)
		{
			Texture2D &texture = preview.texture;
			assert(texture.texture);
			assert(texture.srv);
			ImGui::Image((void *)texture.srv, ImVec2(texture.width, texture.height));
			ImGui::SameLine();
			ImGui::LabelText("", preview.name);
		}
	}

	ImGui::End();
}

void gDrawSettings(const SimulatorAPI *api)
{
	if (!ImGui::Begin(cWindowNameSettings))
	{
		ImGui::End();
		return;
	}

	ImGui::Checkbox("VSync", &gVSync);

	// ImGui::SliderInt("Seed", &settings.seed, 0, 65535);
	// ImGui::InputFloat("World Size (km)", &settings.size);
	// ImGui::InputFloat("Cell radius (km)", &settings.radius);
	// ImGui::SliderInt("Relaxations", &settings.num_relaxations, 1, 15);
	// ImGui::ColorPicker3("Land Color", g_landscapeLandColor);
	// ImGui::ColorPicker3("Water Color", g_landscapeWaterColor);
	// ImGui::ColorPicker3("Shore Color", g_landscapeShoreColor);

	if (ImGui::Button("SIMULATE!!!!"))
	{
		api->simulate();
	}

	if (ImGui::Button("ONE TSTEP!!!!"))
	{
		api->simulateSteps(1);
	}

	// ImGui::SliderInt("Landscape Seed", &settings.landscape_seed, 0, 65535);
	// ImGui::SliderInt("Landscape Octaves", &settings.landscape_octaves, 0, 16);
	// ImGui::InputFloat("Landscape Frequency", &settings.landscape_frequency);
	static float percent = 0;
	const SimulatorProgress progress = api->getProgress();
	percent = percent + (progress.percent - percent) * 0.5;
	ImGui::ProgressBar(
		percent, ImVec2(ImGui::GetFontSize() * 15, 0.0f));

	ImGui::End();
}

void gDrawMenuBar()
{
	if (ImGui::BeginMainMenuBar())
	{
		if (ImGui::BeginMenu("File"))
		{
			if (ImGui::MenuItem("Exit", "Alt + F4"))
			{
				gExit = true;
			}

			ImGui::EndMenu();
		}

		ImGui::EndMainMenuBar();
	}
}

#ifndef WM_DPICHANGED
#define WM_DPICHANGED 0x02E0 // From Windows SDK 8.1+ headers
#endif

// Forward declare message handler from imgui_impl_win32.cpp
extern IMGUI_IMPL_API LRESULT ImGui_ImplWin32_WndProcHandler(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);

// Win32 message handler
// You can read the io.WantCaptureMouse, io.WantCaptureKeyboard flags to tell if dear imgui wants to use your inputs.
// - When io.WantCaptureMouse is true, do not dispatch mouse input data to your main application, or clear/overwrite your copy of the mouse data.
// - When io.WantCaptureKeyboard is true, do not dispatch keyboard input data to your main application, or clear/overwrite your copy of the keyboard data.
// Generally you may always pass all inputs to dear imgui, and hide them from your application based on those two flags.
LRESULT WINAPI WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
	if (ImGui_ImplWin32_WndProcHandler(hWnd, msg, wParam, lParam))
		return true;

	switch (msg)
	{
	case WM_SIZE:
		if (wParam == SIZE_MINIMIZED)
			return 0;
		g_resize_width = (UINT)LOWORD(lParam); // Queue resize
		g_resize_height = (UINT)HIWORD(lParam);
		return 0;
	case WM_SYSCOMMAND:
		if ((wParam & 0xfff0) == SC_KEYMENU) // Disable ALT application menu
			return 0;
		break;
	case WM_DESTROY:
		::PostQuitMessage(0);
		return 0;
	case WM_DPICHANGED:
		if (ImGui::GetIO().ConfigFlags & ImGuiConfigFlags_DpiEnableScaleViewports)
		{
			// const int dpi = HIWORD(wParam);
			// printf("WM_DPICHANGED to %d (%.0f%%)\n", dpi, (float)dpi / 96.0f * 100.0f);
			const RECT *suggested_rect = (RECT *)lParam;
			::SetWindowPos(hWnd, nullptr, suggested_rect->left, suggested_rect->top, suggested_rect->right - suggested_rect->left, suggested_rect->bottom - suggested_rect->top, SWP_NOZORDER | SWP_NOACTIVATE);
		}
		break;
	}
	return ::DefWindowProcW(hWnd, msg, wParam, lParam);
}

void gGeneratePreview(const SimulatorAPI *api, Preview &preview)
{
	unsigned char *image = api->getPreview(preview.name, preview.texture.width, preview.texture.height);
	if (image == NULL)
	{
		return;
	}

	preview.texture.update_content(g_d3d11.m_device_context, image);
	preview.visible = true;
}

void compute(const struct ComputeInfo *info)
{
	OutputDebugStringA("LOLOLOOL\n");

	EnterCriticalSection(&CriticalSectionEnqueue);
	compute_do_it_now = true;
	compute_job = *info;
	LeaveCriticalSection(&CriticalSectionEnqueue);

	while (true)
	{
		EnterCriticalSection(&CriticalSectionDequeue);
		if (compute_do_it_now)
		{
			LeaveCriticalSection(&CriticalSectionDequeue);
			continue;
		}

		OutputDebugStringA("LOLOLOOL 2222\n");
		LeaveCriticalSection(&CriticalSectionDequeue);
		break;
	}
}
