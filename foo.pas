{$mode objfpc}
{$H+}

{$UNITPATH 3rdparty/SDL3-for-Pascal/units/}

uses
    Sysutils, SDL3, ctypes;

const
    screen_width = 640;
    screen_height = 480;
    window_title = 'yatta';
    window_flags = 0; //SDL_WINDOW_VULKAN;

var
    Window: PSDL_Window = nil;
    Device: PSDL_GPUDevice = nil;
    Pipeline: PSDL_GPUGraphicsPipeline = nil;

function loadshader(name: String; stage_: TSDL_GPUShaderStage) : PSDL_GPUShader;
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

    Fillchar(shaderinfo, SizeOf(shaderinfo), 0);
    with shaderinfo do begin
        code := data;
        code_size := datasize;
        entrypoint := Pchar('main');
        format := SDL_GPU_SHADERFORMAT_SPIRV;
        stage := stage_;
        num_samplers := 0; // TODO
        num_uniform_buffers := 0; // TODO
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

procedure CreatePipeline;
var
    vsh, fsh: PSDL_GPUShader;
    pipelineinfo: TSDL_GPUGraphicsPipelineCreateInfo;
    targetdesc: TSDL_GPUColorTargetDescription;
begin
    vsh := loadshader('fullscreen.vert.spv', SDL_GPU_SHADERSTAGE_VERTEX);
    if vsh = nil then begin
        SDL_Log(PChar('Couldn''t create vertex shader!'));
        Exit;
    end;
    fsh := loadshader('solidcolor.frag.spv', SDL_GPU_SHADERSTAGE_FRAGMENT);
    if fsh = nil then begin
        SDL_Log(PChar('Couldn''t create fragment shader!'));
        Exit;
    end;

    Fillchar(targetdesc, SizeOf(targetdesc), 0);
    with targetdesc do begin
        format := SDL_GetGPUSwapchainTextureFormat(Device, Window);
    end;

    Fillchar(pipelineinfo, SizeOf(pipelineinfo), 0);
    with pipelineinfo do begin
        primitive_type := SDL_GPU_PRIMITIVETYPE_TRIANGLELIST;
        vertex_shader := vsh;
        fragment_shader := fsh;
        with target_info do begin
            num_color_targets := 1;
            color_target_descriptions := @targetdesc;
        end;
        rasterizer_state.fill_mode := SDL_GPU_FILLMODE_FILL;
    end;

    Pipeline := SDL_CreateGPUGraphicsPipeline(Device, @pipelineinfo);

    // pipeline holds shaders so we don't need to
    SDL_ReleaseGPUShader(Device, vsh);
    SDL_ReleaseGPUShader(Device, fsh);

    if Pipeline = nil then begin
        SDL_Log(PChar(Format('Couldn''t create rendering pipeline: %s', [SDL_GetError])));
        Exit;
    end;
end;

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

    if not SDL_ClaimWindowForGPUDevice(Device, Window) then
    begin
        SDL_Log(PChar(Format('Couldn''t claim window for GPU: %s', [SDL_GetError])));
        Exit;
    end;

    CreatePipeline;
end;


(*
type
    TVertex = record
        x,y,z: Single;
    end;
*)

procedure render;
var
    time: Single;
    cmdbuf: PSDL_GPUCommandBuffer;
    swapchaintex: PSDL_GPUTexture;
    colortargetinfo: TSDL_GPUColorTargetInfo;
    renderpass: PSDL_GPURenderPass;

begin
    time := SDL_GetTicks() / 1000.0;

    cmdbuf := SDL_AcquireGPUCommandBuffer(Device);
    if cmdbuf = nil then begin
        SDL_Log(PChar(Format('SDL_AcquireGPUCommandBuffer failed: %s', [SDL_GetError])));
        Exit;
    end;

    if not SDL_WaitAndAcquireGPUSwapchainTexture(cmdbuf, Window, @swapchaintex, nil, nil) then
    begin
        SDL_Log(PChar(Format('SDL_WaitAndAcquireGPUSwapchainTexture failed: %s', [SDL_GetError])));
        Exit;
    end;

    if swapchaintex = nil then
    begin
        SDL_SubmitGPUCommandBuffer(cmdbuf);
        Exit;
    end;

    Fillchar(colortargetinfo, SizeOf(colortargetinfo), 0);
    with colortargetinfo do begin
        texture := swapchaintex;
        with clear_color do begin
            r := 0;
            g := 0;
            b := (sin(time)+1)/2.0;
            a := 1.0;
        end;
        load_op := SDL_GPU_LOADOP_CLEAR;
        store_op := SDL_GPU_STOREOP_STORE;
    end;

    renderpass := SDL_BeginGPURenderPass(cmdbuf, @colortargetinfo, 1, nil);

    SDL_BindGPUGraphicsPipeline(renderpass, Pipeline);
    SDL_DrawGPUPrimitives(renderPass, 3, 1, 0, 0); // one fullscreen triangle
    SDL_EndGPURenderPass(renderpass);

    SDL_SubmitGPUCommandBuffer(cmdbuf);
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
            if event.type_ = SDL_EVENT_QUIT then begin
                quitting := true;
            end;
            if event.type_ = SDL_EVENT_KEY_DOWN then begin
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

    SDL_ReleaseGPUGraphicsPipeline(Device, Pipeline);
    SDL_ReleaseWindowFromGPUDevice(Device, Window);
    SDL_DestroyWindow(Window);
    SDL_DestroyGPUDevice(Device);
    SDL_Quit();
end.
