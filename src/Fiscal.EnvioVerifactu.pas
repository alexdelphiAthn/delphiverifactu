{******************************************************************************}
{                                                                              }
{  Modulo:       Fiscal.EnvioVerifactu                                          }
{    Tipo:       Libreria (ejemplo didactico)                                   }
{ Version:       1.0.0                                                          }
{   Fecha:       17/06/2026                                                     }
{   Autor:       Alejandro Laorden Hidalgo                                      }
{                                                                              }
{  Descripcion:                                                                 }
{    Ejemplo autocontenido de como construir y enviar a la AEAT un registro     }
{    de facturacion Veri*factu (alta) a partir de una factura estilo Factuzam.  }
{    Solo depende de la RTL de Delphi. La libreria:                             }
{      1. Compone el XML del RegistroAlta (esquemas SuministroLR/Informacion).  }
{      2. Calcula la huella SHA-256 encadenada (cada factura enlaza con la      }
{         huella de la anterior del mismo emisor).                              }
{      3. Construye la URL de cotejo del QR tributario (Orden HAC/1177/2024).   }
{      4. Envuelve el registro en un sobre SOAP y lo remite por HTTPS con el    }
{         certificado de la empresa emisora (almacen de Windows).               }
{                                                                              }
{    Version simplificada del subsistema de produccion                          }
{    (src/verifactu/inLibVerifactuEnvio.pas). NO cubre: rectificativas R1/R5    }
{    con factura original, operaciones exentas, recargo de equivalencia,        }
{    clientes extranjeros ni firma XAdES. Para esos casos ver el codigo real.   }
{******************************************************************************}
unit Fiscal.EnvioVerifactu;

interface

uses
  System.SysUtils;

type
  // Una banda de IVA del desglose (un tipo impositivo y su base/cuota)
  TBandaIva = record
    Porcentaje: Currency;
    Base:       Currency;
    Cuota:      Currency;
  end;

  // Factura a comunicar. Los campos calcan las columnas de fza_facturas
  // (ver el comentario al lado de cada uno) para que el mapeo sea directo.
  TFacturaVerifactu = record
    Serie:                string;        // SERIE_FAC
    Numero:               string;        // NUMERO_FAC
    Fecha:                TDateTime;     // FECHA_FAC
    Tipo:                 string;        // TIPO_FAC (NORMAL/SIMPLIFICADA...)
    NifEmisor:            string;        // NIF_EMPRESA_FAC
    NombreEmisor:         string;        // RAZON_SOCIAL_EMPRESA_FAC
    NifCliente:           string;        // NIF_CLIENTE_FAC
    NombreCliente:        string;        // RAZON_SOCIAL_CLIENTE_FAC
    DescripcionOperacion: string;        // texto libre de la operacion
    Bandas:               TArray<TBandaIva>;
    // Tipo de factura segun el catalogo Verifactu (F1/F2/R1...)
    function TipoVerifactu: string;
    // Fecha de expedicion en el formato dd-mm-aaaa que exige la AEAT
    function FechaExpedicionTexto: string;
    // Suma de las cuotas de IVA de todas las bandas (CuotaTotal AEAT)
    function CuotaTotal: Currency;
    // Suma de bases + cuotas de todas las bandas (ImporteTotal AEAT)
    function ImporteTotal: Currency;
    // Anade una banda calculando la cuota = base * porcentaje / 100
    procedure AnadirBanda(APorcentaje, ABase: Currency);
  end;

  // Ultimo eslabon de la cadena de huellas del emisor. Mapea las columnas
  // de fza_verifactu_cadena. Para el PRIMER registro, dejar Huella vacia.
  TEslabonCadena = record
    Serie:  string;        // SERIE_FAC_VFCAD
    Numero: string;        // NUMERO_FAC_VFCAD
    Fecha:  string;        // FECHA_FAC_VFCAD en formato dd-mm-aaaa
    Huella: string;        // HUELLA_VFCAD ('' si es el primer registro)
  end;

  // Resultado de construir el registro de alta listo para enviar
  TRegistroVerifactu = record
    NumSerieFactura:  string;
    FechaHoraHusoGen: string;
    Huella:           string;
    CuotaTotal:       Currency;
    ImporteTotal:     Currency;
    XmlRegistro:      string;     // <sum1:RegistroAlta>...</sum1:RegistroAlta>
    XmlSoap:          string;     // sobre SOAP completo a remitir
    UrlQR:            string;     // URL de cotejo del QR tributario
  end;

