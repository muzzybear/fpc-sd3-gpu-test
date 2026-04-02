{$mode objfpc}
{$H+}
{$modeswitch ADVANCEDRECORDS}

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
        numFragmentSamplers : Integer;
        fragmentShaderName : String;
        vertexShaderName : String;
        vertexPitch : Integer;
        vertexAttributes : array of TSDL_GPUVertexAttribute;
        function CreatePipeline : TPipeline;
    end;

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
    vsh := loadshader(vertexShaderName+'.vert.spv', SDL_GPU_SHADERSTAGE_VERTEX, 0, numVertexUniforms);
    if vsh = nil then begin
        SDL_Log(PChar('Couldn''t create vertex shader!'));
        Exit;
    end;
    fsh := loadshader(fragmentShaderName+'.frag.spv', SDL_GPU_SHADERSTAGE_FRAGMENT, numFragmentSamplers, numFragmentUniforms);
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
        format: TSDL_GPUTextureFormat;
        constructor Create(width_, height_: Integer; format_: TSDL_GPUTextureFormat; usage_: TSDL_GPUTextureUsageFlags);
        destructor Destroy;

        procedure UploadToGPU(surface: PSDL_Surface);
    end;

constructor TGPUTexture.Create(width_, height_: Integer; format_: TSDL_GPUTextureFormat; usage_: TSDL_GPUTextureUsageFlags);
var
    info: TSDL_GPUTextureCreateInfo;
begin
    format := format_;
    info := default(TSDL_GPUTextureCreateInfo);
    with info do begin
        _type := SDL_GPU_TEXTURETYPE_2D;
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

procedure TGPUTexture.UploadToGPU(surface: PSDL_Surface);
var
    cmdbuf: PSDL_GPUCommandBuffer;
    copypass: PSDL_GPUCopyPass;
    srcbuf: PSDL_GPUTransferBuffer;
    bufinfo: TSDL_GPUTransferBufferCreateInfo;
    src: TSDL_GPUTextureTransferInfo;
    dst: TSDL_GPUTextureRegion;
    tmp: Boolean = false;
    gpuformat: TSDL_PixelFormat;
    data: Pointer;

begin
    cmdbuf := SDL_AcquireGPUCommandBuffer(Device);
    copypass := SDL_BeginGPUCopyPass(cmdbuf);

    gpuformat := SDL_GetPixelFormatFromGPUTextureFormat(format);
    if surface^.format <> gpuformat then begin
        surface := SDL_ConvertSurface(surface, gpuformat);
        tmp := true;
    end;

    SDL_LockSurface(surface);

    bufinfo := default(TSDL_GPUTransferBufferCreateInfo);
    with bufinfo do begin
        usage := SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD;
        size := surface^.pitch * surface^.h;
    end;
    srcbuf := SDL_CreateGPUTransferBuffer(Device, @bufinfo);

    // copy surface data to transfer buffer
    // TODO consider SDL_ConvertPixels instead
    data := SDL_MapGPUTransferBuffer(Device, srcbuf, false);
    Move(surface^.pixels^, data^, surface^.pitch*surface^.h);
    SDL_UnmapGPUTransferBuffer(Device, srcbuf);

    SDL_UnlockSurface(surface);

    src := Default(TSDL_GPUTextureTransferInfo);
    with src do begin
        transfer_buffer := srcbuf;
        // zero for the rest is fine if data is tightly packed and matches destination region size
    end;

    dst := Default(TSDL_GPUTextureRegion);
    with dst do begin
        texture := handle;
        x := 0; y := 0;
        // TODO validate size
        w := surface^.w; h := surface^.h;
    end;

    SDL_UploadToGPUTexture(copypass, @src, @dst, false);

    SDL_EndGPUCopyPass(copypass);
    SDL_SubmitGPUCommandBuffer(cmdbuf);

    if tmp then begin
        SDL_DestroySurface(surface);
    end;

    SDL_ReleaseGPUTransferBuffer(Device, srcbuf);
end;

// -----

