{******************************************************************************}
{                                                                              }
{  Modulo:       Fiscal.NoVerifactu                                            }
{    Tipo:       Libreria Delphi (ejemplo didactico)                           }
{   Autor:       Alejandro Laorden Hidalgo                                     }
{                                                                              }
{  SPDX-License-Identifier: MIT                                                }
{                                                                              }
{  Descripcion:                                                                }
{    Construccion de los registros locales que exige el modo NO VERI*FACTU     }
{    (sistema de facturacion NO verificable, RD 1007/2023):                    }
{                                                                              }
{      1. REGISTRO DE EVENTOS del sistema (EventosSIF de la AEAT): inicio,     }
{         cierre, cambio de configuracion, exportacion, incidencias... Cada    }
{         evento se encadena por huella SHA-256 con el anterior.               }
{      2. REGISTRO DE FACTURACION: el RegistroAlta/RegistroAnulacion (el       }
{         mismo que en Veri*factu) pero, en lugar de enviarse a la AEAT, se    }
{         conserva en local firmado.                                          }
{                                                                              }
{    A diferencia de Veri*factu, en NO VERI*FACTU NO se envia nada a la AEAT:  }
{    los registros se guardan firmados y solo se exportan a XML cuando se      }
{    piden. La firma electronica (XAdES, politica AGE) es OBLIGATORIA; esta    }
{    unidad la delega en Fiscal.Xades. Sin certificado, los metodos generan    }
{    el XML con la huella SHA-256 como rastro tecnico/demo, NO valido como     }
{    cierre fiscal (equivale a appVerifactuFirmaCertificado = False).          }
{                                                                              }
{    Sin base de datos: la API trabaja con records y XML en memoria.           }
{******************************************************************************}
unit Fiscal.NoVerifactu;

interface

uses
  System.SysUtils, Fiscal.Xades;

const
  // Texto que se congela en el atributo ModoVerifactu del XML de exportacion,
  // para que una verificacion posterior no dependa de la configuracion actual.
  cModoNoVerifactu = 'NO_VERIFACTU';

  // Catalogo de eventos del sistema. El numero interno se traduce al codigo
  // oficial de la AEAT (EventosSIF) con TipoEventoAeat.
  cEventoInicio        = 1;   // AEAT 01 - Inicio del sistema  ("abrir programa")
  cEventoFin           = 2;   // AEAT 02 - Cierre del sistema  ("cerrar programa")
  cEventoCambioConfig  = 3;   // AEAT 03 - Cambio de configuracion ("cambio de parametros")
  cEventoExportFact    = 8;   // AEAT 08 - Exportacion del registro de facturacion
  cEventoExportEventos = 9;   // AEAT 09 - Exportacion del registro de eventos
  cEventoOtros         = 90;  // AEAT 90 - Evento voluntario / incidencia

  // Espacios de nombres oficiales
  cNsEventosSif =
    'https://www2.agenciatributaria.gob.es/static_files/common/internet/' +
    'dep/aplicaciones/es/aeat/tike/cont/ws/EventosSIF.xsd';
  cNsSuministroInformacion =
    'https://www2.agenciatributaria.gob.es/static_files/common/internet/' +
    'dep/aplicaciones/es/aeat/tike/cont/ws/SuministroInformacion.xsd';
  cNsDsig = 'http://www.w3.org/2000/09/xmldsig#';
  // Espacio de nombres propio de los contenedores de exportacion local
  cNsExportacionLocal = 'urn:ejemplo:no-verifactu:v1';

