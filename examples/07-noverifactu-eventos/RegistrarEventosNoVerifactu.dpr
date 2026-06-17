{******************************************************************************}
{  RegistrarEventosNoVerifactu - Ejemplo de uso de Fiscal.NoVerifactu          }
{                                                                              }
{  El modo NO VERI*FACTU obliga a llevar un LIBRO DE EVENTOS del sistema       }
{  (arranque, cierre, cambios de configuracion, exportaciones, incidencias).   }
{  Cada evento se encadena con el anterior por huella SHA-256 y, en modo       }
{  legal, se firma con XAdES (politica AGE) usando el certificado de empresa.  }
{                                                                              }
{  Este ejemplo registra cuatro eventos tipicos del dia a dia:                 }
{    - "abrir programa"      -> Inicio del sistema        (codigo AEAT 01)     }
{    - "factura creada"      -> Evento voluntario         (codigo AEAT 90)     }
{    - "cambio de parametros"-> Cambio de configuracion   (codigo AEAT 03)     }
{    - "cerrar programa"     -> Cierre del sistema        (codigo AEAT 02)     }
{  y vuelca el libro a un XML.                                                 }
{                                                                              }
{  Uso:  RegistrarEventosNoVerifactu.exe [salida.xml] [serialCert] [titular]   }
{        Sin serial/titular -> modo DEMO (solo huella SHA-256, sin firma).     }
{        Con serial/titular -> firma XAdES con el certificado de Windows.      }
{******************************************************************************}
program RegistrarEventosNoVerifactu;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.StrUtils,
  System.IOUtils,
  Fiscal.Xades in '..\..\src\Fiscal.Xades.pas',
  Fiscal.EnvioVerifactu in '..\..\src\Fiscal.EnvioVerifactu.pas',
  Fiscal.NoVerifactu in '..\..\src\Fiscal.NoVerifactu.pas';

// Datos fijos del SISTEMA INFORMATICO (el software) y del OBLIGADO (la
// empresa). En una aplicacion real vendrian de la configuracion y de la ficha
// de empresa; aqui se dejan a la vista para que el ejemplo sea autocontenido.
function DatosDemo: TSistemaInformaticoSif;
begin
  Result := Default(TSistemaInformaticoSif);
  Result.NombreProductor      := 'Ejemplo Sánchez Cornejo';
  Result.NifProductor         := '99999999R';
  Result.NombreSistema        := 'Ejemplo';
  Result.IdSistema            := 'EJ';
  Result.Version              := '1.0.0';
  Result.NumeroInstalacion    := '1';
  Result.IndicadorMultiplesOT := 'N';
  Result.NombreObligado       := 'Ejemplo Romero de Palma';
  Result.NifObligado          := '12345678Z';
end;

procedure MostrarEvento(const AEvento: TEventoNoVerifactu);
begin
  Writeln(Format('  [%s] %-22s huella=%s...%s',
    [AEvento.TipoAeat, AEvento.Descripcion,
     Copy(AEvento.HuellaPropia, 1, 12),
     IfThen(AEvento.Firmado, '  (firmado XAdES)', '  (demo SHA-256)')]));
end;

var
  oLibro:    TLibroEventosNoVerifactu;
  sSalida:   string;
  sSerial:   string;
  sTitular:  string;
begin
  try
    sSalida := ParamStr(1);
    if sSalida = '' then
      sSalida := 'eventos_noverifactu.xml';
    sSerial  := ParamStr(2);
    sTitular := ParamStr(3);

    oLibro := TLibroEventosNoVerifactu.Create(DatosDemo);
    try
      // Si se indica certificado, los eventos se firman (modo legal). Si no,
      // el libro queda en modo demo con huella SHA-256.
      if (sSerial <> '') or (sTitular <> '') then
        oLibro.ConfigurarFirma(sSerial, sTitular);

      Writeln('====================================================');
      if oLibro.Firmar then
        Writeln(' Libro de eventos NO VERI*FACTU (firmado XAdES)')
      else
        Writeln(' Libro de eventos NO VERI*FACTU (demo, sin firma)');
      Writeln('====================================================');

      // La cadena de eventos del dia. El orden importa: cada evento encadena
      // con la huella del anterior.
      MostrarEvento(oLibro.Registrar(cEventoInicio,
        'Abrir programa', 'Arranque de la aplicacion'));
      MostrarEvento(oLibro.Registrar(cEventoOtros,
        'Factura creada', 'Alta de borrador', '2026.A1', '000154'));
      MostrarEvento(oLibro.Registrar(cEventoCambioConfig,
        'Cambio de parametros', 'appVerifactuModo=NO_VERIFACTU'));
      MostrarEvento(oLibro.Registrar(cEventoFin,
        'Cerrar programa', 'Cierre de la aplicacion'));

      TFile.WriteAllText(sSalida, oLibro.XmlExportacion('1.0.0', 'demo'),
        TEncoding.UTF8);

      Writeln('');
      Writeln('Eventos registrados : ', Length(oLibro.Eventos));
      Writeln('Ultima huella       : ', oLibro.UltimaHuella);
      Writeln('Libro de eventos XML: ', sSalida);
    finally
      FreeAndNil(oLibro);
    end;
  except
    on E: Exception do
    begin
      // En modo firmado, la falta de certificado (o su cancelacion) detiene
      // el registro: NO se hace fallback a SHA-256.
      Writeln('ERROR: ', E.ClassName, ': ', E.Message);
      Halt(2);
    end;
  end;
  Writeln('');
  Write('Pulsa Intro para salir...');
  Readln;
end.
