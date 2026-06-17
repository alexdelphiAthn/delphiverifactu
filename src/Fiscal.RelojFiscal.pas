{******************************************************************************}
{                                                                              }
{  Modulo:       Fiscal.RelojFiscal                                            }
{    Tipo:       Libreria Delphi (ejemplo didactico)                           }
{   Autor:       Alejandro Laorden Hidalgo                                     }
{                                                                              }
{  SPDX-License-Identifier: MIT                                                }
{                                                                              }
{  Descripcion:                                                                }
{    Control del reloj fiscal para registros NO VERI*FACTU. La Orden           }
{    HAC/1177/2024 exige que la fecha y hora con que se fechan los registros   }
{    de facturacion sean exactas con un margen maximo de UN MINUTO e incluyan  }
{    huso horario. Esta unidad compara el reloj del sistema con una hora de    }
{    referencia (la oficial) y DENIEGA si la diferencia supera el margen.      }
{                                                                              }
{    Solo depende de la RTL de Delphi:                                         }
{      - La logica de evaluacion (EvaluarReloj / ExigirReloj) es aritmetica    }
{        pura: no necesita red y se puede probar sin conexion.                 }
{      - Como fuente de hora de referencia se incluye una consulta HTTP        }
{        sencilla (cabecera 'Date' de la respuesta), util para el ejemplo.     }
{                                                                              }
{    En produccion (Factuzam) la hora de referencia se obtiene por NTP con     }
{    Indy TIdSNTP (src/Lib/inLibRelojFiscal.pas). El criterio de aceptacion    }
{    es el mismo: diferencia <= 60 s para permitir; en caso contrario, o si    }
{    no se puede comprobar la hora, se bloquea el registro fiscal.             }
{******************************************************************************}
unit Fiscal.RelojFiscal;

interface

uses
  System.SysUtils;

const
  // Margen legal: la diferencia entre el reloj del sistema y la hora oficial
  // no puede superar UN MINUTO. La normativa no permite ampliarlo: aunque se
  // configure un valor mayor, MargenLegalSegundos lo recorta a 60.
  cMargenRelojSegundos = 60;
  // Fuente de hora de referencia por defecto para el ejemplo (se lee la
  // cabecera 'Date' de la respuesta HTTP, que viaja en GMT/UTC).
  cServidorHoraDefecto = 'https://www.agenciatributaria.gob.es/';
  // Tiempo maximo de espera por la hora de red
  cTimeoutHoraDefectoMs = 2000;

type
  // Se lanza cuando el reloj no se puede comprobar o esta desfasado. El
  // llamador NO debe emitir el registro fiscal: debe conservar la operacion
  // sin cierre y dejar constancia de la incidencia de reloj.
  ERelojFiscalDesfasado = class(Exception);

  // Resultado de comprobar el reloj fiscal en un instante dado.
  TResultadoReloj = record
    Comprobado:        Boolean;    // True si se obtuvo una hora de referencia
    Origen:            string;     // 'RED', 'SIMULADO', 'MANUAL'...
    HoraSistemaUtc:    TDateTime;  // reloj del sistema, en UTC
    HoraReferenciaUtc: TDateTime;  // hora oficial de referencia, en UTC
    DesfaseSegundos:   Double;     // sistema - referencia (con signo)
    MargenSegundos:    Integer;    // margen aplicado (<= 60)
    DentroDeMargen:    Boolean;    // True si |Desfase| <= MargenSegundos
    Mensaje:           string;     // texto legible del resultado
    // True si se puede fechar un registro fiscal con este reloj.
    function Permitido: Boolean;
    // Resumen de una linea para mostrar por pantalla.
    function Resumen: string;
  end;

// Reloj del sistema convertido a UTC (la referencia tambien va en UTC para
// que la resta compare manzanas con manzanas).
function HoraSistemaUtc: TDateTime;
// Recorta el margen solicitado al maximo legal (60 s). Un valor <= 0 toma el
// valor legal por defecto; un valor mayor que 60 se limita a 60.
function MargenLegalSegundos(ASolicitado: Integer): Integer;
// Diferencia con signo (sistema - referencia) expresada en segundos.
function DesfaseEnSegundos(ASistemaUtc, AReferenciaUtc: TDateTime): Double;
// Evalua el reloj a partir de dos horas UTC ya conocidas. No usa red, asi
// que es ideal para ejemplos deterministas (incluido el caso de DENEGACION).
function EvaluarReloj(ASistemaUtc, AReferenciaUtc: TDateTime;
                      AMargenSegundos: Integer;
                      const AOrigen: string): TResultadoReloj;
