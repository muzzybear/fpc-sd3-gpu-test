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

    //lightmap: PSDL_Texture = nil;

    rs_foo: PSDL_GPURenderState = nil;


function loadshader(name: String; stage_: TSDL_GPUShaderStage; numSamplers: Integer; numUniforms: Integer; numBuffers: Integer) : PSDL_GPUShader;
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
        num_storage_buffers := 0; //numBuffers; // TODO wait for SDL3.6 to be released
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
    map: array[0..127,0..127] of integer;

procedure initmap;
var
    x,y : Integer;
begin
    for y:=low(map) to high(map) do
    begin
        for x:=low(map[y]) to high(map[y]) do
        begin
            if (y=low(map)) or (y=high(map)) or (x=low(map[y])) or (x=high(map[y])) then
            begin
                map[y][x] := 1;
            end
            else if (y mod 2 = 0) and (x mod 2 = 0) then
            begin
                map[y][x] := 2;
            end
            else
            begin
                map[y][x] := 0;
            end;
        end;
    end;
end;

function CreateGPUBuffer(size:Integer; usage:TSDL_GPUBufferUsageFlags): PSDL_GPUBuffer;
var
    info: TSDL_GPUBufferCreateInfo;
begin
    info := default(TSDL_GPUBufferCreateInfo);
    info.usage := usage;
    info.size := size;
    result := SDL_CreateGPUBuffer(Device, @info);
end;

procedure upload(srcdata: Pointer; dstbuffer: PSDL_GPUBuffer; size_: Integer);
var
    tb_info: TSDL_GPUTransferBufferCreateInfo;
    transferbuffer: PSDL_GPUTransferBuffer;
    cmdbuf: PSDL_GPUCommandBuffer;
    copypass: PSDL_GPUCopyPass;
    src: TSDL_GPUTransferBufferLocation;
    dst: TSDL_GPUBufferRegion;
    data: Pointer;
begin
    tb_info := default(TSDL_GPUTransferBufferCreateInfo);
    tb_info.usage := SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD;
    tb_info.size := size_;
    transferbuffer := SDL_CreateGPUTransferBuffer(device, @tb_info);

    data := SDL_MapGPUTransferBuffer(Device, transferbuffer, false);
    Move(srcdata^, data^, size_);
    SDL_UnmapGPUTransferBuffer(Device, transferbuffer);

    cmdbuf := SDL_AcquireGPUCommandBuffer(Device);
    copypass := SDL_BeginGPUCopyPass(cmdbuf);
    src := default(TSDL_GPUTransferBufferLocation);
    src.transfer_buffer := transferbuffer;
    dst := default(TSDL_GPUBufferRegion);
    dst.buffer := dstbuffer;
    dst.offset := 0;
    dst.size := size_;

    SDL_UploadToGPUBuffer(copypass, @src, @dst, true);
    SDL_EndGPUCopyPass(copypass);
    SDL_SubmitGPUCommandBuffer(cmdbuf);

    SDL_ReleaseGPUTransferBuffer(Device, transferbuffer);
end;

var
    mapbuffer: PSDL_GPUBuffer = nil;

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
        fragment_shader := loadshader('asdf.frag.spv', SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 0, 1);
    end;

    rs_foo := SDL_CreateGPURenderState(Renderer, @rsinfo);

    initmap;
    mapbuffer := CreateGPUBuffer(128*128*4, SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ);
    upload(@map, mapbuffer, 128*128*4);
end;

procedure render;
begin
    SDL_SetRenderDrawColorFloat(Renderer, 0.2, 0.2, 0.2, 1.0);
    SDL_RenderClear(Renderer);

    SDL_SetGPURenderState(Renderer, rs_foo);
    //SDL_SetGPURenderStateStorageBuffers(rs_foo, 1, @mapbuffer); // OOPS requires SDL 3.6.0
    SDL_RenderFillRect(Renderer, nil);
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

    SDL_DestroyGPURenderState(rs_foo);
    SDL_DestroyRenderer(Renderer);
    SDL_ReleaseWindowFromGPUDevice(Device, Window);
    SDL_DestroyWindow(Window);
    SDL_DestroyGPUDevice(Device);
    SDL_Quit();
end.
