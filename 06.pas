{$mode objfpc}
{$H+}
{$modeswitch ADVANCEDRECORDS}

uses
    Sysutils, ctypes, Math, SDL3, Meshbuilder;

const
    screen_width = 640;
    screen_height = 480;
    window_title = 'yatta';
    window_flags = 0; //SDL_WINDOW_VULKAN;

var
    Window: PSDL_Window = nil;
    Device: PSDL_GPUDevice = nil;
    Renderer: PSDL_Renderer = nil;

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
end;

type
    TMeshBuilder = specialize TGenericMeshBuilder<TSDL_Vertex>;

function PointInTriangle(p, a,b,c: TSDL_FPoint): Boolean;
var
    p_ab: Boolean;
begin
    p_ab :=  (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x) > 0;
    if      ((c.x - a.x) * (p.y - a.y) - (c.y - a.y) * (p.x - a.x) > 0) = p_ab then
    begin
        result := false;
    end
    else if ((c.x - b.x) * (p.y - b.y) - (c.y - b.y) * (p.x - b.x) > 0) <> p_ab then
    begin
        result := false;
    end
    else
        result := true;
end;

procedure triangulate(mb: TMeshBuilder; points: array of TSDL_FPoint);
var
    p: array of integer;
    i: integer;

    procedure v(points_idx: Integer);
    var
        tmp : TSDL_Vertex;
    begin
        tmp := Default(TSDL_Vertex);
        tmp.position.x := points[points_idx].x;
        tmp.position.y := points[points_idx].y;
        tmp.color.r := 1.0;
        tmp.color.g := 1.0;
        tmp.color.b := 1.0;
        tmp.color.a := 1.0;
        mb.addVertex(tmp);
    end;

    procedure earclip(idx: Integer);
    begin
        // TODO index-only version
        v(p[idx]);
        v(p[(idx+1) mod Length(p)]);
        v(p[(idx-1+Length(p)) mod Length(p)]);
        delete(p, idx, 1);
    end;

    function earclippable(idx: Integer): Boolean;
    var
        i, t: integer;
        prev,next: integer;
    begin
        prev := (idx+Length(p)-1) mod Length(p);
        next := (idx+1) mod Length(p);
        // without self-intersections, the ear is clippable if it has no points inside it
        for i:=0 to Length(p)-3 do
        begin
            t := (i+2) mod Length(p);
            if PointInTriangle(points[p[t]], points[p[prev]], points[p[idx]], points[p[next]]) then begin
                result := false;
                exit;
            end;
        end;
        result := true;
    end;

begin
    // initialize index list for untesselated polygon points
    SetLength(p, Length(points));
    for i:=0 to Length(points)-1 do
        p[i] := i;

    while Length(p) >= 3 do
    begin
        // find ear to clip
        for i:=0 to Length(p)-1 do begin
            if earclippable(i) then begin
                earclip(i);
                break;
            end;
        end;
    end;
end;

type
    TPolygon = record
        points: array of TSDL_FPoint;
    end;

procedure render_polygon(poly: TPolygon);
var
    mb : TMeshBuilder;

begin
    mb := TMeshBuilder.Create;
    triangulate(mb, poly.points);
    SDL_RenderGeometry(Renderer, nil, mb.getVertices, mb.numVertices, nil, 0);
    mb.free;

    SDL_SetRenderDrawColorFloat(Renderer, 1.0, 0.4, 1.0, 1.0);
    SDL_RenderLines(Renderer, @poly.points[0], Length(poly.points));
end;

procedure bevel_polygon(var poly: TPolygon; amount: Single);
var
    foo : array of TSDL_FPoint;
    i: Integer;
    a,b,ab : TSDL_FPoint;
    d : Single;
begin
    // shrink each edge from both sides by amount, make new edges between
    for i:=0 to Length(poly.points)-1 do begin
        a := poly.points[i];
        b := poly.points[(i+1) mod Length(poly.points)];
        ab.x := b.x - a.x;
        ab.y := b.y - a.y;
        d := sqrt(ab.x*ab.x + ab.y*ab.y);
        // TODO if d<amount*2 we should collapse the vertices to midpoint instead
        a.x := a.x + ab.x * amount / d;
        a.y := a.y + ab.y * amount / d;
        b.x := b.x - ab.x * amount / d;
        b.y := b.y - ab.y * amount / d;
        insert(a, foo, Length(foo));
        insert(b, foo, Length(foo));
    end;
    poly.points := foo;
end;

const
    foo : array of TSDL_FPoint = (
        (x:  0;y:100),
        (x:100;y:  0),
        (x:200;y:100),
        (x:100;y:200),
        (x: 66;y:166),
        (x:133;y:100),
        (x:100;y: 66),
        (x: 33;y:133)
    );

procedure render;
var
    x, y: Integer;
    i: Integer;
    p: TPolygon;

begin
    SDL_SetRenderDrawColorFloat(Renderer, 0.2, 0.2, 0.2, 1.0);
    SDL_RenderClear(Renderer);

    insert(foo, p.points, 0);
    for i:=0 to Length(p.points) do p.points[i].x := p.points[i].x + 10;
    for i:=0 to Length(p.points) do p.points[i].y := p.points[i].y + 10;
    render_polygon(p);

    for i:=0 to Length(p.points) do p.points[i].x := p.points[i].x + 210;
    bevel_polygon(p, 10);
    render_polygon(p);

    for i:=0 to Length(p.points) do p.points[i].x := p.points[i].x + 210;
    bevel_polygon(p, 4);
    render_polygon(p);

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

    SDL_DestroyRenderer(Renderer);
    SDL_ReleaseWindowFromGPUDevice(Device, Window);
    SDL_DestroyWindow(Window);
    SDL_DestroyGPUDevice(Device);
    SDL_Quit();
end.