const
  // Endpoints oficiales del servicio SOAP de Veri*factu
  cVerifactuUrlEnvioPre =
    'https://prewww1.aeat.es/wlpl/TIKE-CONT/ws/SistemaFacturacion/' +
    'VerifactuSOAP';
  cVerifactuUrlEnvioPro =
    'https://www1.agenciatributaria.gob.es/wlpl/TIKE-CONT/ws/' +
    'SistemaFacturacion/VerifactuSOAP';
  // Servicio de cotejo para el QR tributario
  cVerifactuUrlQRPre =
    'https://prewww2.aeat.es/wlpl/TIKE-CONT/ValidarQR';
  cVerifactuUrlQRPro =
    'https://www2.agenciatributaria.gob.es/wlpl/TIKE-CONT/ValidarQR';

// NIF normalizado (solo letras/digitos en mayusculas). El MISMO valor
// viaja en el QR y en el registro: ojo con guiones y espacios.
function NormalizarNif(const AValor: string): string;
// Importe con 2 decimales y punto como separador (formato AEAT)
function FormatearImporte(AImporte: Currency): string;
// Instante de generacion con huso horario (yyyy-mm-ddThh:nn:ss+hh:mm)
function FechaHoraHusoGen(ADt: TDateTime): string;
// Identificador serie+numero que viaja a la AEAT (concatenacion directa)
function ComponerNumSerieFactura(const ASerie, ANumero: string): string;
// Mapea TIPO_FAC de Factuzam al catalogo de tipos de factura Verifactu
function TipoFacturaVerifactu(const ATipo: string): string;
// URL completa de cotejo del QR tributario para una factura
function ConstruirUrlQR(const ANif, ASerie, ANumero: string;
                        AFecha: TDateTime; AImporteTotal: Currency;
                        AEntornoPro: Boolean = False): string;
// Bloque <SistemaInformatico> con los datos del productor del software
function ConstruirSistemaInformatico(const ANombreProductor, ANifProductor,
                                     ANombreSistema, AIdSistema, AVersion,
                                     ANumeroInstalacion: string): string;
// Huella SHA-256 (hex mayuscula) del registro de alta segun la AEAT
function CalcularHuellaAlta(const AFactura: TFacturaVerifactu;
                           const AAnterior: TEslabonCadena;
                           const AFechaHoraHusoGen: string): string;
// XML del <RegistroAlta> completo. Devuelve tambien su huella en AHuella.
function ConstruirRegistroAlta(const AFactura: TFacturaVerifactu;
                              const AAnterior: TEslabonCadena;
                              const ASistemaInformatico,
                              AFechaHoraHusoGen: string;
                              out AHuella: string): string;
// Envuelve el registro en el sobre SOAP RegFactuSistemaFacturacion
function EnvolverSoap(const AFactura: TFacturaVerifactu;
                     const ARegistro: string): string;
// Atajo: construye huella + XML + SOAP + URL del QR de una sola llamada
function PrepararRegistroAlta(const AFactura: TFacturaVerifactu;
                            const AAnterior: TEslabonCadena;
                            const ASistemaInformatico: string;
                            AEntornoPro: Boolean = False): TRegistroVerifactu;
// Remite el sobre SOAP a la AEAT con el certificado de cliente indicado.
// Devuelve True si la respuesta HTTP es 200 (revisar luego EstadoEnvio).
function EnviarSoapAeat(const AUrl, AXmlSoap, ASerieCertificado,
                       ATitularCertificado: string;
                       out AStatus: Integer; out ARespuesta: string): Boolean;
// Extrae el contenido de la primera etiqueta XML con ese nombre local
function ExtraerEtiqueta(const AXml, AEtiqueta: string): string;

implementation

uses
  System.Classes, System.StrUtils, System.Hash, System.DateUtils,
  System.TimeSpan, System.Net.HttpClient, System.Net.URLClient;