type
    generic TGenericMeshBuilder<T> = class
        vertices: array of T;
        indices: array of Integer;
    public
        function addVertex(v: T) : Integer;
        procedure addIndex(i: Integer);
        procedure addTriangle(v0, v1, v2: T);
        procedure addQuad(v0, v1, v2, v3: T);

        function getVertices: Pointer;
        function numVertices: Integer;
        function getIndices: PInteger;
        function numIndices: Integer;
    end;

function TGenericMeshBuilder.addVertex(v: T) : Integer;
begin
    SetLength(vertices, Length(vertices)+1);
    vertices[Length(vertices)-1] := v;
    Result := Length(vertices)-1;
end;

procedure TGenericMeshBuilder.addIndex(i: Integer);
begin
    if i<0 then i := Length(vertices) + i;
    SetLength(indices, Length(indices)+1);
    indices[Length(indices)-1] := i;
end;

procedure TGenericMeshBuilder.addTriangle(v0, v1, v2: T);
begin
    addIndex(addVertex(v0));
    addIndex(addVertex(v1));
    addIndex(addVertex(v2));
end;

procedure TGenericMeshBuilder.addQuad(v0, v1, v2, v3: T);
begin
    // vertices ordered in Z shape
    addVertex(v0);
    addVertex(v1);
    addVertex(v2);
    addVertex(v3);
    addIndex(-4);
    addIndex(-3);
    addIndex(-2);
    addIndex(-3);
    addIndex(-1);
    addIndex(-2);
end;

function TGenericMeshBuilder.getVertices: Pointer;
begin
    Result := @vertices[0];
end;

function TGenericMeshBuilder.numVertices: Integer;
begin
    Result := Length(vertices);
end;

function TGenericMeshBuilder.getIndices: PInteger;
begin
    Result := @indices[0];
end;

function TGenericMeshBuilder.numIndices: Integer;
begin
    Result := Length(indices);
end;

type
    TVertex3D = packed record
        x,y,z: Single; // vec3
        r,g,b: Single; // vec3
        u,v: Single; // vec2
    end;
    PVertex3D = ^TVertex3D;

    TMeshBuilder = specialize TGenericMeshBuilder<TVertex3D>;

    TMesh = record
        vb: PSDL_GPUBuffer;
        ib: PSDL_GPUBuffer;
        numVertices: Integer;
        numIndices: Integer;
    end;
    PMesh = ^TMesh;

function CreateGPUBuffer(usage: TSDL_GPUBufferUsageFlags; size: Integer): PSDL_GPUBuffer;
var
    info: TSDL_GPUBufferCreateInfo;
begin
    info := default(TSDL_GPUBufferCreateInfo);
    info.usage := usage;
    info.size := size;

    result := SDL_CreateGPUBuffer(Device, @info);
end;

procedure rebuildMesh(mesh: PMesh; mb: TMeshBuilder);
var
    cmdbuf: PSDL_GPUCommandBuffer;
    copypass: PSDL_GPUCopyPass;
    src: TSDL_GPUTransferBufferLocation;
    dst: TSDL_GPUBufferRegion;
    vtb, itb: PSDL_GPUTransferBuffer;
    vtb_info, itb_info: TSDL_GPUTransferBufferCreateInfo;
    data: Pointer;

