unit Glib;

{$R-,Q-}

interface

uses
  Windows, Graphics, Types, PNGImage, SysUtils;

function  CreateBitmap(Width, Height: Integer): TBitmap;
function  LoadBitmap(FN: string): TBitmap;
procedure SaveAsPNG(B: TBitmap; FN: string);
function  GetPixel(B: TBitmap; X, Y: Integer)  : TColor ; inline; // 32-BPP only
procedure PutPixel(B: TBitmap; X, Y: Integer; C: TColor); inline; // 32-BPP only
function  Crop(B: TBitmap; X1, Y1, X2, Y2: Integer): TBitmap;

function  LoadPNG(FN: string): TPNGObject;
procedure SavePNG(P: TPNGObject; FN: string);
function  CropPNG(P: TPNGObject; X1, Y1, X2, Y2: Integer): TPNGObject; // slow
function  ToBitmap(P: TPNGObject): TBitmap;
function  VConcatPNG(P1, P2: TPNGObject): TPNGObject;

// XOR
function Difference(P0, P1: TPNGObject): TPNGObject;
// Create alpha PNG of an object taken with a black (P0) and white (P1) backgrounds.
function  MakeAlpha(P0, P1: TPNGObject): TPNGObject;
// Create alpha PNG of an object using a picture without (P0) and with (P1) the object, assuming the object has only grayscale colors.
//function  MakeAlphaGrayscale(P0, P1: TPNGObject): TPNGObject;

// Averages NxN blocks
function Downscale(Bitmap: TBitmap; N: Integer): TBitmap;
// Render text to a new bitmap
function RenderText(Font: TFont; BackgroundColor: TColor; Text: String): TBitmap;

implementation

function CreateBitmap(Width, Height: Integer): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf32bit;
  Result.Width := Width;
  Result.Height := Height;
end;

function LoadBitmap(FN: string): TBitmap;
begin
  if LowerCase(ExtractFileExt(FN))='.png' then
    Result := ToBitmap(LoadPNG(FN))
  else
  begin
    Result := TBitmap.Create;
    Result.LoadFromFile(FN);
    Result.PixelFormat := pf32bit;
  end;
end;

procedure SaveAsPNG(B: TBitmap; FN: string);
var
  P: TPNGObject;
begin
  P := TPNGObject.Create;
  P.Assign(B);
  SavePNG(P, FN);
  P.Free;
end;

function GetPixel(B: TBitmap; X, Y: Integer): TColor; inline;
begin
  Result := PIntegerArray(B.Scanline[Y])[X];
end;

procedure PutPixel(B: TBitmap; X, Y: Integer; C: TColor); inline;
begin
  PIntegerArray(B.Scanline[Y])[X] := C;
end;

function Crop(B: TBitmap; X1, Y1, X2, Y2: Integer): TBitmap;
begin
  Result := TBitmap.Create;
  Result.Assign(B);
  Result.Width := X2-X1;
  Result.Height := Y2-Y1;
  Result.Canvas.CopyRect(Rect(0, 0, Result.Width, Result.Height), B.Canvas, Rect(X1, Y1, X2, Y2));
end;

// ********************************************************

function  LoadPNG(FN: string): TPNGObject;
begin
  Result := TPNGObject.Create;
  Result.LoadFromFile(FN);
end;

procedure SavePNG(P: TPNGObject; FN: string);
begin
  P.CompressionLevel:=9;
  P.Filters:=[pfNone, pfSub, pfUp, pfAverage, pfPaeth];
  P.SaveToFile(FN);
end;

function  CropPNG(P: TPNGObject; X1, Y1, X2, Y2: Integer): TPNGObject;
var
  X, Y: Integer;
begin
  if (X2>P.Width)  then raise Exception.Create('CropPNG: X2 > Width');
  if (Y2>P.Height) then raise Exception.Create('CropPNG: Y2 > Height');
  Result := TPNGObject.CreateBlank(P.Header.ColorType, P.Header.BitDepth, X2-X1, Y2-Y1);
  Result.Palette := P.Palette;
  //Result := TPNGObject.Create;
  //Result.Assign(P);
  for Y := 0 to Y2-Y1-1 do
    for X := 0 to X2-X1-1 do
      Result.Pixels[X, Y] := P.Pixels[X1+X, Y1+Y];
end;

function  VConcatPNG(P1, P2: TPNGObject): TPNGObject;
var
  X, Y: Integer;
begin
  if P1.Height<>P2.Height then
    raise Exception.Create('Mismatching height in VConcatPNG');
  Result := TPNGObject.CreateBlank(P1.Header.ColorType, P1.Header.BitDepth, P1.Width+P2.Width, P1.Height);
  for Y := 0 to P1.Height-1 do
    for X := 0 to P1.Width-1 do
      Result.Pixels[X, Y] := P1.Pixels[X, Y];
  for Y := 0 to P2.Height-1 do
    for X := 0 to P2.Width-1 do
      Result.Pixels[X+P1.Width, Y] := P2.Pixels[X, Y];