// Aplica la regla legal: si el reloj no se comprobo o esta desfasado, lanza
// ERelojFiscalDesfasado con un mensaje claro (incluye contexto y segundos).
procedure ExigirReloj(const AResultado: TResultadoReloj;
                      const AContexto: string);
// Obtiene una hora de referencia en UTC leyendo la cabecera 'Date' de una
// respuesta HTTP. Devuelve False si no hay red o no se pudo interpretar.
function ObtenerHoraRedHttp(const AUrl: string; ATimeoutMs: Integer;
                            out AHoraUtc: TDateTime): Boolean;
// Atajo: obtiene la hora de red y evalua el reloj de una sola llamada. Si no
// hay red, devuelve un resultado con Comprobado = False (que ExigirReloj
// convierte en denegacion).
function ComprobarRelojRed(const AUrl: string; ATimeoutMs,
                           AMargenSegundos: Integer): TResultadoReloj;

implementation

uses
  System.DateUtils, System.StrUtils, System.TimeSpan,
  System.Net.HttpClient, System.Net.URLClient;

function HoraSistemaUtc: TDateTime;
begin
  // Now es la hora local; la pasamos a UTC con la zona horaria del equipo.
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

function MargenLegalSegundos(ASolicitado: Integer): Integer;
begin
  if ASolicitado <= 0 then
    Result := cMargenRelojSegundos
  else
    Result := ASolicitado;
  if Result > cMargenRelojSegundos then
    Result := cMargenRelojSegundos;
end;

function DesfaseEnSegundos(ASistemaUtc, AReferenciaUtc: TDateTime): Double;
begin
  // En Delphi un TDateTime es un numero de dias; la resta da dias y la
  // multiplicacion por 86400 los convierte en segundos (con decimales).
  Result := (ASistemaUtc - AReferenciaUtc) * 24 * 60 * 60;
end;

function EvaluarReloj(ASistemaUtc, AReferenciaUtc: TDateTime;
                      AMargenSegundos: Integer;
                      const AOrigen: string): TResultadoReloj;
begin
  Result.Comprobado        := True;
  Result.Origen            := AOrigen;
  Result.HoraSistemaUtc    := ASistemaUtc;
  Result.HoraReferenciaUtc := AReferenciaUtc;
  Result.MargenSegundos    := MargenLegalSegundos(AMargenSegundos);
  Result.DesfaseSegundos   := DesfaseEnSegundos(ASistemaUtc, AReferenciaUtc);
  Result.DentroDeMargen    :=
    Abs(Result.DesfaseSegundos) <= Result.MargenSegundos;
  if Result.DentroDeMargen then
    Result.Mensaje := Format(
      'Reloj dentro de margen: desfase %.1f s (margen %d s).',
      [Result.DesfaseSegundos, Result.MargenSegundos])
  else
    Result.Mensaje := Format(
      'Reloj DESFASADO: desfase %.1f s supera el margen de %d s.',
      [Result.DesfaseSegundos, Result.MargenSegundos]);
end;

procedure ExigirReloj(const AResultado: TResultadoReloj;
                      const AContexto: string);
begin
  if not AResultado.Comprobado then
    raise ERelojFiscalDesfasado.Create(
      'No se pudo comprobar el reloj fiscal para "' + AContexto +
      '". No se puede garantizar la exactitud legal de la hora, asi que el ' +
      'registro NO VERI*FACTU queda bloqueado. ' + AResultado.Mensaje);
  if not AResultado.DentroDeMargen then
    raise ERelojFiscalDesfasado.Create(
      'Reloj fiscal desfasado para "' + AContexto + '": ' +
      Format('%.1f', [AResultado.DesfaseSegundos]) + ' s de diferencia, ' +
      'por encima del margen legal de ' +
      IntToStr(AResultado.MargenSegundos) + ' s. ' +
      'Ajuste la hora del sistema antes de emitir el registro.');
end;

// --- Hora de referencia por HTTP (cabecera 'Date') -------------------------

