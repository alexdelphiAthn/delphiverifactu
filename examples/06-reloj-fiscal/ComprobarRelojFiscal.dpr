{******************************************************************************}
{  ComprobarRelojFiscal - Ejemplo de uso de Fiscal.RelojFiscal                 }
{                                                                              }
{  El modo NO VERI*FACTU exige fechar los registros con la hora exacta (margen }
{  maximo de UN MINUTO). Este ejemplo compara el reloj del sistema con una     }
{  hora de referencia y DENIEGA si la diferencia supera el margen.             }
{                                                                              }
{  Para que se pueda probar sin conexion, el desfase se puede SIMULAR desde    }
{  el .ini: pon DesfaseSimuladoSegundos = 90 y veras como se deniega.          }
{                                                                              }
{  Uso:  ComprobarRelojFiscal.exe [ruta_al_ini]                               }
{        Si no se pasa ruta, busca ComprobarRelojFiscal.ini junto al .exe.     }
{******************************************************************************}
program ComprobarRelojFiscal;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IniFiles,
  Fiscal.RelojFiscal in '..\..\src\Fiscal.RelojFiscal.pas';

procedure Ejecutar(const ARutaIni: string);
var
  oIni:            TMemIniFile;
  iMargen:         Integer;
  dDesfaseSim:     Double;
  bComprobarRed:   Boolean;
  sServidor:       string;
  iTimeout:        Integer;
  dSistemaUtc:     TDateTime;
  dSistemaSim:     TDateTime;
  dReferenciaUtc:  TDateTime;
  sOrigen:         string;
  oResultado:      TResultadoReloj;
  oFmt:            TFormatSettings;
begin
  if not FileExists(ARutaIni) then
    raise Exception.Create('No se encuentra el .ini: ' + ARutaIni);
  // El .ini usa el punto como separador decimal (DesfaseSimuladoSegundos).
  oFmt := TFormatSettings.Create;
  oFmt.DecimalSeparator  := '.';
  oFmt.ThousandSeparator := #0;

  oIni := TMemIniFile.Create(ARutaIni);
  try
    iMargen       := oIni.ReadInteger('Reloj', 'MargenSegundos', 60);
    dDesfaseSim   := StrToFloatDef(
      oIni.ReadString('Reloj', 'DesfaseSimuladoSegundos', '0'), 0, oFmt);
    bComprobarRed := oIni.ReadInteger('Reloj', 'ComprobarRed', 0) = 1;
    sServidor     := oIni.ReadString('Reloj', 'ServidorHora',
      cServidorHoraDefecto);
    iTimeout      := oIni.ReadInteger('Reloj', 'TimeoutMs',
      cTimeoutHoraDefectoMs);
  finally
    FreeAndNil(oIni);
  end;

  // 1) Hora del sistema (en UTC).
  dSistemaUtc := HoraSistemaUtc;

  // 2) Hora de referencia (la "oficial"). Por red, o el propio sistema si
  //    trabajamos sin conexion.
  if bComprobarRed then
  begin
    sOrigen := 'RED';
    if not ObtenerHoraRedHttp(sServidor, iTimeout, dReferenciaUtc) then
    begin
      Writeln('Aviso: no se pudo obtener la hora de ', sServidor);
      Writeln('       Se usa la hora del sistema como referencia (demo).');
      dReferenciaUtc := dSistemaUtc;
      sOrigen := 'SIMULADO';
    end;
  end
  else
  begin
    sOrigen := 'SIMULADO';
    dReferenciaUtc := dSistemaUtc;
  end;

  // 3) Simulamos un reloj de sistema desviado sumando el desfase configurado.
  dSistemaSim := dSistemaUtc + (dDesfaseSim / (24 * 60 * 60));

  // 4) Evaluamos la regla legal.
  oResultado := EvaluarReloj(dSistemaSim, dReferenciaUtc, iMargen, sOrigen);

  Writeln('====================================================');
  Writeln(' Control del reloj fiscal NO VERI*FACTU');
  Writeln('====================================================');
  Writeln('Origen referencia : ', oResultado.Origen);
  Writeln('Hora sistema (UTC): ',
    FormatDateTime('yyyy-mm-dd hh:nn:ss', dSistemaSim));
  Writeln('Hora oficial (UTC): ',
    FormatDateTime('yyyy-mm-dd hh:nn:ss', dReferenciaUtc));
  Writeln('Desfase           : ',
    FormatFloat('0.0', oResultado.DesfaseSegundos), ' s');
  Writeln('Margen legal      : ', oResultado.MargenSegundos, ' s');
  Writeln('');
  Writeln(oResultado.Resumen);
  Writeln('');

  // 5) Aplicamos la regla: ExigirReloj lanza una excepcion si NO se permite.
  try
    ExigirReloj(oResultado, 'Registro de facturacion NO VERI*FACTU');
    Writeln('=> El reloj es valido: se puede fechar y emitir el registro.');
  except
    on E: ERelojFiscalDesfasado do
    begin
      Writeln('=> DENEGADO. No se emite el registro NO VERI*FACTU.');
      Writeln('   ', E.Message);
      Halt(3);
    end;
  end;
end;

var
  sRutaIni: string;
begin
  try
    if ParamStr(1) <> '' then
      sRutaIni := ParamStr(1)
    else
      sRutaIni := ChangeFileExt(ParamStr(0), '.ini');
    Ejecutar(sRutaIni);
  except
    on E: Exception do
      Writeln('ERROR: ', E.ClassName, ': ', E.Message);
  end;
  Writeln('');
  Write('Pulsa Intro para salir...');
  Readln;
end.
