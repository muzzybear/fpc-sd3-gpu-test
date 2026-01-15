{$mode objfpc}
{$H+}
{$modeswitch ADVANCEDRECORDS}

{$UNITPATH 3rdparty/SDL3-for-Pascal/units/}

uses
    Sysutils, SDL3, ctypes, matrix, Math;

const
    screen_width = 640;
    screen_height = 480;
    window_title = 'yatta';
    window_flags = 0; //SDL_WINDOW_VULKAN;

var
    Window: PSDL_Window = nil;
    Device: PSDL_GPUDevice = nil;

function loadshader(name: String; stage_: TSDL_GPUShaderStage; numUniforms: Integer) : PSDL_GPUShader;
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
        num_samplers := 0; // TODO
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

type
    TVertex3D = packed record
        x,y,z: Single; // vec3
        r,g,b: Single; // vec3
    end;
    PVertex3D = ^TVertex3D;

type
    TPipeline = class
    public
        handle: PSDL_GPUGraphicsPipeline;
        constructor Create(handle_: PSDL_GPUGraphicsPipeline);
        destructor Destroy;
    end;

    TPipelineBuilder = class
    public
        hasDepth : Boolean;
        //vertexBuffers : array of ...
        numVertexUniforms : Integer;
        numFragmentUniforms : Integer;
        fragmentShaderName : String;
        vertexShaderName : String;
        vertexPitch : Integer;
        vertexAttributes : array of TSDL_GPUVertexAttribute;
        function CreatePipeline : TPipeline;
    end;

    // TODO wrapper class for shaders

destructor TPipeline.Destroy;
begin
    SDL_ReleaseGPUGraphicsPipeline(Device, handle);
end;

constructor TPipeline.Create(handle_: PSDL_GPUGraphicsPipeline);
begin
    handle := handle_;
end;

function TPipelineBuilder.CreatePipeline : TPipeline;
var
    vsh, fsh: PSDL_GPUShader;
    pipelineinfo: TSDL_GPUGraphicsPipelineCreateInfo;
    targetdesc: TSDL_GPUColorTargetDescription;
    Pipeline: PSDL_GPUGraphicsPipeline = nil;
    vbdesc: TSDL_GPUVertexBufferDescription;
begin
    vsh := loadshader(vertexShaderName+'.vert.spv', SDL_GPU_SHADERSTAGE_VERTEX, numVertexUniforms);
    if vsh = nil then begin
        SDL_Log(PChar('Couldn''t create vertex shader!'));
        Exit;
    end;
    fsh := loadshader(fragmentShaderName+'.frag.spv', SDL_GPU_SHADERSTAGE_FRAGMENT, numFragmentUniforms);
    if fsh = nil then begin
        SDL_Log(PChar('Couldn''t create fragment shader!'));
        SDL_ReleaseGPUShader(Device, vsh);
        Exit;
    end;

    targetdesc := default(TSDL_GPUColorTargetDescription);
    with targetdesc do begin
        format := SDL_GetGPUSwapchainTextureFormat(Device, Window);
    end;

    vbdesc := default(TSDL_GPUVertexBufferDescription);
    with vbdesc do begin
        slot := 0;
        pitch := vertexPitch;
        input_rate := SDL_GPU_VERTEXINPUTRATE_VERTEX;
    end;

    pipelineinfo := default(TSDL_GPUGraphicsPipelineCreateInfo);
    with pipelineinfo do begin
        primitive_type := SDL_GPU_PRIMITIVETYPE_TRIANGLELIST;
        with rasterizer_state do begin
            fill_mode := SDL_GPU_FILLMODE_FILL;
            //cull_mode := SDL_GPU_CULLMODE_BACK;
        end;
        if hasDepth then with depth_stencil_state do begin
            enable_depth_test := true;
            enable_depth_write := true;
            compare_op := SDL_GPU_COMPAREOP_LESS;
        end;

        vertex_shader := vsh;
        fragment_shader := fsh;
        with target_info do begin
            num_color_targets := 1;
            color_target_descriptions := @targetdesc;
            if hasDepth then begin
                has_depth_stencil_target := true;
                depth_stencil_format := SDL_GPU_TEXTUREFORMAT_D16_UNORM;
            end;
        end;
        // TODO vertex layouts

        with vertex_input_state do begin
            vertex_buffer_descriptions := nil;
            num_vertex_buffers := 0;
            vertex_attributes := nil;
            num_vertex_attributes := Length(vertexAttributes);
            if num_vertex_attributes > 0 then begin
                vertex_attributes := @vertexAttributes[0];
                num_vertex_buffers := 1;
                vertex_buffer_descriptions := @vbdesc;
            end;
        end;
    end;

    Pipeline := SDL_CreateGPUGraphicsPipeline(Device, @pipelineinfo);

    // pipeline holds shaders so we don't need to
    SDL_ReleaseGPUShader(Device, vsh);
    SDL_ReleaseGPUShader(Device, fsh);

    if Pipeline = nil then begin
        SDL_Log(PChar(Format('Couldn''t create rendering pipeline: %s', [SDL_GetError])));
        Exit;
    end;

    result := TPipeline.Create(Pipeline);