const
  cNsSoap = 'http://schemas.xmlsoap.org/soap/envelope/';
  cNsLR =
    'https://www2.agenciatributaria.gob.es/static_files/common/internet/' +
    'dep/aplicaciones/es/aeat/tike/cont/ws/SuministroLR.xsd';
  cNsInf =
    'https://www2.agenciatributaria.gob.es/static_files/common/internet/' +
    'dep/aplicaciones/es/aeat/tike/cont/ws/SuministroInformacion.xsd';

type
  // Selecciona el certificado de cliente en la negociacion TLS: primero
  // por numero de serie (en su orden de bytes o el inverso) y, si no, por
  // titular dentro del Subject.
  TSelectorCertificado = class
  private
    FSerial:  string;
    FTitular: string;
  public
    constructor Create(const ASerial, ATitular: string);
    procedure Seleccionar(const Sender: TObject;
                          const ARequest: TURLRequest;
                          const ACertificateList: TCertificateList;
                          var AnIndex: Integer);
  end;

function EscaparXml(const AValor: string): string;
begin
  Result := StringReplace(AValor,  '&', '&amp;',  [rfReplaceAll]);
  Result := StringReplace(Result,  '<', '&lt;',   [rfReplaceAll]);
  Result := StringReplace(Result,  '>', '&gt;',   [rfReplaceAll]);
  Result := StringReplace(Result,  '"', '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, '''', '&apos;', [rfReplaceAll]);
end;

function NormalizarNif(const AValor: string): string;
var
  cActual: Char;
begin
  Result := '';
  for cActual in UpperCase(Trim(AValor)) do
  begin
    if ((cActual >= 'A') and (cActual <= 'Z')) or
       ((cActual >= '0') and (cActual <= '9')) then
      Result := Result + cActual;
  end;
end;

function FormatearImporte(AImporte: Currency): string;
var
  oFmt: TFormatSettings;
begin
  oFmt := TFormatSettings.Create;
  oFmt.DecimalSeparator  := '.';
  oFmt.ThousandSeparator := #0;
  Result := FormatFloat('0.00', AImporte, oFmt);
end;

function FechaHoraHusoGen(ADt: TDateTime): string;
var
  oDesfase: TTimeSpan;
  sSigno:   string;
begin
  oDesfase := TTimeZone.Local.GetUtcOffset(ADt);
  if oDesfase.Ticks < 0 then
    sSigno := '-'
  else
    sSigno := '+';
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', ADt) + sSigno +
            Format('%.2d:%.2d', [Abs(oDesfase.Hours),
                                 Abs(oDesfase.Minutes)]);
end;

function ComponerNumSerieFactura(const ASerie, ANumero: string): string;
begin
  // Concatenacion simple serie+numero. El QR y el registro DEBEN llevar
  // exactamente el mismo valor; si se cambia aqui, cambia en los dos.
  Result := Trim(ASerie) + Trim(ANumero);
end;

function TipoFacturaVerifactu(const ATipo: string): string;
begin
  // F1 completa, F2 simplificada (ticket), R1 rectificativa por sustitucion.
  // El codigo real distingue R1/R5 segun el tipo de la factura original.
  if SameText(ATipo, 'SIMPLIFICADA') then
    Result := 'F2'
  else if SameText(ATipo, 'RECTIFICATIVA') then
    Result := 'R1'
  else
    Result := 'F1';
end;

// Percent-encode (RFC 3986): solo quedan sin codificar los no reservados
function CodificarParametroURL(const AValor: string): string;
var
  aBytes:  TBytes;
  iOcteto: Byte;
  oSalida: TStringBuilder;
begin
  oSalida := TStringBuilder.Create;
  try
    aBytes := TEncoding.UTF8.GetBytes(AValor);
    for iOcteto in aBytes do
    begin
      if ((iOcteto >= Ord('A')) and (iOcteto <= Ord('Z'))) or
         ((iOcteto >= Ord('a')) and (iOcteto <= Ord('z'))) or
         ((iOcteto >= Ord('0')) and (iOcteto <= Ord('9'))) or
         (iOcteto = Ord('-')) or (iOcteto = Ord('.')) or
         (iOcteto = Ord('_')) or (iOcteto = Ord('~')) then
        oSalida.Append(Char(iOcteto))
      else
        oSalida.Append('%' + IntToHex(iOcteto, 2));
    end;
    Result := oSalida.ToString;
  finally
    FreeAndNil(oSalida);
  end;
end;

function ConstruirUrlQR(const ANif, ASerie, ANumero: string;
                        AFecha: TDateTime; AImporteTotal: Currency;
                        AEntornoPro: Boolean): string;
var
  sBase: string;
begin
  if AEntornoPro then
    sBase := cVerifactuUrlQRPro
  else
    sBase := cVerifactuUrlQRPre;
  // Formato fijado por la AEAT: nif, numserie, fecha dd-mm-aaaa e importe
  // total con punto decimal, todos percent-encoded.
  Result := sBase +
    '?nif='      + CodificarParametroURL(NormalizarNif(ANif)) +
    '&numserie=' + CodificarParametroURL(
                     ComponerNumSerieFactura(ASerie, ANumero)) +
    '&fecha='    + CodificarParametroURL(
                     FormatDateTime('dd-mm-yyyy', AFecha)) +
    '&importe='  + CodificarParametroURL(
                     FormatearImporte(AImporteTotal));
end;

function ConstruirSistemaInformatico(const ANombreProductor, ANifProductor,
                                     ANombreSistema, AIdSistema, AVersion,
                                     ANumeroInstalacion: string): string;
begin
  Result :=
    '<sum1:SistemaInformatico>' +
    '<sum1:NombreRazon>' + EscaparXml(ANombreProductor) +
    '</sum1:NombreRazon>' +
    '<sum1:NIF>' + EscaparXml(NormalizarNif(ANifProductor)) + '</sum1:NIF>' +
    '<sum1:NombreSistemaInformatico>' + EscaparXml(ANombreSistema) +
    '</sum1:NombreSistemaInformatico>' +
    '<sum1:IdSistemaInformatico>' + EscaparXml(AIdSistema) +
    '</sum1:IdSistemaInformatico>' +
    '<sum1:Version>' + EscaparXml(AVersion) + '</sum1:Version>' +
    '<sum1:NumeroInstalacion>' + EscaparXml(ANumeroInstalacion) +
    '</sum1:NumeroInstalacion>' +
    '<sum1:TipoUsoPosibleSoloVerifactu>N' +
    '</sum1:TipoUsoPosibleSoloVerifactu>' +
    '<sum1:TipoUsoPosibleMultiOT>S</sum1:TipoUsoPosibleMultiOT>' +
    '<sum1:IndicadorMultiplesOT>N</sum1:IndicadorMultiplesOT>' +
    '</sum1:SistemaInformatico>';
end;

function CalcularHuellaAlta(const AFactura: TFacturaVerifactu;
                           const AAnterior: TEslabonCadena;
                           const AFechaHoraHusoGen: string): string;
var
  sBase: string;
begin
  // Orden de campos EXACTO de la especificacion tecnica (no alterar):
  // separados por '&', SHA-256, hexadecimal en mayusculas.
  sBase :=
    'IDEmisorFactura=' + NormalizarNif(AFactura.NifEmisor) +
    '&NumSerieFactura=' +
    ComponerNumSerieFactura(AFactura.Serie, AFactura.Numero) +
    '&FechaExpedicionFactura=' + AFactura.FechaExpedicionTexto +
    '&TipoFactura=' + AFactura.TipoVerifactu +
    '&CuotaTotal=' + FormatearImporte(AFactura.CuotaTotal) +
    '&ImporteTotal=' + FormatearImporte(AFactura.ImporteTotal) +
    '&Huella=' + AAnterior.Huella +
    '&FechaHoraHusoGenRegistro=' + AFechaHoraHusoGen;
  Result := UpperCase(THashSHA2.GetHashString(sBase));
end;

function ConstruirDesglose(const AFactura: TFacturaVerifactu): string;
var
  i:    Integer;
  sDet: string;
begin
  Result := '';
  // Una operacion sujeta y no exenta con IVA repercutido por cada banda.
  for i := 0 to High(AFactura.Bandas) do
  begin
    sDet :=
      '<sum1:Impuesto>01</sum1:Impuesto>' +
      '<sum1:ClaveRegimen>01</sum1:ClaveRegimen>' +
      '<sum1:CalificacionOperacion>S1</sum1:CalificacionOperacion>' +
      '<sum1:TipoImpositivo>' +
      FormatearImporte(AFactura.Bandas[i].Porcentaje) +
      '</sum1:TipoImpositivo>' +
      '<sum1:BaseImponibleOimporteNoSujeto>' +
      FormatearImporte(AFactura.Bandas[i].Base) +
      '</sum1:BaseImponibleOimporteNoSujeto>' +
      '<sum1:CuotaRepercutida>' +
      FormatearImporte(AFactura.Bandas[i].Cuota) +
      '</sum1:CuotaRepercutida>';
    Result := Result + '<sum1:DetalleDesglose>' + sDet +
              '</sum1:DetalleDesglose>';
  end;
end;

function ConstruirDestinatarios(const AFactura: TFacturaVerifactu): string;
var
  sTipo: string;
begin
  // Las completas (F1) y las rectificativas de completas (R1) exigen
  // identificar al destinatario; las simplificadas (F2) no.
  sTipo := AFactura.TipoVerifactu;
  if (sTipo = 'F1') or (sTipo = 'R1') then
    Result := '<sum1:Destinatarios><sum1:IDDestinatario>' +
      '<sum1:NombreRazon>' + EscaparXml(AFactura.NombreCliente) +
      '</sum1:NombreRazon>' +
      '<sum1:NIF>' + EscaparXml(NormalizarNif(AFactura.NifCliente)) +
      '</sum1:NIF>' +
      '</sum1:IDDestinatario></sum1:Destinatarios>'
  else
    Result := '';
end;

function ConstruirEncadenamiento(const ANif: string;
                                 const AAnterior: TEslabonCadena): string;
begin
  if AAnterior.Huella = '' then
    Result := '<sum1:Encadenamiento>' +
              '<sum1:PrimerRegistro>S</sum1:PrimerRegistro>' +
              '</sum1:Encadenamiento>'
  else
    Result := '<sum1:Encadenamiento><sum1:RegistroAnterior>' +
      '<sum1:IDEmisorFactura>' + EscaparXml(ANif) +
      '</sum1:IDEmisorFactura>' +
      '<sum1:NumSerieFactura>' +
      EscaparXml(ComponerNumSerieFactura(AAnterior.Serie,
                                         AAnterior.Numero)) +
      '</sum1:NumSerieFactura>' +
      '<sum1:FechaExpedicionFactura>' + AAnterior.Fecha +
      '</sum1:FechaExpedicionFactura>' +
      '<sum1:Huella>' + AAnterior.Huella + '</sum1:Huella>' +
      '</sum1:RegistroAnterior></sum1:Encadenamiento>';
end;

function ConstruirRegistroAlta(const AFactura: TFacturaVerifactu;
                              const AAnterior: TEslabonCadena;
                              const ASistemaInformatico,
                              AFechaHoraHusoGen: string;
                              out AHuella: string): string;
var
  sNif:      string;
  sNumSerie: string;
  sCuota:    string;
  sImporte:  string;
begin
  sNif      := NormalizarNif(AFactura.NifEmisor);
  sNumSerie := ComponerNumSerieFactura(AFactura.Serie, AFactura.Numero);
  sCuota    := FormatearImporte(AFactura.CuotaTotal);
  sImporte  := FormatearImporte(AFactura.ImporteTotal);
  AHuella   := CalcularHuellaAlta(AFactura, AAnterior, AFechaHoraHusoGen);
  Result :=
    '<sum1:RegistroAlta>' +
    '<sum1:IDVersion>1.0</sum1:IDVersion>' +
    '<sum1:IDFactura>' +
    '<sum1:IDEmisorFactura>' + EscaparXml(sNif) +
    '</sum1:IDEmisorFactura>' +
    '<sum1:NumSerieFactura>' + EscaparXml(sNumSerie) +
    '</sum1:NumSerieFactura>' +
    '<sum1:FechaExpedicionFactura>' + AFactura.FechaExpedicionTexto +
    '</sum1:FechaExpedicionFactura>' +
    '</sum1:IDFactura>' +
    '<sum1:NombreRazonEmisor>' + EscaparXml(AFactura.NombreEmisor) +
    '</sum1:NombreRazonEmisor>' +
    '<sum1:TipoFactura>' + AFactura.TipoVerifactu + '</sum1:TipoFactura>' +
    '<sum1:DescripcionOperacion>' +
    EscaparXml(AFactura.DescripcionOperacion) +
    '</sum1:DescripcionOperacion>' +
    ConstruirDestinatarios(AFactura) +
    '<sum1:Desglose>' + ConstruirDesglose(AFactura) + '</sum1:Desglose>' +
    '<sum1:CuotaTotal>' + sCuota + '</sum1:CuotaTotal>' +
    '<sum1:ImporteTotal>' + sImporte + '</sum1:ImporteTotal>' +
    ConstruirEncadenamiento(sNif, AAnterior) +
    ASistemaInformatico +
    '<sum1:FechaHoraHusoGenRegistro>' + AFechaHoraHusoGen +
    '</sum1:FechaHoraHusoGenRegistro>' +
    '<sum1:TipoHuella>01</sum1:TipoHuella>' +
    '<sum1:Huella>' + AHuella + '</sum1:Huella>' +
    '</sum1:RegistroAlta>';
end;

function EnvolverSoap(const AFactura: TFacturaVerifactu;
                     const ARegistro: string): string;
begin
  Result :=
    '<?xml version="1.0" encoding="UTF-8"?>' +
    '<soapenv:Envelope xmlns:soapenv="' + cNsSoap + '" ' +
    'xmlns:sum="' + cNsLR + '" xmlns:sum1="' + cNsInf + '">' +
    '<soapenv:Header/><soapenv:Body>' +
    '<sum:RegFactuSistemaFacturacion>' +
    '<sum:Cabecera><sum1:ObligadoEmision>' +
    '<sum1:NombreRazon>' + EscaparXml(AFactura.NombreEmisor) +
    '</sum1:NombreRazon>' +
    '<sum1:NIF>' + EscaparXml(NormalizarNif(AFactura.NifEmisor)) +
    '</sum1:NIF>' +
    '</sum1:ObligadoEmision></sum:Cabecera>' +
    '<sum:RegistroFactura>' + ARegistro + '</sum:RegistroFactura>' +
    '</sum:RegFactuSistemaFacturacion>' +
    '</soapenv:Body></soapenv:Envelope>';
end;

function PrepararRegistroAlta(const AFactura: TFacturaVerifactu;
                            const AAnterior: TEslabonCadena;
                            const ASistemaInformatico: string;
                            AEntornoPro: Boolean): TRegistroVerifactu;
begin
  Result.NumSerieFactura :=
    ComponerNumSerieFactura(AFactura.Serie, AFactura.Numero);
  Result.FechaHoraHusoGen := FechaHoraHusoGen(Now);
  Result.CuotaTotal       := AFactura.CuotaTotal;
  Result.ImporteTotal     := AFactura.ImporteTotal;
  Result.XmlRegistro      := ConstruirRegistroAlta(AFactura, AAnterior,
    ASistemaInformatico, Result.FechaHoraHusoGen, Result.Huella);
  Result.XmlSoap          := EnvolverSoap(AFactura, Result.XmlRegistro);
  Result.UrlQR            := ConstruirUrlQR(AFactura.NifEmisor,
    AFactura.Serie, AFactura.Numero, AFactura.Fecha, AFactura.ImporteTotal,
    AEntornoPro);
end;

function ExtraerEtiqueta(const AXml, AEtiqueta: string): string;
var
  iIni:      Integer;
  iFin:      Integer;
  sApertura: string;
begin
  // Tolera cualquier prefijo de namespace en la respuesta de la AEAT
  Result := '';
  sApertura := AEtiqueta + '>';
  iIni := Pos('<' + sApertura, AXml);
  if iIni > 0 then
    iIni := iIni + Length(sApertura) + 1
  else
  begin
    iIni := Pos(':' + sApertura, AXml);
    if iIni > 0 then
      iIni := iIni + Length(sApertura) + 1;
  end;
  if iIni > 0 then
  begin
    iFin := PosEx('<', AXml, iIni);
    if iFin > iIni then
      Result := Trim(Copy(AXml, iIni, iFin - iIni));
  end;
end;

function NormalizarSerieCert(const AValor: string): string;
begin
  Result := UpperCase(Trim(AValor));
  Result := StringReplace(Result, ' ', '', [rfReplaceAll]);
  Result := StringReplace(Result, ':', '', [rfReplaceAll]);
  Result := StringReplace(Result, '-', '', [rfReplaceAll]);
end;

// El numero de serie puede venir con los bytes en orden inverso segun la
// capa que lo lea, asi que se compara en ambos sentidos
function InvertirBytesHex(const AHex: string): string;
var
  iPos: Integer;
begin
  Result := '';
  iPos := Length(AHex) - 1;
  while iPos >= 1 do
  begin
    Result := Result + Copy(AHex, iPos, 2);
    Dec(iPos, 2);
  end;
end;

constructor TSelectorCertificado.Create(const ASerial, ATitular: string);
begin
  inherited Create;
  FSerial  := ASerial;
  FTitular := ATitular;
end;

procedure TSelectorCertificado.Seleccionar(const Sender: TObject;
                                           const ARequest: TURLRequest;
                                           const ACertificateList:
                                                 TCertificateList;
                                           var AnIndex: Integer);
var
  i:        Integer;
  sBuscada: string;
  sSerie:   string;
begin
  AnIndex := -1;
  sBuscada := NormalizarSerieCert(FSerial);
  if sBuscada <> '' then
  begin
    for i := 0 to ACertificateList.Count - 1 do
    begin
      sSerie := NormalizarSerieCert(ACertificateList[i].SerialNum);
      if (AnIndex < 0) and
         ((sSerie = sBuscada) or (sSerie = InvertirBytesHex(sBuscada))) then
        AnIndex := i;
    end;
  end;
  if (AnIndex < 0) and (Trim(FTitular) <> '') then
  begin
    for i := 0 to ACertificateList.Count - 1 do
    begin
      if (AnIndex < 0) and
         ContainsText(ACertificateList[i].Subject, Trim(FTitular)) then
        AnIndex := i;
    end;
  end;
  // Ultimo recurso: si solo se ofrece un certificado, se usa ese
  if (AnIndex < 0) and (ACertificateList.Count = 1) then
    AnIndex := 0;
end;

function EnviarSoapAeat(const AUrl, AXmlSoap, ASerieCertificado,
                       ATitularCertificado: string;
                       out AStatus: Integer; out ARespuesta: string): Boolean;
var
  oHttp:     THTTPClient;
  oSelector: TSelectorCertificado;
  oCuerpo:   TStringStream;
  oResp:     IHTTPResponse;
begin
  oHttp     := THTTPClient.Create;
  oSelector := TSelectorCertificado.Create(ASerieCertificado,
                                           ATitularCertificado);
  oCuerpo   := TStringStream.Create(AXmlSoap, TEncoding.UTF8);
  try
    oHttp.ConnectionTimeout := 30000;
    oHttp.ResponseTimeout   := 90000;
    oHttp.OnNeedClientCertificate := oSelector.Seleccionar;
    oResp := oHttp.Post(AUrl, oCuerpo, nil,
      [TNetHeader.Create('Content-Type', 'text/xml; charset=utf-8'),
       TNetHeader.Create('SOAPAction', '""')]);
    AStatus    := oResp.StatusCode;
    ARespuesta := oResp.ContentAsString(TEncoding.UTF8);
    Result     := AStatus = 200;
  finally
    FreeAndNil(oCuerpo);
    FreeAndNil(oSelector);
    FreeAndNil(oHttp);
  end;
end;

function TFacturaVerifactu.TipoVerifactu: string;
begin
  Result := TipoFacturaVerifactu(Tipo);
end;

function TFacturaVerifactu.FechaExpedicionTexto: string;
begin
  Result := FormatDateTime('dd-mm-yyyy', Fecha);
end;

function TFacturaVerifactu.CuotaTotal: Currency;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(Bandas) do
    Result := Result + Bandas[i].Cuota;
end;

function TFacturaVerifactu.ImporteTotal: Currency;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(Bandas) do
    Result := Result + Bandas[i].Base + Bandas[i].Cuota;
end;

procedure TFacturaVerifactu.AnadirBanda(APorcentaje, ABase: Currency);
var
  iIndice: Integer;
begin
  iIndice := Length(Bandas);
  SetLength(Bandas, iIndice + 1);
  Bandas[iIndice].Porcentaje := APorcentaje;
  Bandas[iIndice].Base       := ABase;
  Bandas[iIndice].Cuota      := ABase * APorcentaje / 100;
end;

end.