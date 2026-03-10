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

    lightmap: PSDL_Texture = nil;
    rs_lightgradient: PSDL_GPURenderState = nil;
    lightgradient_hack: PSDL_Texture = nil;

    groundtransitions: PSDL_Texture = nil;

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

var
    map: array[0..50,0..50] of integer;

procedure initmap;
var
    x,y : Integer;
    i : Integer;
begin
    // water border top and bottom
    for y in [low(map), low(map)+1, high(map)-1, high(map)] do
        for x:=low(map[y]) to high(map[y]) do
            map[y][x] := 3;

    for y:=low(map)+2 to high(map)-2 do
    begin
        // water border left and right
        for x in [low(map[y]), low(map[y])+1, high(map[y])-1, high(map[y])] do
            map[y][x] := 3;

        for x:=low(map[y])+2 to high(map[y])-2 do
            map[y][x] := Random(4);
    end;

    // randomly propagate cells around to make more continuous areas
    for i:=0 to 3500 do
    begin
        y:=randomRange(low(map)+2, high(map)-2);
        x:=randomRange(low(map[y])+2, high(map[y])-2);
        map[y][x] := map[y+randomRange(-2,+2)][x+randomRange(-2,+2)];
        map[y+randomRange(-1,+1)][x+randomRange(-1,+1)] := map[y][x];
        map[y+randomRange(-1,+1)][x+randomRange(-1,+1)] := map[y][x];
    end;
end;

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

    lightmap := SDL_CreateTexture(Renderer, SDL_PIXELFORMAT_RGBA8888, SDL_TEXTUREACCESS_TARGET, screen_width, screen_height);
    if lightmap = nil then
    begin
        SDL_Log(PChar(Format('Couldn''t create lightmap texture: %s', [SDL_GetError])));
        Exit;
    end;
    SDL_SetTextureBlendMode(lightmap, SDL_BLENDMODE_MOD);

    rsinfo := Default(TSDL_GPURenderStateCreateInfo);
    with rsinfo do
    begin
        fragment_shader := loadshader('light_gradient.frag.spv', SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 0);
    end;

    rs_lightgradient := SDL_CreateGPURenderState(Renderer, @rsinfo);

    // we need a dummy texture or SDL nukes the UVs even when using SDL_RenderGeometry
    lightgradient_hack := SDL_CreateTexture(Renderer, SDL_PIXELFORMAT_RGBA8888, SDL_TEXTUREACCESS_STATIC, 1, 1);
    SDL_SetTextureBlendMode(lightgradient_hack, SDL_BLENDMODE_ADD);
    // TODO blendmode should maybe be maximum instead
    //SDL_ComposeCustomBlendMode();

    // FIXME check creation

    groundtransitions := IMG_LoadTexture(Renderer, PChar('assets/tileset-groundtransitions.png'));
    if groundtransitions = nil then
    begin
        SDL_Log(PChar(Format('Couldn''t find tileset: %s', [SDL_GetError])));
        Exit;
    end;

    initmap;
end;

procedure renderlights;
var
    rect: TSDL_FRect;
begin
    SDL_SetRenderTarget(Renderer, lightmap);
    SDL_SetRenderDrawColorFloat(Renderer, 0.2,0.2,0.2, 1.0);
    SDL_RenderClear(Renderer);

    SDL_SetRenderDrawColorFloat(Renderer, 1.0, 1.0, 1.0, 1.0);
    SDL_SetGPURenderState(Renderer, rs_lightgradient);
    rect.x := 50; rect.y := 50; rect.w := 300; rect.h := 300;
    SDL_RenderTexture(Renderer, lightgradient_hack, nil, @rect);
    rect.x := 250; rect.y := 100; rect.w := 300; rect.h := 300;
    SDL_RenderTexture(Renderer, lightgradient_hack, nil, @rect);
    SDL_SetGPURenderState(Renderer, nil);

    SDL_SetRenderTarget(Renderer, nil);
end;

procedure render;
var
    src, dst: TSDL_FRect;
    i, j: Integer;
    a,b,c,d,idx: Integer;

begin
    SDL_SetRenderDrawColorFloat(Renderer, 0.2, 0.2, 0.2, 1.0);
    SDL_RenderClear(Renderer);

    src.w := 32; src.h := 32;
    dst.w := 32; dst.h := 32;

    SDL_SetRenderDrawColorFloat(Renderer, 0.2, 0.8, 0.2, 1.0);
    for j:=0 to 14 do begin
        for i:=0 to 19 do begin
            a := map[j][i];
            b := map[j][i+1];
            c := map[j+1][i];
            d := map[j+1][i+1];
            idx := a*4*4*4 + b*4*4 + c*4 + d;
            src.x := (idx mod 16)*32;
            src.y := (idx div 16)*32;
            dst.x := 32*i;
            dst.y := 32*j;
            SDL_RenderTexture(Renderer, groundtransitions, @src, @dst);
        end;
    end;

    renderlights;
    SDL_RenderTexture(Renderer, lightmap, nil, nil);

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

    SDL_DestroyTexture(lightmap);
    SDL_DestroyTexture(groundtransitions);
    SDL_DestroyGPURenderState(rs_lightgradient);
    SDL_DestroyRenderer(Renderer);
    SDL_ReleaseWindowFromGPUDevice(Device, Window);
    SDL_DestroyWindow(Window);
    SDL_DestroyGPUDevice(Device);
    SDL_Quit();
end.