begin
    assert(mesh <> nil);
    assert(mb.numVertices <> 0);

    if mesh^.vb <> nil then SDL_ReleaseGPUBuffer(Device, mesh^.vb);
    if mesh^.ib <> nil then SDL_ReleaseGPUBuffer(Device, mesh^.ib);
    mesh^ := Default(TMesh);

    // prepare vertices for upload
    vtb_info := default(TSDL_GPUTransferBufferCreateInfo);
    with vtb_info do begin
        usage := SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD;
        size := sizeof(TVertex3D)*mb.numVertices;
    end;
    vtb := SDL_CreateGPUTransferBuffer(Device, @vtb_info);

    data := SDL_MapGPUTransferBuffer(Device, vtb, false);
    Move(mb.getVertices^, data^, sizeof(TVertex3D)*mb.numVertices);
    SDL_UnmapGPUTransferBuffer(Device, vtb);

    // prepare indices for upload
    itb_info := default(TSDL_GPUTransferBufferCreateInfo);
    with itb_info do begin
        usage := SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD;
        size := sizeof(Integer)*mb.numIndices;
    end;
    itb := SDL_CreateGPUTransferBuffer(Device, @itb_info);

    data := SDL_MapGPUTransferBuffer(Device, itb, false);
    Move(mb.getIndices^, data^, sizeof(Integer)*mb.numIndices);
    SDL_UnmapGPUTransferBuffer(Device, itb);

    mesh^.vb := CreateGPUBuffer(SDL_GPU_BUFFERUSAGE_VERTEX, SizeOf(TVertex3D) * mb.numVertices);
    mesh^.numVertices := mb.numVertices;

    cmdbuf := SDL_AcquireGPUCommandBuffer(Device);
    copypass := SDL_BeginGPUCopyPass(cmdbuf);

    src := default(TSDL_GPUTransferBufferLocation);
    src.transfer_buffer := vtb;
    dst := default(TSDL_GPUBufferRegion);
    with dst do begin
        buffer := mesh^.vb;
        offset := 0;
        size := SizeOf(TVertex3D) * mb.numVertices;
    end;
    SDL_UploadToGPUBuffer(copypass, @src, @dst, true);

    if mb.numIndices <> 0 then
    begin
        mesh^.ib := CreateGPUBuffer(SDL_GPU_BUFFERUSAGE_INDEX, SizeOf(Integer) * mb.numIndices);
        mesh^.numIndices := mb.numIndices;

        src := default(TSDL_GPUTransferBufferLocation);
        src.transfer_buffer := itb;
        dst := default(TSDL_GPUBufferRegion);
        with dst do begin
            buffer := mesh^.ib;
            offset := 0;
            size := SizeOf(Integer) * mb.numIndices;
        end;
        SDL_UploadToGPUBuffer(copypass, @src, @dst, true);
    end;

    SDL_EndGPUCopyPass(copypass);
    SDL_SubmitGPUCommandBuffer(cmdbuf);

    SDL_ReleaseGPUTransferBuffer(Device, itb);
    SDL_ReleaseGPUTransferBuffer(Device, vtb);
end;

type
    TUVRect = record
        x0,y0,x1,y1 : Single;
    end;

    TTextureAtlas = class
        uvrects: array of TUVRect;
    public
        function getUV(i: Integer): TUVRect;
        function addUV(uv: TUVRect): Integer;
    end;

function TTextureAtlas.getUV(i: Integer): TUVRect;
begin
    // TODO bounds check?
    result := uvrects[i];
end;

function TTextureAtlas.addUV(uv: TUVRect): Integer;
begin
    Result := Length(uvrects);
    SetLength(uvrects, Length(uvrects)+1);
    uvrects[Result] := uv;
end;

var
    atlas: TTextureAtlas;
    atlastex: TGPUTexture;

procedure initatlas;
var
    foo: PSDL_Surface;
const
    BearUV : TUVRect = (x0:0; y0:0; x1:1; y1:1);
    NoseUV : TUVRect = (x0:0.75; y0:0.4; x1:0.95; y1:0.6);

begin
    atlas := TTextureAtlas.Create;
    // TODO load textures, combine them into atlas, generate UV rects

    // IMG_Load
    // SDL_ConvertSurface
    // create atlas surface, upload to gpu
    // SDL_DestroySurface

    foo := IMG_Load(PChar('assets/bear-1024-pexels-jiri-mikolas-7183267.jpg'));
    if foo = nil then
    begin
        SDL_Log(PChar(Format('Couldn''t find bear: %s', [SDL_GetError])));
        Exit;
    end;

    atlastex := TGPUTexture.Create(1024,1024,SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,SDL_GPU_TEXTUREUSAGE_SAMPLER);
    atlastex.UploadToGPU(foo);

    atlas.addUV(BearUV);
    atlas.addUV(NoseUV);
end;

