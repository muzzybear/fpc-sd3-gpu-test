{$mode objfpc}
{$H+}

unit Matrix3DMath;

interface

uses matrix;

function rotateX(angle: Single) : TMatrix4_single;
function rotateY(angle: Single) : TMatrix4_single;
function rotateZ(angle: Single) : TMatrix4_single;
function translate(X,Y,Z: Single) : TMatrix4_single;
function perspective(fovy, aspect, near, far: Single): TMatrix4_single;

implementation

uses Math;

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
end.
