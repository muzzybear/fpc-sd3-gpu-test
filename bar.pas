{$mode objfpc}
{$H+}
{$modeswitch ADVANCEDRECORDS}

{$UNITPATH 3rdparty/Lazarus-SDL-3.0-Packages-and-Examples/packages/}

uses
    Sysutils, SDL3, SDL3_Image, ctypes, matrix, Matrix3DMath, Math;

const
    screen_width = 640;
    screen_height = 480;
    window_title = 'yatta';
    window_flags = 0; //SDL_WINDOW_VULKAN;

var
    Window: PSDL_Window = nil;
    Device: PSDL_GPUDevice = nil;
    Renderer: PSDL_Renderer = nil;

    rs_foo: PSDL_GPURenderState = nil;
    bear: PSDL_Texture = nil;

function loadshader(name: String; stage_: TSDL_GPUShaderStage; numSamplers: Integer; numUniforms: Integer) : PSDL_GPUShader;
var
    data: Pointer;
    datasize: csize_t = 0;
    formats: TSDL_GPUShaderFormat;
    shaderinfo: TSDL_GPUShaderCreateInfo;
    shader: PSDL_GPUShader;
begin
    result := nil;

    formats := SDL_GetGPUShaderFormats(Device);
    if formats and SDL_GPU_SHADERFORMAT_SPIRV = 0 then begin
        SDL_Log(PChar('Unrecognized shader backend!'));
        Exit;
    end;

    data := SDL_LoadFile(PChar(Format('%s/%s', [SDL_GetBasePath(), name])), @datasize);
    if data = nil then
    begin
        SDL_Log(PChar(Format('Couldn''t load shader: %s', [SDL_GetError])));
        Exit;
    end;

    shaderinfo := default(TSDL_GPUShaderCreateInfo);
    with shaderinfo do begin
        code := data;
        code_size := datasize;
        entrypoint := Pchar('main');
        format := SDL_GPU_SHADERFORMAT_SPIRV;
        stage := stage_;
        num_samplers := numSamplers;
        num_uniform_buffers := numUniforms;
        num_storage_buffers := 0; // TODO
        num_storage_textures := 0; // TODO
    end;

    shader := SDL_CreateGPUShader(Device, @shaderinfo);
    if shader = nil then begin
        SDL_Log(PChar(Format('Couldn''t create shader: %s', [SDL_GetError])));
        SDL_Free(data);
        Exit;
    end;

    SDL_Free(data);
    result := shader;
end;

// -----

procedure init;
var
    rsinfo : TSDL_GPURenderStateCreateInfo;
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

    rsinfo := Default(TSDL_GPURenderStateCreateInfo);
    with rsinfo do
    begin
        fragment_shader := loadshader('desaturate.frag.spv', SDL_GPU_SHADERSTAGE_FRAGMENT, 1, 1);
    end;

    rs_foo := SDL_CreateGPURenderState(Renderer, @rsinfo);

    bear := IMG_LoadTexture(Renderer, PChar('assets/bear-1024-pexels-jiri-mikolas-7183267.jpg'));
    if bear = nil then
    begin
        SDL_Log(PChar(Format('Couldn''t find bear: %s', [SDL_GetError])));
        Exit;
    end;
end;


type
    TDesaturateParams = packed record
        amount: Single;
    end;

procedure render;
var
    time: Single;
    rect: TSDL_FRect;
    params: TDesaturateParams;

begin
    time := SDL_GetTicks() / 1000.0;

    SDL_SetRenderDrawColorFloat(Renderer, 0.2, 0.2, 0.2, 1.0);
    SDL_RenderClear(Renderer);

    SDL_SetRenderDrawColorFloat(Renderer, 0.2, 0.8, 0.2, 1.0);
    with rect do begin
        x := 20; y:= 30; w := 400; h := 400;
    end;

    params := Default(TDesaturateParams);
    params.amount := 0.5 + sin(time*4)*0.5;
    SDL_SetGPURenderStateFragmentUniforms(rs_foo, 0, @params, sizeof(params));
    SDL_SetGPURenderState(Renderer, rs_foo);
    SDL_RenderTexture(Renderer, bear, nil, @rect);
    SDL_SetGPURenderState(Renderer, nil);

    SDL_SetRenderDrawColorFloat(Renderer, 1.0, 1.0, 1.0, 1.0);
    SDL_RenderDebugText(Renderer, 10, 10, PChar('Testing'));

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

    SDL_DestroyTexture(bear);
    SDL_DestroyGPURenderState(rs_foo);
    SDL_DestroyRenderer(Renderer);
    SDL_ReleaseWindowFromGPUDevice(Device, Window);
    SDL_DestroyWindow(Window);
    SDL_DestroyGPUDevice(Device);
    SDL_Quit();
end.