type
  // Datos del SISTEMA INFORMATICO (el software que emite) y del OBLIGADO a
  // emitir (la empresa). Son fijos para toda la sesion de eventos.
  TSistemaInformaticoSif = record
    NombreProductor:      string;  // razon social del fabricante del software
    NifProductor:         string;  // NIF del fabricante del software
    NombreSistema:        string;  // nombre comercial del programa
    IdSistema:            string;  // identificador del programa
    Version:              string;  // version del programa
    NumeroInstalacion:    string;  // numero de instalacion
    IndicadorMultiplesOT: string;  // 'S' si da servicio a varios obligados
    NombreObligado:       string;  // razon social de la empresa emisora
    NifObligado:          string;  // NIF de la empresa emisora
  end;

  // Un evento ya construido (y, si habia certificado, firmado).
  TEventoNoVerifactu = record
    Codigo:           Integer;                 // uno de los cEvento*
    TipoAeat:         string;                  // '01'..'90'
    Instante:         TDateTime;               // momento del evento
    FechaHoraHuso:    string;                  // con huso horario (legal)
    Descripcion:      string;
    DatosAdicionales: string;
    SerieFactura:     string;
    NumeroFactura:    string;
    HuellaAnterior:   string;                  // huella del evento previo
    HuellaPropia:     string;                  // SHA-256 de este evento
    Xml:              string;                  // <sf:RegistroEvento> base
    XmlFirmado:       string;                  // con <ds:Signature> dentro de Evento
    FirmaXades:       string;                  // SignatureValue (vacio en demo)
    DatosCertificado: TXadesDatosCertificado;  // certificado firmante
    Firmado:          Boolean;
  end;

  // Un registro de facturacion local (alta o anulacion), firmado.
  TRegistroFacturacionNoVerifactu = record
    Serie:            string;
    Numero:           string;
    TipoOperacion:    string;                  // 'ALTA' / 'ANULACION'
    Huella:           string;                  // huella del registro
    Xml:              string;                  // registro base (con namespaces)
    XmlFirmado:       string;                  // con <ds:Signature>
    FirmaXades:       string;                  // SignatureValue (vacio en demo)
    DatosCertificado: TXadesDatosCertificado;
    Firmado:          Boolean;
  end;

// Traduce el codigo interno de evento al codigo oficial de la AEAT.
function TipoEventoAeat(ACodigo: Integer): string;
// Instante con huso horario (yyyy-mm-ddThh:nn:ss+hh:mm) que exige la AEAT.
function FechaHoraHusoSif(ADt: TDateTime): string;

// --- Eventos ---------------------------------------------------------------

// Construye el XML base <sf:RegistroEvento> y devuelve su huella encadenada.
// AHuellaAnterior / ATipoAnterior / AFechaAnterior describen el evento previo
// ('' / '' / '' si es el primero).
function ConstruirXmlEvento(const ASif: TSistemaInformaticoSif;
                            ACodigo: Integer; AInstante: TDateTime;
                            const ADescripcion, ADatosAdicionales: string;
                            AEsPrimero: Boolean;
                            const AHuellaAnterior, ATipoAnterior,
                            AFechaAnterior: string;
                            out AHuella, AFechaHoraHuso: string): string;
// Firma un evento con XAdES (politica AGE). La firma se inserta DENTRO del
// nodo sf:Evento, como exige la AEAT. Requiere certificado en el almacen de
// Windows. Devuelve el XML firmado y, en AFirmaXades, el SignatureValue.
function FirmarEventoNoVerifactu(const AXmlEvento, AHuella, ASerialCert,
                                 ATitularCert: string;
                                 out ADatosCert: TXadesDatosCertificado;
                                 out AFirmaXades: string): string;

type
  // Libro de eventos: mantiene la cadena de huellas y, si se configura un
  // certificado, firma cada evento al registrarlo. Es la pieza que usan los
  // ejemplos: crear -> Registrar(...) por cada evento -> XmlExportacion.
  TLibroEventosNoVerifactu = class
  private
    FSif:            TSistemaInformaticoSif;
    FFirmar:         Boolean;
    FSerialCert:     string;
    FTitularCert:    string;
    FEsPrimero:      Boolean;
    FUltimaHuella:   string;
    FUltimoTipoAeat: string;
    FUltimaFecha:    string;
    FEventos:        TArray<TEventoNoVerifactu>;
  public
    constructor Create(const ASif: TSistemaInformaticoSif);
    // Activa la firma XAdES con el certificado indicado (almacen de Windows).
    // Si no se llama, el libro funciona en modo demo (solo huella SHA-256).
    procedure ConfigurarFirma(const ASerialCert, ATitularCert: string);
    // Registra un evento, lo encadena con el anterior y lo firma si procede.
    function Registrar(ACodigo: Integer; const ADescripcion: string;
                       const ADatosAdicionales: string = '';
                       const ASerie: string = '';
                       const ANumero: string = '';
                       AInstante: TDateTime = 0): TEventoNoVerifactu;
    // XML del registro de eventos completo (contenedor con cada evento
    // firmado embebido en CDATA). NO se firma el contenedor: la firma legal
    // vive en cada <sf:RegistroEvento>.
    function XmlExportacion(const AVersion: string = '1.0.0';
                            const AUsuario: string = ''): string;
    property Firmar: Boolean read FFirmar;
    property UltimaHuella: string read FUltimaHuella;
    property Eventos: TArray<TEventoNoVerifactu> read FEventos;
  end;

