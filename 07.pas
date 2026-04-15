{$mode objfpc}
{$H+}
{$modeswitch ADVANCEDRECORDS}

uses
    Sysutils, ctypes, Math, SDL3, SDL3_ttf, FGL;

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
    CenteredFont: PTTF_Font;
    TextEngine: PTTF_TextEngine;

// -----

procedure initgui; forward;

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
    CenteredFont := TTF_CopyFont(Font);
    TTF_SetFontWrapAlignment(CenteredFont, TTF_HORIZONTAL_ALIGN_CENTER);

    TextEngine := TTF_CreateRendererTextEngine(Renderer);

    initgui;
end;

type
    TGUIMessageType = (gmMouseMove, gmMouseUp, gmMouseDown);

    TGUIMessage = record
        msgtype: TGUIMessageType;

        case TGUIMessageType of
            gmMouseMove: (move: record x,y: Integer; end);
            gmMouseUp:   (mouseup: record btn, x,y: Integer; end);
            gmMouseDown: (mousedown: record btn, x,y: Integer; end);
    end;

    TRenderObject = class
    public
        procedure render; virtual; abstract;
    end;

    TRenderObjectList = specialize TFPGObjectList<TRenderObject>;

    TGUI = class(TRenderObject)
    private
        children : TRenderObjectList;
    public
        constructor Create;
        destructor Destroy; override;
        procedure render; override;

        procedure MouseMove(var msg: TGUIMessage); message Integer(gmMouseMove);

        procedure add(obj: TRenderObject);
    end;

    TBoundedRenderObject = class(TRenderObject)
    private
        x_,y_, w,h : Integer;
        mousein: Boolean;
        function getFRect: TSDL_FRect;
        procedure MouseMove(var msg: TGUIMessage); message Integer(gmMouseMove);
    public
        property X: Integer read x_ write x_;
        property Y: Integer read y_ write y_;
        property Width: Integer read w write w;
        property Height: Integer read h write h;
        property Bounds: TSDL_FRect read getFRect;
        property MouseInBounds: Boolean read mousein;
    end;

    TButton = class(TBoundedRenderObject)
        text_: String;
    public
        procedure render; override;

        property Text: String read text_ write text_;
    end;

constructor TGUI.Create;
begin
    children := TRenderObjectList.Create;
end;

destructor TGUI.Destroy;
begin
    children.free;
    inherited;
end;

procedure TGUI.add(obj: TRenderObject);
begin
    children.add(obj);
end;

procedure TGUI.Render;
var
    obj : TRenderObject;
begin
    for obj in children do obj.render;
end;

procedure TGUI.MouseMove(var msg: TGUIMessage);
var
    obj : TRenderObject;
begin
    for obj in children do obj.Dispatch(msg);
end;

function TBoundedRenderObject.getFRect: TSDL_FRect;
begin
    result.x := X;
    result.y := Y;
    result.w := Width;
    result.h := Height;
end;

procedure TBoundedRenderObject.MouseMove(var msg: TGUIMessage);
var
    rect : TSDL_FRect;
    point : TSDL_FPoint;
begin
    inherited;
    rect := Bounds;
    point.x := msg.move.x;
    point.y := msg.move.y;
    mousein := SDL_PointInRectFloat(@point, @rect);
end;

procedure TButton.render;
var
    rect: TSDL_FRect;
    ttf_text: PTTF_Text;
    tw,th: Integer;
begin
    if MouseInBounds then begin
        SDL_SetRenderDrawColorFloat(Renderer, 0.2,0.2,0.8, 1.0);
    end else begin
        SDL_SetRenderDrawColorFloat(Renderer, 0.0,0.0,0.6, 1.0);
    end;
    rect := Bounds;
    SDL_RenderFillRect(Renderer, @rect);
    ttf_text := TTF_CreateText(TextEngine, CenteredFont, PChar(Text), 0);
    TTF_SetTextWrapWidth(ttf_text, Width);
    TTF_GetTextSize(ttf_text, @tw,@th);
    // center alignment isn't really needed, centered font should always give maximum width
    TTF_DrawRendererText(ttf_text, x+(width-tw) div 2, y+(height-th) div 2);
    TTF_DestroyText(ttf_text);
end;

var
    gui: TGUI;

procedure initgui;
var
    tmp: TButton;
begin
    gui := TGUI.Create;

    tmp := TButton.Create;
    tmp.x := 100; tmp.y := 200;
    tmp.width := 100; tmp.height := 40;
    tmp.text := 'Yatta!';
    gui.add(tmp);

    tmp := TButton.Create;
    tmp.x := 300; tmp.y := 200;
    tmp.width := 100; tmp.height := 40;
    tmp.text := 'Happy Go Lucky!';
    gui.add(tmp);
end;

procedure render;
var
    i: Integer;
    text: PTTF_Text;

begin
    SDL_SetRenderDrawColorFloat(Renderer, 0.2, 0.2, 0.2, 1.0);
    SDL_RenderClear(Renderer);

    text := TTF_CreateText(TextEngine, Font, PChar('foo bar baz'#10#10'ちりも積もれば山となる'#10#10'千里之行，始於足下'#10#10'لا يهم كم أنت بطيئ طالما أنك لن تتوقف'), 0);
    TTF_DrawRendererText(text, 10, 10);
    TTF_DestroyText(text);

    gui.render;

    SDL_RenderPresent(Renderer);
end;

var
    quitting : boolean = false;

procedure mainloop;
var
    event: TSDL_Event;
    guimsg: TGUIMessage;
begin
    while not quitting do
    begin
        while (SDL_PollEvent(@event)) do
        begin
            if event._type = SDL_EVENT_QUIT then begin
                quitting := true;
            end;
            if event._type = SDL_EVENT_MOUSE_MOTION then begin
                guimsg.msgtype := gmMouseMove;
                guimsg.move.x := Round(event.motion.x);
                guimsg.move.y := Round(event.motion.y);
                gui.Dispatch(guimsg);
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

    gui.free;

    TTF_CloseFont(Font);
    TTF_CloseFont(CenteredFont);
    TTF_Quit();

    SDL_DestroyRenderer(Renderer);
    SDL_ReleaseWindowFromGPUDevice(Device, Window);
    SDL_DestroyWindow(Window);
    SDL_DestroyGPUDevice(Device);
    SDL_Quit();
end.