type
    TSurfaceKind = (None, Bear, Nose);

    TMapCell = record
        floorKind, ceilingKind: TSurfaceKind;
        floorHeight, ceilingHeight: Single;
    end;
    PMapCell = ^TMapCell;

    TMapGrid = class
    public
        width, height: Integer;
        cells: array of array of TMapCell;

        constructor Create(w, h: Integer);
    end;

constructor TMapGrid.Create(w, h: Integer);
var
    i: Integer;
begin
    width := w;
    height := h;
    SetLength(cells, height);
    for i:=0 to height-1 do
    begin
        SetLength(cells[i], width);
    end;
end;

var
    bg_pipeline, fg_pipeline: TPipeline;
    DepthBuffer : TGPUTexture;
    dummyobject: TMesh;
    gamemap: TMapGrid;

procedure initmap;
const
    data: array of string = (
        '############',
        '#......N...#',
        '#.#####N##.#',
        '#....##N...#',
        '#.#....N####',
        '#NNNNNNNNNN#',
        '###....N...#',
        '#....#.N#..#',
        '#.#....N...#',
        '############'
    );
    function CharToKind(ch: Char) : TSurfaceKind;
    begin
        case ch of
            '.': result := Bear;
            'N': Result := Nose;
            else result := None;
        end;
    end;
var
    x,y: Integer;
begin
    gamemap := TMapGrid.Create(12,10);
    for y:=0 to gamemap.height-1 do
    begin
        for x:=0 to gamemap.width-1 do
        begin
            gamemap.cells[y][x] := Default(TMapCell);
            with gamemap.cells[y][x] do begin
                floorKind := CharToKind(data[y][x+1]);
                floorHeight := 0;
            end;
        end;
    end;
end;

procedure initmesh;
var
    i,j: Integer;
    v0,v1,v2,v3: TVertex3D;
    mb: TMeshBuilder;
    tmp: Single;
    pcell: PMapCell;
    uv : TUVRect;
begin
    dummyobject := Default(TMesh);

    mb := TMeshBuilder.Create;
    for i:=0 to gamemap.height-1 do
    begin
        for j:=0 to gamemap.width-1 do
        begin
            pcell := @gamemap.cells[i][j];
            if pcell^.floorKind = None then continue;
            if pcell^.floorKind = Bear then uv := atlas.getUV(0);
            if pcell^.floorKind = Nose then uv := atlas.getUV(1);
            tmp := 0.5;
            with v0 do begin
                x:=j;
                y:=pcell^.floorHeight;
                z:=i;
                r:=tmp*0.5+0.5; g:=r; b:=r;
                u:=uv.x0; v:=uv.y0;
            end;
            with v1 do begin
                x:=j+1;
                y:=pcell^.floorHeight;
                z:=i;
                r:=tmp*0.5+0.5; g:=r; b:=r;
                u:=uv.x1; v:=uv.y0;
            end;
            with v2 do begin
                x:=j;
                y:=pcell^.floorHeight;
                z:=i+1;
                r:=tmp*0.5+0.5; g:=r; b:=r;
                u:=uv.x0; v:=uv.y1;
            end;
            with v3 do begin
                x:=j+1;
                y:=pcell^.floorHeight;
                z:=i+1;
                r:=tmp*0.5+0.5; g:=r; b:=r;
                u:=uv.x1; v:=uv.y1;
            end;
            mb.addQuad(v0,v1,v2,v3);
        end;
    end;
    rebuildMesh(@dummyobject, mb);
    mb.free;
end;

var
    asdfsampler : PSDL_GPUSampler = nil;

procedure initsampler;
var
    info : TSDL_GPUSamplerCreateInfo;
begin
    info := Default(TSDL_GPUSamplerCreateInfo);
    with info do begin
        min_filter := SDL_GPU_FILTER_NEAREST;
        mag_filter := SDL_GPU_FILTER_NEAREST;
        mipmap_mode := SDL_GPU_SAMPLERMIPMAPMODE_NEAREST;
        min_lod := 0;
        max_lod := 0;
    end;
    asdfsampler := SDL_CreateGPUSampler(Device, @info);
    if asdfsampler = nil then begin
        SDL_Log(PChar(Format('Couldn''t create sampler: %s', [SDL_GetError])));
        Exit;
    end;