// --- Facturacion -----------------------------------------------------------

// Envuelve el fragmento <sum1:RegistroAlta>/<sum1:RegistroAnulacion> (el que
// produce Fiscal.EnvioVerifactu) como documento XML autonomo y firmable,
// anadiendo los namespaces sum1 y ds. ATipoOperacion: 'ALTA' o 'ANULACION'.
function EnvolverRegistroFacturacion(const ARegistro,
                                     ATipoOperacion: string): string;
// Firma el registro de facturacion con XAdES (politica AGE) en su nodo raiz
// (RegistroAlta/RegistroAnulacion). Requiere certificado de Windows.
function FirmarRegistroFacturacion(const ARegistroXml, ATipoOperacion,
                                   AHuella, ASerialCert, ATitularCert: string;
                                   out ADatosCert: TXadesDatosCertificado;
                                   out AFirmaXades: string): string;
// Contenedor <RegistroFacturacionNoVerifactu> con la lista de registros ya
// firmados (cada registro va embebido en CDATA, como en la exportacion real).
function XmlExportacionFacturacion(
  const ARegistros: TArray<TRegistroFacturacionNoVerifactu>;
  const AVersion: string = '1.0.0'; const AUsuario: string = ''): string;

implementation

uses
  System.Hash, System.StrUtils,
  Fiscal.EnvioVerifactu;

// --- Helpers de texto y hash -----------------------------------------------

