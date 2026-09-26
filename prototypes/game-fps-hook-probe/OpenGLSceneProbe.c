#include <SDL2/SDL.h>
#include <OpenGL/gl.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    (void)argc;
    (void)argv;
    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        fprintf(stderr, "SDL_Init failed: %s\n", SDL_GetError());
        return 1;
    }
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 1);
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
    SDL_Window *window = SDL_CreateWindow("Hagimi OpenGL FPS Probe", SDL_WINDOWPOS_CENTERED,
                                           SDL_WINDOWPOS_CENTERED, 900, 560,
                                           SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE);
    if (!window) {
        fprintf(stderr, "SDL_CreateWindow failed: %s\n", SDL_GetError());
        SDL_Quit();
        return 1;
    }
    SDL_GLContext context = SDL_GL_CreateContext(window);
    if (!context) {
        fprintf(stderr, "SDL_GL_CreateContext failed: %s\n", SDL_GetError());
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 1;
    }
    int vsync = SDL_GL_SetSwapInterval(1);
    int targetFPS = 120;
    const char *value = getenv("HAGIMI_FPS_TARGET");
    if (value && atoi(value) > 0) targetFPS = atoi(value);
    fprintf(stdout, "{\"target\":\"opengl\",\"requested_fps\":%d,\"vsync_result\":%d}\n", targetFPS, vsync);
    fflush(stdout);

    const double frequency = (double)SDL_GetPerformanceFrequency();
    double lastReport = (double)SDL_GetPerformanceCounter() / frequency;
    double nextFrame = lastReport;
    unsigned long submitted = 0;
    int running = 1;
    while (running) {
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT) running = 0;
            if (event.type == SDL_KEYDOWN && event.key.keysym.sym == SDLK_ESCAPE) running = 0;
        }
        double now = (double)SDL_GetPerformanceCounter() / frequency;
        // VSync 已接管节拍时不再 SDL_Delay(1):它可能刚好跨过下一次 120Hz 垂直回扫。
        if (vsync != 0 && now < nextFrame) {
            SDL_Delay(1);
            continue;
        }
        nextFrame = now + 1.0 / targetFPS;
        float phase = (float)(now * 2.0);
        glClearColor(0.25f + 0.25f * sinf(phase), 0.22f + 0.22f * sinf(phase * 0.73f),
                     0.45f + 0.25f * cosf(phase * 0.91f), 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        SDL_GL_SwapWindow(window);
        submitted++;
        if (now - lastReport >= 1.0) {
            fprintf(stdout, "{\"target\":\"opengl\",\"submitted\":%lu,\"seconds\":%.3f}\n",
                    submitted, now - lastReport);
            fflush(stdout);
            submitted = 0;
            lastReport = now;
        }
    }
    SDL_GL_DeleteContext(context);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
