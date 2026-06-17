{******************************************************************************}
{  GenerarQRVerifactu - Ejemplo                                                }
{                                                                              }
{  Autor:  Alejandro Laorden Hidalgo                                           }
{  Email:  alejandro.laorden@protonmail.com                                    }
{******************************************************************************}

program GenerarQRVerifactu;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  DelphiZXingQRCode in '..\..\src\DelphiZXingQRCode.pas'; // Tu versión modificada

procedure GenerarBitmapQR(const ATextoUrl, ARutaDestino: string);
var
  oQRCode: TDelphiZXingQRCode;
  oBitmap: TBitmap;
  Fila, Columna: Integer;
  Escala: Integer;
begin
  oQRCode := TDelphiZXingQRCode.Create;
  oBitmap := TBitmap.Create;
  try
    // 1. Configurar el QR con la URL de la AEAT
    oQRCode.Data := ATextoUrl;
    oQRCode.Encoding := qrUTF8NoBOM; 
    oQRCode.QuietZone := 4;
    
    // 2. ¡Nivel de corrección M (15%) obligatorio para Veri*Factu!
    // Aunque ahora es tu valor por defecto, es buena práctica dejarlo explícito.
    oQRCode.ErrorCorrectionLevel := qreM;

    // 3. Establecer el tamaño y preparar el Bitmap
    Escala := 4;
    oBitmap.PixelFormat := pf24bit;
    oBitmap.Width  := oQRCode.Columns * Escala;
    oBitmap.Height := oQRCode.Rows * Escala;

    oBitmap.Canvas.Brush.Color := clWhite;
    oBitmap.Canvas.FillRect(Rect(0, 0, oBitmap.Width, oBitmap.Height));

    // 4. Dibujar la matriz de datos
    oBitmap.Canvas.Brush.Color := clBlack;
    for Fila := 0 to oQRCode.Rows - 1 do
    begin
      for Columna := 0 to oQRCode.Columns - 1 do
      begin
        if oQRCode.IsBlack[Fila, Columna] then
        begin
          oBitmap.Canvas.FillRect(Rect(
            Columna * Escala,
            Fila * Escala,
            (Columna + 1) * Escala,
            (Fila + 1) * Escala
          ));
        end;
      end;
    end;

    // 5. Guardar el QR
    oBitmap.SaveToFile(ARutaDestino);
    Writeln('Codigo QR guardado con exito en: ', ARutaDestino);

  finally
    oBitmap.Free;
    oQRCode.Free;
  end;
end;

var
  sUrlAeat: string;
begin
  try
    sUrlAeat := 'https://prewww2.aeat.es/wlpl/TIKE-CONT/ValidarQR?nif=12345678Z&numserie=2026.A1000154&fecha=17-06-2026&importe=121.00';

    Writeln('Generando bitmap del QR Nivel M para la URL:');
    Writeln(sUrlAeat);

    GenerarBitmapQR(sUrlAeat, 'QR_Verifactu_NivelM.bmp');

  except
    on E: Exception do
      Writeln('ERROR: ', E.ClassName, ': ', E.Message);
  end;
  
  Writeln('');
  Write('Pulsa Intro para salir...');
  Readln;
end.