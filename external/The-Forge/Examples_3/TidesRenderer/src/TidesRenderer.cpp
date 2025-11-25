#include "TidesRenderer.h"

#include "../../../Common_3/Graphics/Interfaces/IGraphics.h"

int TR_initRenderer()
{
    const char* appName = "Tides Renderer";
    Renderer*   g_Renderer = NULL;

    RendererDesc settings;
    initRenderer(appName, &settings, &g_Renderer);

    return 0;
}
