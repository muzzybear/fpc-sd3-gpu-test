{$mode objfpc}
{$H+}
{$modeswitch ADVANCEDRECORDS}

uses
    Sysutils, ctypes, Math, SDL3, SDL3_ttf;

const
    screen_width = 640;
    screen_height = 480;
    window_title = 'yatta';
    window_flags = 0; //SDL_WINDOW_VULKAN;

var
    Window: PSDL_Window = nil;
    Device: PSDL_GPUDevice = nil;
    Renderer: PSDL_Renderer = nil;
    Font: PTTF_Font;
    TextEngine: PTTF_TextEngine;

// -----

procedure init;
begin
    if not SDL_Init(SDL_INIT_VIDEO) then
    begin
        SDL_Log(PChar(Format('Couldn''t initialize SDL: %s', [SDL_GetError])));
        Exit;
    end;

    // TODO SDL_GPU_SHADERFORMAT_SPIRV | SDL_GPU_SHADERFORMAT_DXIL | SDL_GPU_SHADERFORMAT_MSL
    Device := SDL_CreateGPUDevice(SDL_GPU_SHADERFORMAT_SPIRV, true, nil);
    if Device = nil then
    begin
        SDL_Log(PChar(Format('Couldn''t create GPU device: %s', [SDL_GetError])));
        Exit;
    end;

    Window := SDL_CreateWindow(window_title, screen_width, screen_height, window_flags);
    if Window = nil then
    begin
        SDL_Log(PChar(Format('Couldn''t create window: %s', [SDL_GetError])));
        Exit;
    end;

    Renderer := SDL_CreateGPURenderer(Device, Window);

    if Renderer = nil then
    begin
        SDL_Log(PChar(Format('Couldn''t create GPU renderer: %s', [SDL_GetError])));
        Exit;
    end;

    if not TTF_Init then
    begin
        SDL_Log(PChar(Format('Couldn''t initialize SDL_ttf: %s', [SDL_GetError])));
        Exit;
    end;

    Font := TTF_OpenFont(Pchar('assets/unifont-17.0.04.otf'), 16);

    TextEngine := TTF_CreateRendererTextEngine(Renderer);
end;

procedure render;
var
    x, y: Integer;
    i: Integer;
    text: PTTF_Text;

begin
    SDL_SetRenderDrawColorFloat(Renderer, 0.2, 0.2, 0.2, 1.0);
    SDL_RenderClear(Renderer);

    text := TTF_CreateText(TextEngine, Font, PChar('foo bar baz'#10#10'ちりも積もれば山となる'#10#10'千里之行，始於足下'#10#10'لا يهم كم أنت بطيئ طالما أنك لن تتوقف'), 0);
    TTF_DrawRendererText(text, 10, 10);
    TTF_DestroyText(text);

    SDL_RenderPresent(Renderer);
end;

var
    quitting : boolean = false;

procedure mainloop;
var
    event: TSDL_Event;
begin
    while not quitting do
    begin
        while (SDL_PollEvent(@event)) do
        begin
            if event._type = SDL_EVENT_QUIT then begin
                quitting := true;
            end;
            if event._type = SDL_EVENT_KEY_DOWN then begin
                if event.key.key = SDLK_ESCAPE then begin
                    quitting := true;
                end;
            end;
        end;

        render;
    end;
end;

begin
    init;

    mainloop;

    TTF_CloseFont(Font);
    TTF_Quit();

    SDL_DestroyRenderer(Renderer);
    SDL_ReleaseWindowFromGPUDevice(Device, Window);
    SDL_DestroyWindow(Window);
    SDL_DestroyGPUDevice(Device);
    SDL_Quit();
end.