end;

function ToBitmap(P: TPNGObject): TBitmap;
begin
  Result := TBitmap.Create;
  Result.Assign(P);
  Result.PixelFormat := pf32bit;
end;

// ********************************************************

function Difference(P0, P1: TPNGObject): TPNGObject;
var
  X, Y: Integer;
begin
  Result := TPNGObject.CreateBlank(P0.Header.ColorType, P0.Header.BitDepth, P0.Width, P0.Height);
  for Y:=0 to P0.Height-1 do
    for X:=0 to P0.Width-1 do
      Result.Pixels[X, Y] := P0.Pixels[X,Y] xor P1.Pixels[X,Y];
end;

procedure CalcAlpha(X, Y: Byte; var C, A: Byte); inline;
begin
  A := 255+X-Y;
  if A=0 then
    C := 0
  else
    C := 255*X div A;
end;

function MakeAlpha(P0, P1: TPNGObject): TPNGObject;
var
  X, Y: Integer;
  C0, C1: TColor;
  R, G, B, A1, A2, A3: Byte;
begin
  Result := TPNGObject.CreateBlank(COLOR_RGBALPHA, 8, P0.Width, P0.Height);
  for Y:=0 to P0.Height-1 do
    for X:=0 to P0.Width-1 do
    begin
      C0 := P0.Pixels[X,Y];
      C1 := P1.Pixels[X,Y];
      CalcAlpha(GetRValue(C0), GetRValue(C1), R, A1);
      CalcAlpha(GetGValue(C0), GetGValue(C1), G, A2);
      CalcAlpha(GetBValue(C0), GetBValue(C1), B, A3);
      //PIntegerArray(Result.     Scanline[Y])[X] := RGB(R, G, B);
      Result.Pixels[X, Y] := RGB(R, G, B);
      PByteArray   (Result.AlphaScanline[Y])[X] := (A1 + A2 + A3) div 3;
    end;
end;

{function MakeAlphaGrayscale(P0, P1: TPNGObject): TPNGObject;
var
  X, Y: Integer;
  C0, C1: TColor;
  R0, G0, B0, R1, G1, B1, RD, GD, BD: Integer;
begin
  Result := TPNGObject.CreateBlank(COLOR_RGBALPHA, 8, P0.Width, P0.Height);
  for Y:=0 to P0.Height-1 do
    for X:=0 to P0.Width-1 do
    begin
      C0 := P0.Pixels[X,Y];
      C1 := P1.Pixels[X,Y];
      
      R0 := GetRValue(C0);
      G0 := GetGValue(C0);
      B0 := GetBValue(C0);
      
      R1 := GetRValue(C1);
      G1 := GetGValue(C1);
      B1 := GetBValue(C1);

      // P1 = (ResultColor * ResultAlpha) + (P0 * (1-ResultAlpha))
      
      CalcAlpha(GetRValue(C0), GetRValue(C1), R, A1);
      CalcAlpha(GetGValue(C0), GetGValue(C1), G, A2);
      CalcAlpha(GetBValue(C0), GetBValue(C1), B, A3);
      //PIntegerArray(Result.     Scanline[Y])[X] := RGB(R, G, B);
      Result.Pixels[X, Y] := RGB(R, G, B);
      PByteArray   (Result.AlphaScanline[Y])[X] := (A1 + A2 + A3) div 3;
    end;
end;}

function Downscale(Bitmap: TBitmap; N: Integer): TBitmap;
var
  X, Y, I, J: Integer;
  R, G, B: Integer;
  C: TColor;
begin
  Result := TBitmap.Create;
  Result.Width := Bitmap.Width div N;
  Result.Height := Bitmap.Height div N;
  for Y:=0 to Bitmap.Height div N - 1 do
    for X:=0 to Bitmap.Width div N - 1 do
    begin
      R := 0; G := 0; B := 0;
      for J:=0 to N-1 do
        for I:=0 to N-1 do
        begin
          C := Bitmap.Canvas.Pixels[X*N+I, Y*N+J];
          Inc(R, GetRValue(C));
          Inc(G, GetGValue(C));
          Inc(B, GetBValue(C));
        end;
      Result.Canvas.Pixels[X, Y] := RGB(R div (N*N), G div (N*N), B div (N*N));
    end;
end;

function RenderText(Font: TFont; BackgroundColor: TColor; Text: String): TBitmap;
begin
  Result := TBitmap.Create;
  Result.Canvas.Font := Font;
  Result.Canvas.Brush.Color := BackgroundColor;
  Result.Width := Result.Canvas.TextWidth(Text);
  Result.Height := Result.Canvas.TextHeight(Text);
  Result.Canvas.TextOut(0, 0, Text);
end;

end.