end;

procedure init;
const
    fg_attrs : array of TSDL_GPUVertexAttribute =
    (
        (location: 0; buffer_slot: 0; format: SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3; offset: 0),
        (location: 1; buffer_slot: 0; format: SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3; offset: 4*3),
        (location: 2; buffer_slot: 0; format: SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2; offset: 4*6)
    );
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
        vertexShaderName := 'simple_xyz_rgb_uv';
        fragmentShaderName := 'tex_color';
        vertexAttributes := fg_attrs;
        vertexPitch := sizeof(TVertex3D);
        numVertexUniforms := 1;
        numFragmentSamplers := 1;
        hasDepth := true;
        fg_pipeline := CreatePipeline;
        Destroy;
    end;

    initmap;
    initatlas;
    initmesh;

    initsampler;

    DepthBuffer := TGPUTexture.Create(screen_width, screen_height, SDL_GPU_TEXTUREFORMAT_D16_UNORM, SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET);
end;

procedure renderMesh(renderpass: PSDL_GPURenderPass; mesh: TMesh);
var
    binding: TSDL_GPUBufferBinding;
begin
    binding := default(TSDL_GPUBufferBinding);
    binding.buffer := mesh.vb;
    SDL_BindGPUVertexBuffers(renderpass, 0, @binding, 1);

    if mesh.numIndices = 0 then
    begin
        SDL_DrawGPUPrimitives(renderpass, mesh.numVertices, 1, 0, 0);
    end else begin
        binding.buffer := mesh.ib;
        SDL_BindGPUIndexBuffer(renderpass, @binding, SDL_GPU_INDEXELEMENTSIZE_32BIT);
        SDL_DrawGPUIndexedPrimitives(renderpass, mesh.numIndices, 1, 0, 0, 0);
    end;
end;

procedure render;
var
    time: Single;
    cmdbuf: PSDL_GPUCommandBuffer;
    swapchaintex: PSDL_GPUTexture;
    colortargetinfo: TSDL_GPUColorTargetInfo;
    depthtargetinfo: TSDL_GPUDepthStencilTargetInfo;
    renderpass: PSDL_GPURenderPass;
    transform: TMatrix4_single;
    texbinding: TSDL_GPUTextureSamplerBinding;

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

    // render
    renderpass := SDL_BeginGPURenderPass(cmdbuf, @colortargetinfo, 1, @depthtargetinfo);

    SDL_BindGPUGraphicsPipeline(renderpass, bg_pipeline.handle);
    SDL_DrawGPUPrimitives(renderPass, 3, 1, 0, 0); // one fullscreen triangle

    SDL_BindGPUGraphicsPipeline(renderpass, fg_pipeline.handle);
    transform.init_identity;
    transform := translate(-6.5,-0.5,-5.5) * transform;
    //transform := rotateZ(time*1.7) * transform;
    transform := rotateY(time) * transform;
    //transform := translate(0,0,8) * transform;
    transform := perspective(DegToRad(60), screen_height/screen_width, 0.1, 100) * transform;
    // GPU wants column-major, but TMatrix4_single is row-major
    transform := transform.transpose;
    SDL_PushGPUVertexUniformData(cmdbuf, 0, @transform.data, SizeOf(transform.data));

    texbinding := default(TSDL_GPUTextureSamplerBinding);
    texbinding.texture := atlastex.handle;
    texbinding.sampler := asdfsampler;
    SDL_BindGPUFragmentSamplers(renderpass, 0, @texbinding, 1);

    renderMesh(renderpass, dummyobject);

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

    atlas.free;
    atlastex.free;
    gamemap.free;

    bg_pipeline.Destroy;
    fg_pipeline.Destroy;
    DepthBuffer.Destroy;
    SDL_ReleaseWindowFromGPUDevice(Device, Window);
    SDL_DestroyWindow(Window);
    SDL_DestroyGPUDevice(Device);
    SDL_Quit();
end.
