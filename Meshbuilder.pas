{$mode objfpc}
{$H+}

unit Meshbuilder;

interface

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

implementation

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

end.