// Convierte un nombre de mes ingles ('Jan'..'Dec') en su numero (1..12).
function MesIngles(const AMes: string): Integer;
const
  cMeses: array[1..12] of string = (
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC');
var
  i: Integer;
begin
  Result := 0;
  for i := 1 to 12 do
    if SameText(AMes, cMeses[i]) then
      Exit(i);
end;

// Interpreta una fecha HTTP en formato RFC 1123, p.ej.
// 'Tue, 17 Jun 2026 14:30:00 GMT'. La hora va en GMT, equivalente a UTC.
function ParsearFechaHttp(const AValor: string; out AHoraUtc: TDateTime):
  Boolean;
var
  oPartes: TArray<string>;
  oHora:   TArray<string>;
  iDia:    Integer;
  iMes:    Integer;
  iAnio:   Integer;
  iHh:     Integer;
  iMm:     Integer;
  iSs:     Integer;
  sLimpio: string;
begin
  Result := False;
  // Quitamos la coma del dia de la semana y normalizamos espacios.
  sLimpio := StringReplace(Trim(AValor), ',', '', [rfReplaceAll]);
  while Pos('  ', sLimpio) > 0 do
    sLimpio := StringReplace(sLimpio, '  ', ' ', [rfReplaceAll]);
  // Partes esperadas: [DiaSem] Dia Mes Anio Hora GMT
  oPartes := sLimpio.Split([' ']);
  if Length(oPartes) < 5 then
    Exit;
  iDia := StrToIntDef(oPartes[1], 0);
  iMes := MesIngles(oPartes[2]);
  iAnio := StrToIntDef(oPartes[3], 0);
  oHora := oPartes[4].Split([':']);
  if (iDia = 0) or (iMes = 0) or (iAnio = 0) or (Length(oHora) < 3) then
    Exit;
  iHh := StrToIntDef(oHora[0], -1);
  iMm := StrToIntDef(oHora[1], -1);
  iSs := StrToIntDef(oHora[2], -1);
  if (iHh < 0) or (iMm < 0) or (iSs < 0) then
    Exit;
  Result := TryEncodeDateTime(iAnio, iMes, iDia, iHh, iMm, iSs, 0, AHoraUtc);
end;

function ObtenerHoraRedHttp(const AUrl: string; ATimeoutMs: Integer;
                            out AHoraUtc: TDateTime): Boolean;
var
  oHttp:    THTTPClient;
  oResp:    IHTTPResponse;
  oHeader:  TNetHeader;
  sFecha:   string;
begin
  Result := False;
  AHoraUtc := 0;
  oHttp := THTTPClient.Create;
  try
    oHttp.ConnectionTimeout := ATimeoutMs;
    oHttp.ResponseTimeout   := ATimeoutMs;
    try
      // HEAD basta: solo nos interesa la cabecera 'Date' de la respuesta.
      oResp := oHttp.Head(AUrl);
      sFecha := '';
      for oHeader in oResp.Headers do
        if SameText(oHeader.Name, 'Date') then
          sFecha := oHeader.Value;
      if sFecha <> '' then
        Result := ParsearFechaHttp(sFecha, AHoraUtc);
    except
      // Sin red o servidor inalcanzable: se trata como "no comprobado".
      Result := False;
    end;
  finally
    FreeAndNil(oHttp);
  end;
end;

function ComprobarRelojRed(const AUrl: string; ATimeoutMs,
                           AMargenSegundos: Integer): TResultadoReloj;
var
  dReferencia: TDateTime;
begin
  if ObtenerHoraRedHttp(AUrl, ATimeoutMs, dReferencia) then
    Result := EvaluarReloj(HoraSistemaUtc, dReferencia, AMargenSegundos, 'RED')
  else
  begin
    // No se pudo obtener la hora: queda como NO comprobado para que
    // ExigirReloj lo trate como denegacion.
    Result := Default(TResultadoReloj);
    Result.Comprobado     := False;
    Result.Origen         := 'RED';
    Result.HoraSistemaUtc := HoraSistemaUtc;
    Result.MargenSegundos := MargenLegalSegundos(AMargenSegundos);
    Result.Mensaje        :=
      'No respondio la fuente de hora ' + AUrl + '.';
  end;
end;

{ TResultadoReloj }

function TResultadoReloj.Permitido: Boolean;
begin
  Result := Comprobado and DentroDeMargen;
end;

function TResultadoReloj.Resumen: string;
begin
  if Permitido then
    Result := 'PERMITIDO  | ' + Mensaje
  else
    Result := 'DENEGADO   | ' + Mensaje;
end;

end.