end;

// -----

type
    TGPUTexture = class
    public
        handle: PSDL_GPUTexture;
        constructor Create(width_, height_: Integer; format_: TSDL_GPUTextureFormat; usage_: TSDL_GPUTextureUsageFlags);
        destructor Destroy;
    end;

constructor TGPUTexture.Create(width_, height_: Integer; format_: TSDL_GPUTextureFormat; usage_: TSDL_GPUTextureUsageFlags);
var
    info: TSDL_GPUTextureCreateInfo;
begin
    info := default(TSDL_GPUTextureCreateInfo);
    with info do begin
        type_ := SDL_GPU_TEXTURETYPE_2D;
        sample_count := SDL_GPU_SAMPLECOUNT_1;
        width := width_;
        height := height_;
        format := format_;
        usage := usage_;
        layer_count_or_depth := 1;
        num_levels := 1;
    end;
    handle := SDL_CreateGPUTexture(Device, @info);
end;

destructor TGPUTexture.Destroy;
begin
    SDL_ReleaseGPUTexture(Device, handle);
end;

// -----

function CreateVertexBuffer: PSDL_GPUBuffer;
var
    info: TSDL_GPUBufferCreateInfo;
    buffer: PSDL_GPUBuffer = nil;
begin
    info := default(TSDL_GPUBufferCreateInfo);
    with info do begin
        usage := SDL_GPU_BUFFERUSAGE_VERTEX;
        size := SizeOf(TVertex3D) * 3*12;
    end;

    buffer := SDL_CreateGPUBuffer(Device, @info);

    result := buffer;
end;

var
    bg_pipeline, fg_pipeline: TPipeline;
    VertexBuffer: PSDL_GPUBuffer = nil;
    DepthBuffer : TGPUTexture;

procedure init;
const
    fg_attrs : array of TSDL_GPUVertexAttribute =
    (
        (location: 0; buffer_slot: 0; format: SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3; offset: 0),
        (location: 1; buffer_slot: 0; format: SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3; offset: 4*3)
    );
var
    cmdbuf: PSDL_GPUCommandBuffer;
    copypass: PSDL_GPUCopyPass;
    src: TSDL_GPUTransferBufferLocation;
    dst: TSDL_GPUBufferRegion;
    VertexTransferBuffer: PSDL_GPUTransferBuffer;
    vtb_info: TSDL_GPUTransferBufferCreateInfo;
    data: PVertex3D;
    i: Integer;
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

    with TPipelineBuilder.Create do begin
        vertexShaderName := 'fullscreen';
        fragmentShaderName := 'uv_out';
        bg_pipeline := CreatePipeline;
        Destroy;
    end;

    with TPipelineBuilder.Create do begin
        vertexShaderName := 'simple_xyz_rgb';
        fragmentShaderName := 'solidcolor';
        vertexAttributes := fg_attrs;
        vertexPitch := sizeof(TVertex3D);
        numVertexUniforms := 1;
        hasDepth := true;
        fg_pipeline := CreatePipeline;
        Destroy;
    end;

    VertexBuffer := CreateVertexBuffer;

    vtb_info := default(TSDL_GPUTransferBufferCreateInfo);
    with vtb_info do begin
        usage := SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD;
        size := Sizeof(TVertex3D)*3;
    end;
    VertexTransferBuffer := SDL_CreateGPUTransferBuffer(device, @vtb_info);

    data := SDL_MapGPUTransferBuffer(Device, VertexTransferBuffer, false);
    with data[0] do begin
        x:=-0.5; y:=-0.5; z:=0;
        r:=1; g:=0; b:=0;
    end;
    with data[1] do begin
        x:=0.5; y:=-0.5; z:=0;
        r:=1; g:=0; b:=0;
    end;
    with data[2] do begin
        x:=0; y:=0.5; z:=0;
        r:=1; g:=1; b:=1;
    end;
    for i:=0 to 11 do begin
        with data[i*3] do begin
            x:=sin(i*2*PI/12);
            y:=cos(i*2*PI/12);
            z:=0.3;
            r:=1; g:=0; b:=0;
        end;
        with data[i*3+1] do begin
            x:=sin(i*2*PI/12);
            y:=cos(i*2*PI/12);
            z:=-0.3;
            r:=1; g:=1; b:=0;
        end;
        with data[i*3+2] do begin
            x:=sin((i+0.8)*2*PI/12);
            y:=cos((i+0.8)*2*PI/12);
            z:=0;
            r:=1; g:=1; b:=1;
        end;
    end;
    SDL_UnmapGPUTransferBuffer(Device, VertexTransferBuffer);

    cmdbuf := SDL_AcquireGPUCommandBuffer(Device);
    copypass := SDL_BeginGPUCopyPass(cmdbuf);
    src := default(TSDL_GPUTransferBufferLocation);
    src.transfer_buffer := VertexTransferBuffer;
    dst := default(TSDL_GPUBufferRegion);
    with dst do begin
        buffer := VertexBuffer;
        offset := 0;
        size := SizeOf(TVertex3D)*3*12;
    end;

    SDL_UploadToGPUBuffer(copypass, @src, @dst, true);
    SDL_EndGPUCopyPass(copypass);
    SDL_SubmitGPUCommandBuffer(cmdbuf);

    DepthBuffer := TGPUTexture.Create(screen_width, screen_height, SDL_GPU_TEXTUREFORMAT_D16_UNORM, SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET);