function EscaparXml(const AValor: string): string;
begin
  Result := StringReplace(AValor,  '&', '&amp;',  [rfReplaceAll]);
  Result := StringReplace(Result,  '<', '&lt;',   [rfReplaceAll]);
  Result := StringReplace(Result,  '>', '&gt;',   [rfReplaceAll]);
  Result := StringReplace(Result,  '"', '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, '''', '&apos;', [rfReplaceAll]);
end;

// Encierra un texto en CDATA, neutralizando la unica secuencia prohibida.
function CData(const AValor: string): string;
begin
  Result := '<![CDATA[' +
            StringReplace(AValor, ']]>', ']]]]><![CDATA[>', [rfReplaceAll]) +
            ']]>';
end;

function Sha256HexMayus(const AValor: string): string;
begin
  Result := UpperCase(THashSHA2.GetHashString(AValor));
end;

// Normaliza el texto de un evento: una sola linea, sin espacios dobles y como
// mucho 100 caracteres (limite del campo OtrosDatosEvento).
function TextoEventoSif(const AValor: string): string;
begin
  Result := Trim(AValor);
  Result := StringReplace(Result, #13, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
  while Pos('  ', Result) > 0 do
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
  if Length(Result) > 100 then
    Result := Copy(Result, 1, 100);
end;

function TipoEventoAeat(ACodigo: Integer): string;
begin
  case ACodigo of
    cEventoInicio:        Result := '01';
    cEventoFin:           Result := '02';
    cEventoCambioConfig:  Result := '03';
    cEventoExportFact:    Result := '08';
    cEventoExportEventos: Result := '09';
  else
    Result := '90';
  end;
end;

function FechaHoraHusoSif(ADt: TDateTime): string;
begin
  // Mismo formato con huso horario que el registro de facturacion.
  Result := FechaHoraHusoGen(ADt);
end;

// --- Construccion del XML de evento (EventosSIF) ---------------------------

function BloqueSistemaInformatico(const ASif: TSistemaInformaticoSif): string;
var
  sMultiOT: string;
begin
  if SameText(Trim(ASif.IndicadorMultiplesOT), 'S') then
    sMultiOT := 'S'
  else
    sMultiOT := 'N';
  Result :=
    '<sf:SistemaInformatico>' +
    '<sf:NombreRazon>' + EscaparXml(ASif.NombreProductor) +
    '</sf:NombreRazon>' +
    '<sf:NIF>' + EscaparXml(NormalizarNif(ASif.NifProductor)) + '</sf:NIF>' +
    '<sf:NombreSistemaInformatico>' + EscaparXml(ASif.NombreSistema) +
    '</sf:NombreSistemaInformatico>' +
    '<sf:IdSistemaInformatico>' + EscaparXml(ASif.IdSistema) +
    '</sf:IdSistemaInformatico>' +
    '<sf:Version>' + EscaparXml(ASif.Version) + '</sf:Version>' +
    '<sf:NumeroInstalacion>' + EscaparXml(ASif.NumeroInstalacion) +
    '</sf:NumeroInstalacion>' +
    '<sf:TipoUsoPosibleSoloVerifactu>N</sf:TipoUsoPosibleSoloVerifactu>' +
    '<sf:TipoUsoPosibleMultiOT>S</sf:TipoUsoPosibleMultiOT>' +
    '<sf:IndicadorMultiplesOT>' + sMultiOT + '</sf:IndicadorMultiplesOT>' +
    '</sf:SistemaInformatico>';
end;

function BloqueObligado(const ASif: TSistemaInformaticoSif): string;
begin
  Result :=
    '<sf:ObligadoEmision>' +
    '<sf:NombreRazon>' + EscaparXml(ASif.NombreObligado) +
    '</sf:NombreRazon>' +
    '<sf:NIF>' + EscaparXml(NormalizarNif(ASif.NifObligado)) + '</sf:NIF>' +
    '</sf:ObligadoEmision>';
end;

function BloqueEncadenamiento(AEsPrimero: Boolean; const ATipoAnterior,
                              AFechaAnterior, AHuellaAnterior: string): string;
begin
  if AEsPrimero then
    Result := '<sf:Encadenamiento><sf:PrimerEvento>S</sf:PrimerEvento>' +
              '</sf:Encadenamiento>'
  else
    Result := '<sf:Encadenamiento><sf:EventoAnterior>' +
      '<sf:TipoEvento>' + ATipoAnterior + '</sf:TipoEvento>' +
      '<sf:FechaHoraHusoGenEvento>' + AFechaAnterior +
      '</sf:FechaHoraHusoGenEvento>' +
      '<sf:HuellaEvento>' + AHuellaAnterior + '</sf:HuellaEvento>' +
      '</sf:EventoAnterior></sf:Encadenamiento>';
end;

function ConstruirXmlEvento(const ASif: TSistemaInformaticoSif;
                            ACodigo: Integer; AInstante: TDateTime;
                            const ADescripcion, ADatosAdicionales: string;
                            AEsPrimero: Boolean;
                            const AHuellaAnterior, ATipoAnterior,
                            AFechaAnterior: string;
                            out AHuella, AFechaHoraHuso: string): string;
var
  sTipoAeat: string;
  sOtros:    string;
  sBaseHash: string;
begin
  sTipoAeat := TipoEventoAeat(ACodigo);
  AFechaHoraHuso := FechaHoraHusoSif(AInstante);
  sOtros := TextoEventoSif(ADescripcion + ' ' + ADatosAdicionales);
  // Huella SHA-256 del evento: campos clave separados por '&' y encadenados
  // con la huella del evento anterior. El orden NO se puede alterar.
  sBaseHash := 'TipoEvento=' + sTipoAeat +
               '&FechaHoraHusoGenEvento=' + AFechaHoraHuso +
               '&OtrosDatosEvento=' + sOtros +
               '&HuellaEventoAnterior=' + AHuellaAnterior;
  AHuella := Sha256HexMayus(sBaseHash);
  Result :=
    '<?xml version="1.0" encoding="UTF-8"?>' +
    '<sf:RegistroEvento xmlns:sf="' + cNsEventosSif +
    '" xmlns:ds="' + cNsDsig + '">' +
    '<sf:IDVersion>1.0</sf:IDVersion>' +
    '<sf:Evento>' +
    BloqueSistemaInformatico(ASif) +
    BloqueObligado(ASif) +
    '<sf:FechaHoraHusoGenEvento>' + AFechaHoraHuso +
    '</sf:FechaHoraHusoGenEvento>' +
    '<sf:TipoEvento>' + sTipoAeat + '</sf:TipoEvento>';
  if sOtros <> '' then
    Result := Result + '<sf:OtrosDatosEvento>' + EscaparXml(sOtros) +
              '</sf:OtrosDatosEvento>';
  Result := Result +
    BloqueEncadenamiento(AEsPrimero, ATipoAnterior, AFechaAnterior,
                         AHuellaAnterior) +
    '<sf:TipoHuella>01</sf:TipoHuella>' +
    '<sf:HuellaEvento>' + AHuella + '</sf:HuellaEvento>' +
    '</sf:Evento></sf:RegistroEvento>';
end;

function FirmarEventoNoVerifactu(const AXmlEvento, AHuella, ASerialCert,
                                 ATitularCert: string;
                                 out ADatosCert: TXadesDatosCertificado;
                                 out AFirmaXades: string): string;
var
  oOpciones: TXadesOpciones;
begin
  // Politica AGE para NO VERI*FACTU; la firma se inserta dentro de sf:Evento.
  oOpciones := OpcionesXadesNoVerifactu('FZ-EVENTO-' + AHuella);
  oOpciones.NombreNodoInsercionFirma := 'sf:Evento';
  oOpciones.FirmaSilenciosa := False;
  Result := FirmarXmlXadesEnveloped(AXmlEvento, ASerialCert, ATitularCert,
                                    oOpciones, ADatosCert);
  AFirmaXades := ExtraerEtiqueta(Result, 'SignatureValue');
end;

{ TLibroEventosNoVerifactu }

constructor TLibroEventosNoVerifactu.Create(
  const ASif: TSistemaInformaticoSif);
begin
  inherited Create;
  FSif := ASif;
  FFirmar := False;
  FEsPrimero := True;
  FUltimaHuella := '';
  FUltimoTipoAeat := '';
  FUltimaFecha := '';
  SetLength(FEventos, 0);
end;

procedure TLibroEventosNoVerifactu.ConfigurarFirma(const ASerialCert,
  ATitularCert: string);
begin
  FSerialCert := ASerialCert;
  FTitularCert := ATitularCert;
  FFirmar := (Trim(ASerialCert) <> '') or (Trim(ATitularCert) <> '');
end;

function TLibroEventosNoVerifactu.Registrar(ACodigo: Integer;
  const ADescripcion: string; const ADatosAdicionales, ASerie,
  ANumero: string; AInstante: TDateTime): TEventoNoVerifactu;
var
  oEvento: TEventoNoVerifactu;
begin
  oEvento := Default(TEventoNoVerifactu);
  if AInstante = 0 then
    AInstante := Now;
  oEvento.Codigo := ACodigo;
  oEvento.TipoAeat := TipoEventoAeat(ACodigo);
  oEvento.Instante := AInstante;
  oEvento.Descripcion := ADescripcion;
  oEvento.DatosAdicionales := ADatosAdicionales;
  oEvento.SerieFactura := ASerie;
  oEvento.NumeroFactura := ANumero;
  // Primer evento: huella anterior a cero (64 ceros), como exige la cadena.
  if FEsPrimero then
    oEvento.HuellaAnterior := StringOfChar('0', 64)
  else
    oEvento.HuellaAnterior := FUltimaHuella;
  oEvento.Xml := ConstruirXmlEvento(FSif, ACodigo, AInstante, ADescripcion,
    ADatosAdicionales, FEsPrimero, FUltimaHuella, FUltimoTipoAeat,
    FUltimaFecha, oEvento.HuellaPropia, oEvento.FechaHoraHuso);
  oEvento.XmlFirmado := oEvento.Xml;
  oEvento.FirmaXades := '';
  oEvento.Firmado := False;
  if FFirmar then
  begin
    // Firma XAdES real: si falla (sin certificado, caducado, cancelado...)
    // la excepcion sube al llamador. NO se hace fallback a SHA-256, porque
    // dejaria un registro no verificable sin la firma exigible.
    oEvento.XmlFirmado := FirmarEventoNoVerifactu(oEvento.Xml,
      oEvento.HuellaPropia, FSerialCert, FTitularCert,
      oEvento.DatosCertificado, oEvento.FirmaXades);
    oEvento.Firmado := True;
  end;
  // Avanzamos la cadena para el siguiente evento.
  FUltimaHuella := oEvento.HuellaPropia;
  FUltimoTipoAeat := oEvento.TipoAeat;
  FUltimaFecha := oEvento.FechaHoraHuso;
  FEsPrimero := False;
  FEventos := FEventos + [oEvento];
  Result := oEvento;
end;

function TLibroEventosNoVerifactu.XmlExportacion(const AVersion,
  AUsuario: string): string;
var
  oSb:      TStringBuilder;
  oEvento:  TEventoNoVerifactu;
  i:        Integer;
  sFirmaDigital: string;
begin
  oSb := TStringBuilder.Create;
  try
    oSb.Append('<?xml version="1.0" encoding="UTF-8"?>');
    oSb.Append('<RegistroEventosNoVerifactu xmlns="' + cNsExportacionLocal +
      '" Generado="' + EscaparXml(FechaHoraHusoSif(Now)) +
      '" Version="' + EscaparXml(AVersion) +
      '" Usuario="' + EscaparXml(AUsuario) +
      '" ModoVerifactu="' + cModoNoVerifactu + '">');
    for i := 0 to High(FEventos) do
    begin
      oEvento := FEventos[i];
      // FirmaDigital: si el evento esta firmado, SHA-256 de la firma XAdES;
      // si es demo, la propia huella del evento.
      if oEvento.Firmado then
        sFirmaDigital := Sha256HexMayus(oEvento.FirmaXades)
      else
        sFirmaDigital := oEvento.HuellaPropia;
      oSb.Append('<Evento>');
      oSb.Append('<Id>' + IntToStr(i + 1) + '</Id>');
      oSb.Append('<Instante>' + EscaparXml(oEvento.FechaHoraHuso) +
        '</Instante>');
      oSb.Append('<Tipo>' + IntToStr(oEvento.Codigo) + '</Tipo>');
      oSb.Append('<TipoAeat>' + oEvento.TipoAeat + '</TipoAeat>');
      oSb.Append('<Descripcion>' + CData(oEvento.Descripcion) +
        '</Descripcion>');
      if oEvento.DatosAdicionales <> '' then
        oSb.Append('<DatosAdicionales>' + CData(oEvento.DatosAdicionales) +
          '</DatosAdicionales>');
      if oEvento.SerieFactura <> '' then
        oSb.Append('<SerieFactura>' + EscaparXml(oEvento.SerieFactura) +
          '</SerieFactura>');
      if oEvento.NumeroFactura <> '' then
        oSb.Append('<NumeroFactura>' + EscaparXml(oEvento.NumeroFactura) +
          '</NumeroFactura>');
      oSb.Append('<HashAnterior>' + oEvento.HuellaAnterior +
        '</HashAnterior>');
      oSb.Append('<HashPropio>' + oEvento.HuellaPropia + '</HashPropio>');
      oSb.Append('<FirmaDigital>' + sFirmaDigital + '</FirmaDigital>');
      oSb.Append('<Firmado>' + IfThen(oEvento.Firmado, 'S', 'N') +
        '</Firmado>');
      oSb.Append('<RegistroXmlFirmado>' + CData(oEvento.XmlFirmado) +
        '</RegistroXmlFirmado>');
      if oEvento.FirmaXades <> '' then
        oSb.Append('<FirmaXades>' + CData(oEvento.FirmaXades) +
          '</FirmaXades>');
      if oEvento.DatosCertificado.NumeroSerie <> '' then
        oSb.Append('<SerieCertificado>' +
          EscaparXml(oEvento.DatosCertificado.NumeroSerie) +
          '</SerieCertificado>');
      if oEvento.DatosCertificado.Titular <> '' then
        oSb.Append('<TitularCertificado>' +
          EscaparXml(oEvento.DatosCertificado.Titular) +
          '</TitularCertificado>');
      if oEvento.DatosCertificado.HuellaSha1 <> '' then
        oSb.Append('<HuellaCertificado>' +
          EscaparXml(oEvento.DatosCertificado.HuellaSha1) +
          '</HuellaCertificado>');
      oSb.Append('</Evento>');
    end;
    oSb.Append('</RegistroEventosNoVerifactu>');
    Result := oSb.ToString;
  finally
    FreeAndNil(oSb);
  end;
end;

// --- Facturacion -----------------------------------------------------------

function RaizRegistroFacturacion(const ATipoOperacion: string): string;
begin
  if SameText(ATipoOperacion, 'ANULACION') then
    Result := 'RegistroAnulacion'
  else
    Result := 'RegistroAlta';
end;

function EnvolverRegistroFacturacion(const ARegistro,
                                     ATipoOperacion: string): string;
var
  sRaiz:          string;
  sApertura:      string;
  sNuevaApertura: string;
begin
  // El registro llega como fragmento <sum1:RegistroAlta>...; le ponemos los
  // namespaces en la etiqueta raiz para que sea un documento firmable.
  sRaiz := RaizRegistroFacturacion(ATipoOperacion);
  sApertura := '<sum1:' + sRaiz + '>';
  sNuevaApertura := '<sum1:' + sRaiz + ' xmlns:sum1="' +
    cNsSuministroInformacion + '" xmlns:ds="' + cNsDsig + '">';
  Result := StringReplace(ARegistro, sApertura, sNuevaApertura, []);
  Result := '<?xml version="1.0" encoding="UTF-8"?>' + Result;
end;

function FirmarRegistroFacturacion(const ARegistroXml, ATipoOperacion,
                                   AHuella, ASerialCert, ATitularCert: string;
                                   out ADatosCert: TXadesDatosCertificado;
                                   out AFirmaXades: string): string;
var
  oOpciones: TXadesOpciones;
  sXml:      string;
begin
  sXml := EnvolverRegistroFacturacion(ARegistroXml, ATipoOperacion);
  // Politica AGE; la firma envuelve el propio RegistroAlta/RegistroAnulacion.
  oOpciones := OpcionesXadesNoVerifactu('FZ-FACTURA-' + AHuella);
  oOpciones.FirmaSilenciosa := False;
  Result := FirmarXmlXadesEnveloped(sXml, ASerialCert, ATitularCert,
                                    oOpciones, ADatosCert);
  AFirmaXades := ExtraerEtiqueta(Result, 'SignatureValue');
end;

function XmlExportacionFacturacion(
  const ARegistros: TArray<TRegistroFacturacionNoVerifactu>;
  const AVersion, AUsuario: string): string;
var
  oSb: TStringBuilder;
  i:   Integer;
begin
  oSb := TStringBuilder.Create;
  try
    oSb.Append('<?xml version="1.0" encoding="UTF-8"?>');
    oSb.Append('<RegistroFacturacionNoVerifactu xmlns="' +
      cNsExportacionLocal +
      '" Generado="' + EscaparXml(FechaHoraHusoSif(Now)) +
      '" Version="' + EscaparXml(AVersion) +
      '" Usuario="' + EscaparXml(AUsuario) +
      '" ModoVerifactu="' + cModoNoVerifactu + '">');
    for i := 0 to High(ARegistros) do
    begin
      oSb.Append('<RegistroFactura>');
      oSb.Append('<Id>' + IntToStr(i + 1) + '</Id>');
      oSb.Append('<Serie>' + EscaparXml(ARegistros[i].Serie) + '</Serie>');
      oSb.Append('<Numero>' + EscaparXml(ARegistros[i].Numero) +
        '</Numero>');
      oSb.Append('<TipoOperacion>' + EscaparXml(ARegistros[i].TipoOperacion) +
        '</TipoOperacion>');
      oSb.Append('<Huella>' + ARegistros[i].Huella + '</Huella>');
      oSb.Append('<Firmado>' + IfThen(ARegistros[i].Firmado, 'S', 'N') +
        '</Firmado>');
      oSb.Append('<RegistroXmlFirmado>' + CData(ARegistros[i].XmlFirmado) +
        '</RegistroXmlFirmado>');
      if ARegistros[i].FirmaXades <> '' then
        oSb.Append('<FirmaDigitalXades>' + CData(ARegistros[i].FirmaXades) +
          '</FirmaDigitalXades>');
      if ARegistros[i].DatosCertificado.NumeroSerie <> '' then
        oSb.Append('<SerieCertificado>' +
          EscaparXml(ARegistros[i].DatosCertificado.NumeroSerie) +
          '</SerieCertificado>');
      if ARegistros[i].DatosCertificado.Titular <> '' then
        oSb.Append('<TitularCertificado>' +
          EscaparXml(ARegistros[i].DatosCertificado.Titular) +
          '</TitularCertificado>');
      if ARegistros[i].DatosCertificado.HuellaSha1 <> '' then
        oSb.Append('<HuellaCertificado>' +
          EscaparXml(ARegistros[i].DatosCertificado.HuellaSha1) +
          '</HuellaCertificado>');
      oSb.Append('</RegistroFactura>');
    end;
    oSb.Append('</RegistroFacturacionNoVerifactu>');
    Result := oSb.ToString;
  finally
    FreeAndNil(oSb);
  end;
end;

end.
