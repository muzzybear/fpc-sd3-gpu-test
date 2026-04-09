{$mode objfpc}
{$H+}
{$modeswitch ADVANCEDRECORDS}

uses
    Sysutils, ctypes, matrix, Math, SDL3, lgQueue;

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

type
    TMapIndex = Integer;
    TMapIndexArray = array of TMapIndex;

    Generic TMap<T> = class
        data: array of T;
        width_, height_: Integer;
        function GetCell(y,x:Integer) : T;
        procedure SetCell(y,x:Integer; value:T);
    public
        constructor Create(W,H:Integer);
        property Width : Integer Read width_;
        property Height : Integer Read height_;
        property Cell[y,x: Integer] : T Read GetCell Write SetCell; default;

        procedure Clear;
        procedure Fill(value: T);
    end;

constructor TMap.Create(W,H:Integer);
begin
    width_ := W;
    height_ := H;
    SetLength(data, W*H);
end;

function TMap.GetCell(y,x:Integer) : T;
begin
    result := data[y*width+x];
end;

procedure TMap.SetCell(y,x:Integer; value:T);
begin
    data[y*width+x] := value;
end;

procedure TMap.Clear;
begin
    Fillchar(data[0], Length(data)*sizeof(T), 0);
end;

procedure TMap.Fill(value: T);
var
    i: Integer;
begin
    for i:=0 to Length(data)-1 do begin
        data[i] := value;
    end;
end;

// ----



// ----

type
    TGameMap = specialize TMap<Byte>;

var
    map : TGameMap;
    distmap : specialize TMap<Integer>;

procedure initmap;

    procedure makeroom(x,y,w,h:Integer);
    var
        i, j: Integer;
    begin
        for i:=x to x+w-1 do begin
            map[y,i] := 0;
            map[y+h-1,i] := 0;
        end;
        for j:=y+1 to y+h-2 do begin
            map[j,x] := 0;
            for i:=x+1 to x+w-2 do begin
                map[j,i] := 1;
            end;
            map[j,x+w-1] := 0;
        end;

    end;

var
    x, y: Integer;
begin
    map := TGameMap.Create(33,33);
    for y:=0 to map.Height-1 do begin
        for x:=0 to map.Width-1 do begin
            map[y,x] := (x*x+y*y) and (16+4);
        end;
    end;

    makeroom(5,3,8,5);
    makeroom(16,7,7,10);
    makeroom(8,11,6,12);
    map[3,8] := 1;
    map[19,8] := 1;
    map[12,13] := 1;
    map[12,16] := 1;
    map[16,20] := 1;

    distmap := specialize TMap<Integer>.Create(33,33);
    distmap.Clear;
    for y:=0 to map.Height-1 do begin
        for x:=0 to map.Width-1 do begin
            distmap[y,x] := x+y;
        end;
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

    Renderer := SDL_CreateGPURenderer(Device, Window);

    if Renderer = nil then
    begin
        SDL_Log(PChar(Format('Couldn''t create GPU renderer: %s', [SDL_GetError])));
        Exit;
    end;

    initmap;
end;

procedure calcdist(ox,oy:Integer);
type
    TWork = record x,y,d: Integer; end;
    function makeWork(x,y,d:Integer) : TWork;
    begin
        Result.x := x;
        Result.y := y;
        Result.d := d;
    end;
var
    work: TWork;
    workqueue: specialize TGQueue<TWork>;

begin
    distmap.Fill(99);
    workqueue := specialize TGQueue<TWork>.Create;
    workqueue.Enqueue(makeWork(ox,oy,0));

    while workqueue.TryDequeue(work) do begin
        // test if we're searching into a valid cell
        if (work.y < 0) or (work.y >= distmap.height) then continue;
        if (work.x < 0) or (work.x >= distmap.width) then continue;
        if map[work.y, work.x] = 0 then continue; // don't path into walls

        if distmap[work.y, work.x] <= work.d then continue;
        distmap[work.y, work.x] := work.d;

        // queue unchecked 4way walk
        workqueue.Enqueue(makeWork(work.x-1,work.y,work.d+1));
        workqueue.Enqueue(makeWork(work.x+1,work.y,work.d+1));
        workqueue.Enqueue(makeWork(work.x,work.y-1,work.d+1));
        workqueue.Enqueue(makeWork(work.x,work.y+1,work.d+1));
    end;
    workqueue.free;
end;

var
    startx, starty : Integer;

procedure render;
var
    rect: TSDL_FRect;
    x, y: Integer;
    d: Integer;

begin
    SDL_SetRenderDrawColorFloat(Renderer, 0.2, 0.2, 0.2, 1.0);
    SDL_RenderClear(Renderer);

    rect.w := 17;
    rect.h := 11;

    startx := 6;
    starty := 12;

    calcdist(startx, starty);

    for y:=0 to map.Height-1 do begin
        for x:=0 to map.Width-1 do begin
            rect.x := x*19 +8;
            rect.y := y*13 +12;
            d := distmap[y,x];
            if map[y,x] = 0 then begin
                d := -1;
                SDL_SetRenderDrawColorFloat(Renderer, 0.1, 0.1, 0.1, 1.0);
            end else begin
                SDL_SetRenderDrawColorFloat(Renderer, d*0.02, 0.2, 0.8, 1.0);
            end;
            SDL_RenderFillRect(Renderer, @rect);
            if d >= 0 then begin
                SDL_SetRenderDrawColorFloat(Renderer, 1.0, 1.0, 1.0, 0.5);
                SDL_RenderDebugText(Renderer, rect.x+1, rect.y+2, PChar(Format('%.2d', [d])));
            end;
        end;
    end;

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

    map.free;
    distmap.free;

    SDL_DestroyRenderer(Renderer);
    SDL_ReleaseWindowFromGPUDevice(Device, Window);
    SDL_DestroyWindow(Window);
    SDL_DestroyGPUDevice(Device);
    SDL_Quit();
end.