end;


function rotateX(angle: Single) : TMatrix4_single;
var
    c,s: Single;
begin
    c := cos(angle);
    s := sin(angle);
    result.init(
                   1, 0, 0, 0,
                   0, c,-s, 0,
                   0, s, c, 0,
                   0, 0, 0, 1
               );
end;

function rotateY(angle: Single) : TMatrix4_single;
var
    c,s: Single;
begin
    c := cos(angle);
    s := sin(angle);
    result.init(
                   c, 0, s, 0,
                   0, 1, 0, 0,
                  -s, 0, c, 0,
                   0, 0, 0, 1
               );
end;

function rotateZ(angle: Single) : TMatrix4_single;
var
    c,s: Single;
begin
    c := cos(angle);
    s := sin(angle);
    result.init(
                   c,-s, 0, 0,
                   s, c, 0, 0,
                   0, 0, 1, 0,
                   0, 0, 0, 1
               );
end;

function translate(X,Y,Z: Single) : TMatrix4_single;
begin
    result.init(
                   1,0,0,X,
                   0,1,0,Y,
                   0,0,1,Z,
                   0,0,0,1
               );
end;

function perspective(fovy, aspect, near, far: Single): TMatrix4_single;
var
    f: Single;
    k: Single;
begin
    f := 1.0 / tan(fovy *0.5);
    k := far/(far-near);
    result.init(
                   f/aspect, 0, 0, 0,
                   0, f, 0, 0,
                   0, 0, k, -near*k,
                   0, 0, 1, 0
               );
end;

procedure render;
var
    time: Single;
    cmdbuf: PSDL_GPUCommandBuffer;
    swapchaintex: PSDL_GPUTexture;
    colortargetinfo: TSDL_GPUColorTargetInfo;
    depthtargetinfo: TSDL_GPUDepthStencilTargetInfo;
    renderpass: PSDL_GPURenderPass;
    binding: TSDL_GPUBufferBinding;
    transform: TMatrix4_single;

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

    colortargetinfo := default(TSDL_GPUColorTargetInfo);
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

    depthtargetinfo := default(TSDL_GPUDepthStencilTargetInfo);
    with depthtargetinfo do begin
        texture := DepthBuffer.handle;
        load_op := SDL_GPU_LOADOP_CLEAR;
        store_op := SDL_GPU_STOREOP_STORE;
        stencil_load_op := SDL_GPU_LOADOP_DONT_CARE;
        stencil_store_op := SDL_GPU_STOREOP_DONT_CARE;
        clear_depth := 1;
        cycle := true;
    end;

    binding := default(TSDL_GPUBufferBinding);
    with binding do begin
        buffer := VertexBuffer;
    end;

    // render
    renderpass := SDL_BeginGPURenderPass(cmdbuf, @colortargetinfo, 1, @depthtargetinfo);

    SDL_BindGPUGraphicsPipeline(renderpass, bg_pipeline.handle);
    SDL_DrawGPUPrimitives(renderPass, 3, 1, 0, 0); // one fullscreen triangle

    SDL_BindGPUGraphicsPipeline(renderpass, fg_pipeline.handle);
    SDL_BindGPUVertexBuffers(renderpass, 0, @binding, 1);
    transform.init_identity;
    transform := rotateZ(time*1.7) * transform;
    transform := rotateY(time) * transform;
    transform := translate(0,0,5) * transform;
    transform := perspective(DegToRad(60), screen_height/screen_width, 0.1, 10) * transform;
    // GPU wants column-major, but TMatrix4_single is row-major
    transform := transform.transpose;
    SDL_PushGPUVertexUniformData(cmdbuf, 0, @transform.data, SizeOf(transform.data));
    SDL_DrawGPUPrimitives(renderPass, 3*12, 1, 0, 0); // one triangle

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

    bg_pipeline.Destroy;
    fg_pipeline.Destroy;
    DepthBuffer.Destroy;
    SDL_ReleaseWindowFromGPUDevice(Device, Window);
    SDL_DestroyWindow(Window);
    SDL_DestroyGPUDevice(Device);
    SDL_Quit();
end.
