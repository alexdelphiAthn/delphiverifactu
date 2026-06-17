{******************************************************************************}
{                                                                              }
{  Modulo:       Fiscal.Facturae                                               }
{    Tipo:       Libreria Delphi                                               }
{   Autor:       Alejandro Laorden Hidalgo                                     }
{                                                                              }
{  SPDX-License-Identifier: MIT                                                }
{                                                                              }
{  Descripcion:                                                                }
{    Construccion del XML Facturae 3.2.x (factura electronica) a partir de      }
{    records, SIN dependencia de base de datos ni de componentes de acceso a    }
{    datos. La firma XAdES (politica Facturae, rol emisor) se delega en         }
{    Fiscal.Xades; la validacion de NIF/NIE/CIF en Fiscal.DocumentoFiscal.      }
{                                                                              }
{    Flujo tipico:                                                             }
{      1. Rellenar un TFacturaeFactura (emisor, receptor, lineas...).          }
{      2. ConstruirXmlFacturae  -> XML 3.2.2 sin firmar (multiplataforma).     }
{      3. EmitirFacturaeFirmada -> valida, construye y firma en un paso        }
{         (.xsig); requiere certificado en el almacen de Windows.             }
{                                                                              }
{    El nucleo no lee tablas fza_*: la aplicacion (p. ej. el adaptador de      }
{    Factuzam) construye el record y decide donde persistir el resultado.      }
{******************************************************************************}
unit Fiscal.Facturae;

interface

uses
  System.SysUtils, Fiscal.Xades;

type
  EFacturaeError = class(Exception);

  // Una parte de la factura (emisor o receptor). Los centros DIR3 solo se
  // usan cuando el receptor es una administracion publica (FACe).
  TFacturaeParte = record
    Nif:               string;
    RazonSocial:       string;   // razon social (juridica) o nombre completo
    Direccion:         string;
    CodigoPostal:      string;
    Poblacion:         string;
    Provincia:         string;
    CodigoPais:        string;   // ISO ('', 'ES', 'ESP', '724'...); ESP por defecto
    NombrePais:        string;   // alternativa textual ('Espana', 'Francia'...)
    TipoResidencia:    string;   // 'R' residente (defecto), 'E' UE, 'U' extranjero
    // Centros administrativos DIR3 (receptor publico). Si se rellena uno, han
    // de estar los tres. Si se dejan vacios, no se emite <AdministrativeCentres>.
    OficinaContable:   string;
    OrganoGestor:      string;
    UnidadTramitadora: string;
  end;

  // Una linea de la factura. La base, la cuota de IVA y la de recargo se
  // calculan; el llamador solo aporta cantidad, precio y tipos.
  TFacturaeLinea = record
    Descripcion:    string;
    Cantidad:       Double;
    PrecioUnitario: Double;   // precio unitario SIN IVA
    TipoIva:        Double;   // % de IVA (0..21...)
    TipoRecargo:    Double;   // % de recargo de equivalencia (0 si no aplica)
    function Base: Double;          // Cantidad * PrecioUnitario (2 decimales)
    function CuotaIva: Double;      // Base * TipoIva / 100
    function CuotaRecargo: Double;  // Base * TipoRecargo / 100
  end;

  // Factura completa. Lo unico obligatorio para firmar es lo que valida
  // ValidarFacturae (serie, numero, fecha, partes y al menos una linea).
  TFacturaeFactura = record
    Version:           string;     // '3.2.2' por defecto
    Serie:             string;
    Numero:            string;
    FechaExpedicion:   TDateTime;
    FechaVencimiento:  TDateTime;   // 0 = se usa la fecha de expedicion
    FormaPagoFacturae: string;      // PaymentMeans Facturae '01'..'19' (01 contado)
    Moneda:            string;      // 'EUR' por defecto
    Idioma:            string;      // 'es' por defecto
    TipoRetencion:     Double;      // % de retencion IRPF (0 si no hay)
    Emisor:            TFacturaeParte;
    Receptor:          TFacturaeParte;
    Lineas:            TArray<TFacturaeLinea>;
    // Anade una linea calculando base/cuotas a partir de los tipos.
    procedure AnadirLinea(const ADescripcion: string;
                          ACantidad, APrecioUnitario, ATipoIva: Double;
                          ATipoRecargo: Double = 0);
    function BaseImponibleTotal: Double;
    function CuotaIvaTotal: Double;
    function CuotaRecargoTotal: Double;
    function ImporteRetencion: Double;   // BaseImponibleTotal * TipoRetencion / 100
    function TotalFactura: Double;        // bases + IVA + recargo - retencion
  end;

// Espacio de nombres oficial segun la version (3.2 / 3.2.1 / 3.2.2).
function NamespaceFacturae(const AVersion: string): string;
// Codigo de pais ISO-3166 alfa-3 que exige Facturae (ESP por defecto).
function CodigoPaisFacturae(const ACodigo, ANombre: string): string;
// Nombre de fichero .xsig sugerido para una factura (solo caracteres seguros).
function NombreArchivoFacturae(const ASerie, ANumero: string): string;
// Identificador seguro (EDOC-...) para el Id de la firma XAdES.
function IdFacturaeSeguro(const ASerie, ANumero: string): string;
// Normaliza el PaymentMeans Facturae a dos digitos '01'..'19' ('' si invalido).
function NormalizarFormaPagoFacturae(const AValor: string): string;

// Valida los datos minimos. Lanza EFacturaeError con la lista de problemas.
procedure ValidarFacturae(const AFactura: TFacturaeFactura);
// Construye el XML Facturae 3.2.x SIN firmar (multiplataforma).
function ConstruirXmlFacturae(const AFactura: TFacturaeFactura): string;
// Atajo: valida, construye y firma con XAdES (politica Facturae, rol emisor).
// Requiere certificado en el almacen personal de Windows. Devuelve el .xsig.
function EmitirFacturaeFirmada(const AFactura: TFacturaeFactura;
                               const ASerialCert, ATitularCert: string;
                               out ADatosCert: TXadesDatosCertificado): string;

implementation

uses
  System.Classes, System.Math, Fiscal.DocumentoFiscal;

type
  // Acumulador de impuestos por tipo (IVA + recargo) para el TaxesOutputs
  // de cabecera. Se agrupan las lineas con el mismo par (TipoIva, TipoRecargo).
  TBucketIva = record
    TipoIva:      Double;
    TipoRecargo:  Double;
    Base:         Double;
    CuotaIva:     Double;
    CuotaRecargo: Double;
  end;

// --- Helpers de texto y numero ---------------------------------------------

function EscaparXml(const AValor: string): string;
begin
  Result := StringReplace(AValor,  '&', '&amp;',  [rfReplaceAll]);
  Result := StringReplace(Result,  '<', '&lt;',   [rfReplaceAll]);
  Result := StringReplace(Result,  '>', '&gt;',   [rfReplaceAll]);
  Result := StringReplace(Result,  '"', '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, '''', '&apos;', [rfReplaceAll]);
end;

// Importe con punto decimal (formato Facturae): 2 decimales para importes,
// 6 para cantidades y precios unitarios.
function DecimalFacturae(AValor: Double; ADecimales: Integer = 2): string;
var
  oFormato: TFormatSettings;
begin
  oFormato := TFormatSettings.Create('en-US');
  if ADecimales = 6 then
    Result := FormatFloat('0.000000', AValor, oFormato)
  else
    Result := FormatFloat('0.00', AValor, oFormato);
end;

// NIF sin espacios ni signos, en mayusculas (lo que viaja al XML).
function NormalizarNif(const AValor: string): string;
var
  i: Integer;
  c: Char;
begin
  Result := '';
  for i := 1 to Length(AValor) do
  begin
    c := UpCase(AValor[i]);
    if CharInSet(c, ['A'..'Z', '0'..'9']) then
      Result := Result + c;
  end;
end;

// True si el identificador corresponde a persona juridica (CIF).
function EsPersonaJuridica(const ANif: string): Boolean;
var
  sNif: string;
begin
  sNif := NormalizarNif(ANif);
  Result := (sNif <> '') and
    CharInSet(sNif[1], ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'J', 'N',
                        'P', 'Q', 'R', 'S', 'U', 'V', 'W']);
end;

// Reparte la razon social de una persona fisica en nombre y primer apellido
// de forma simple: primer token = nombre, resto = apellidos.
procedure SepararNombrePersona(const ARazonSocial: string;
                               out ANombre, AApellidos: string);
var
  iPos: Integer;
  sTexto: string;
begin
  sTexto := Trim(ARazonSocial);
  iPos := Pos(' ', sTexto);
  if iPos > 0 then
  begin
    ANombre := Copy(sTexto, 1, iPos - 1);
    AApellidos := Trim(Copy(sTexto, iPos + 1, MaxInt));
  end
  else
  begin
    ANombre := sTexto;
    AApellidos := '.';
  end;
end;

function CodigoPaisFacturae(const ACodigo, ANombre: string): string;
var
  sCodigo: string;
  sNombre: string;
begin
  sCodigo := UpperCase(Trim(ACodigo));
  sNombre := UpperCase(Trim(ANombre));
  if (sCodigo = '') or (sCodigo = 'ES') or (sCodigo = '724') or
     SameText(sNombre, 'ESPANA') or (Copy(sNombre, 1, 4) = 'ESPA') then
    Result := 'ESP'
  else if Length(sCodigo) = 3 then
    Result := sCodigo
  else
    Result := 'ESP';
end;

function NamespaceFacturae(const AVersion: string): string;
var
  sVersion: string;
begin
  sVersion := Trim(AVersion);
  if sVersion = '3.2' then
    Result := 'http://www.facturae.gob.es/formato/Versiones/Facturaev3_2.xml'
  else if sVersion = '3.2.1' then
    Result := 'http://www.facturae.gob.es/formato/Versiones/Facturaev3_2_1.xml'
  else
    Result := 'http://www.facturae.gob.es/formato/Versiones/Facturaev3_2_2.xml';
end;

function NombreArchivoFacturae(const ASerie, ANumero: string): string;
var
  i: Integer;
  sBase: string;
  c: Char;
begin
  Result := 'eDoc_';
  sBase := ASerie + '_' + ANumero;
  for i := 1 to Length(sBase) do
  begin
    c := sBase[i];
    if CharInSet(c, ['A'..'Z', 'a'..'z', '0'..'9', '-', '_']) then
      Result := Result + c
    else
      Result := Result + '_';
  end;
  Result := Result + '.xsig';
end;

function IdFacturaeSeguro(const ASerie, ANumero: string): string;
var
  i: Integer;
  sBase: string;
  c: Char;
begin
  Result := 'EDOC';
  sBase := ASerie + '-' + ANumero;
  for i := 1 to Length(sBase) do
  begin
    c := UpCase(sBase[i]);
    if CharInSet(c, ['A'..'Z', '0'..'9']) then
      Result := Result + c
    else
      Result := Result + '-';
  end;
end;

function FormaPagoFacturaeValida(const AValor: string): Boolean;
var
  iCodigo: Integer;
begin
  Result := TryStrToInt(AValor, iCodigo) and
            (Length(AValor) = 2) and
            (iCodigo >= 1) and (iCodigo <= 19);
end;

function NormalizarFormaPagoFacturae(const AValor: string): string;
begin
  Result := Trim(AValor);
  if Result = '' then
    Result := '01'
  else
  begin
    if Length(Result) = 1 then
      Result := '0' + Result;
    if not FormaPagoFacturaeValida(Result) then
      Result := '';
  end;
end;

// --- Helpers de construccion XML -------------------------------------------
// Facturae usa elementFormDefault="unqualified": la raiz va con prefijo fe: y
// los hijos sin prefijo (en ningun espacio de nombres). Por eso Nodo/Linea
// emiten nombres "pelados" y solo la raiz lleva fe:.

procedure Linea(ASb: TStringBuilder; ANivel: Integer; const ATexto: string);
begin
  ASb.Append(StringOfChar(' ', ANivel * 2));
  ASb.AppendLine(ATexto);
end;

procedure Nodo(ASb: TStringBuilder; ANivel: Integer;
               const ANombre, AValor: string);
begin
  Linea(ASb, ANivel, '<' + ANombre + '>' + EscaparXml(AValor) + '</' +
    ANombre + '>');
end;

function TieneDir3(const AParte: TFacturaeParte): Boolean;
begin
  Result := (Trim(AParte.OficinaContable) <> '') and
            (Trim(AParte.OrganoGestor) <> '') and
            (Trim(AParte.UnidadTramitadora) <> '');
end;

procedure AnadirDireccion(ASb: TStringBuilder; ANivel: Integer;
                          const AParte: TFacturaeParte; const APais: string);
begin
  if APais = 'ESP' then
  begin
    Linea(ASb, ANivel, '<AddressInSpain>');
    Nodo(ASb, ANivel + 1, 'Address', AParte.Direccion);
    Nodo(ASb, ANivel + 1, 'PostCode', AParte.CodigoPostal);
    Nodo(ASb, ANivel + 1, 'Town', AParte.Poblacion);
    Nodo(ASb, ANivel + 1, 'Province', AParte.Provincia);
    Nodo(ASb, ANivel + 1, 'CountryCode', APais);
    Linea(ASb, ANivel, '</AddressInSpain>');
  end
  else
  begin
    Linea(ASb, ANivel, '<OverseasAddress>');
    Nodo(ASb, ANivel + 1, 'Address', AParte.Direccion);
    Nodo(ASb, ANivel + 1, 'PostCodeAndTown',
      Trim(AParte.CodigoPostal + ' ' + AParte.Poblacion));
    Nodo(ASb, ANivel + 1, 'Province', AParte.Provincia);
    Nodo(ASb, ANivel + 1, 'CountryCode', APais);
    Linea(ASb, ANivel, '</OverseasAddress>');
  end;
end;

procedure AnadirCentroAdministrativo(ASb: TStringBuilder; ANivel: Integer;
                                     const ACodigo, ARol, ANombre: string;
                                     const AParte: TFacturaeParte;
                                     const APais: string);
begin
  Linea(ASb, ANivel, '<AdministrativeCentre>');
  Nodo(ASb, ANivel + 1, 'CentreCode', ACodigo);
  Nodo(ASb, ANivel + 1, 'RoleTypeCode', ARol);
  Nodo(ASb, ANivel + 1, 'Name', ANombre);
  AnadirDireccion(ASb, ANivel + 1, AParte, APais);
  Linea(ASb, ANivel, '</AdministrativeCentre>');
end;

// Los AdministrativeCentres son hijo directo de la parte (BusinessType), tras
// TaxIdentification y antes del Individual/LegalEntity, como exige el esquema.
procedure AnadirCentrosAdministrativos(ASb: TStringBuilder; ANivel: Integer;
                                       const AParte: TFacturaeParte;
                                       const APais: string);
begin
  Linea(ASb, ANivel, '<AdministrativeCentres>');
  AnadirCentroAdministrativo(ASb, ANivel + 1, Trim(AParte.OficinaContable),
    '01', 'Oficina contable', AParte, APais);
  AnadirCentroAdministrativo(ASb, ANivel + 1, Trim(AParte.OrganoGestor),
    '02', 'Organo gestor', AParte, APais);
  AnadirCentroAdministrativo(ASb, ANivel + 1, Trim(AParte.UnidadTramitadora),
    '03', 'Unidad tramitadora', AParte, APais);
  Linea(ASb, ANivel, '</AdministrativeCentres>');
end;

procedure AnadirParte(ASb: TStringBuilder; const ANodo: string;
                      const AParte: TFacturaeParte; const APais: string;
                      AIncluirCentros: Boolean);
var
  sNombre: string;
  sApellidos: string;
  sResidencia: string;
  bJuridica: Boolean;
  bCentros: Boolean;
begin
  bJuridica := EsPersonaJuridica(AParte.Nif);
  bCentros := AIncluirCentros and TieneDir3(AParte);
  sResidencia := Trim(AParte.TipoResidencia);
  if sResidencia = '' then
    sResidencia := 'R';
  Linea(ASb, 2, '<' + ANodo + '>');
  Linea(ASb, 3, '<TaxIdentification>');
  if bJuridica then
    Nodo(ASb, 4, 'PersonTypeCode', 'J')
  else
    Nodo(ASb, 4, 'PersonTypeCode', 'F');
  Nodo(ASb, 4, 'ResidenceTypeCode', sResidencia);
  Nodo(ASb, 4, 'TaxIdentificationNumber', NormalizarNif(AParte.Nif));
  Linea(ASb, 3, '</TaxIdentification>');
  // AdministrativeCentres (DIR3) a nivel de parte, antes del Individual/LegalEntity.
  if bCentros then
    AnadirCentrosAdministrativos(ASb, 3, AParte, APais);
  if bJuridica then
  begin
    Linea(ASb, 3, '<LegalEntity>');
    Nodo(ASb, 4, 'CorporateName', AParte.RazonSocial);
    AnadirDireccion(ASb, 4, AParte, APais);
    Linea(ASb, 3, '</LegalEntity>');
  end
  else
  begin
    SepararNombrePersona(AParte.RazonSocial, sNombre, sApellidos);
    Linea(ASb, 3, '<Individual>');
    Nodo(ASb, 4, 'Name', sNombre);
    Nodo(ASb, 4, 'FirstSurname', sApellidos);
    AnadirDireccion(ASb, 4, AParte, APais);
    Linea(ASb, 3, '</Individual>');
  end;
  Linea(ASb, 2, '</' + ANodo + '>');
end;

procedure AnadirImpuesto(ASb: TStringBuilder; ANivel: Integer;
                         APorcentajeIva, ABase, AImporteIva,
                         APorcentajeRe, AImporteRe: Double);
begin
  Linea(ASb, ANivel, '<Tax>');
  Nodo(ASb, ANivel + 1, 'TaxTypeCode', '01');
  Nodo(ASb, ANivel + 1, 'TaxRate', DecimalFacturae(APorcentajeIva));
  Linea(ASb, ANivel + 1, '<TaxableBase>');
  Nodo(ASb, ANivel + 2, 'TotalAmount', DecimalFacturae(ABase));
  Linea(ASb, ANivel + 1, '</TaxableBase>');
  Linea(ASb, ANivel + 1, '<TaxAmount>');
  Nodo(ASb, ANivel + 2, 'TotalAmount', DecimalFacturae(AImporteIva));
  Linea(ASb, ANivel + 1, '</TaxAmount>');
  if (Abs(APorcentajeRe) > 0.000001) and (Abs(AImporteRe) > 0.000001) then
  begin
    Nodo(ASb, ANivel + 1, 'EquivalenceSurcharge',
      DecimalFacturae(APorcentajeRe));
    Linea(ASb, ANivel + 1, '<EquivalenceSurchargeAmount>');
    Nodo(ASb, ANivel + 2, 'TotalAmount', DecimalFacturae(AImporteRe));
    Linea(ASb, ANivel + 1, '</EquivalenceSurchargeAmount>');
  end;
  Linea(ASb, ANivel, '</Tax>');
end;

// Agrupa las lineas por (TipoIva, TipoRecargo) para el desglose de cabecera.
function AgruparImpuestos(const AFactura: TFacturaeFactura): TArray<TBucketIva>;
var
  i: Integer;
  j: Integer;
  iIndice: Integer;
  oLinea: TFacturaeLinea;
begin
  SetLength(Result, 0);
  for i := 0 to High(AFactura.Lineas) do
  begin
    oLinea := AFactura.Lineas[i];
    iIndice := -1;
    for j := 0 to High(Result) do
      if (Abs(Result[j].TipoIva - oLinea.TipoIva) < 0.0001) and
         (Abs(Result[j].TipoRecargo - oLinea.TipoRecargo) < 0.0001) then
      begin
        iIndice := j;
        Break;
      end;
    if iIndice < 0 then
    begin
      SetLength(Result, Length(Result) + 1);
      iIndice := High(Result);
      Result[iIndice].TipoIva := oLinea.TipoIva;
      Result[iIndice].TipoRecargo := oLinea.TipoRecargo;
      Result[iIndice].Base := 0;
      Result[iIndice].CuotaIva := 0;
      Result[iIndice].CuotaRecargo := 0;
    end;
    Result[iIndice].Base := Result[iIndice].Base + oLinea.Base;
    Result[iIndice].CuotaIva := Result[iIndice].CuotaIva + oLinea.CuotaIva;
    Result[iIndice].CuotaRecargo := Result[iIndice].CuotaRecargo +
      oLinea.CuotaRecargo;
  end;
end;

procedure AnadirPaymentDetails(ASb: TStringBuilder;
                               const AFactura: TFacturaeFactura;
                               ATotal: Double);
var
  dVencimiento: TDateTime;
  sCodigoPago: string;
begin
  dVencimiento := AFactura.FechaVencimiento;
  if dVencimiento <= 0 then
    dVencimiento := AFactura.FechaExpedicion;
  sCodigoPago := NormalizarFormaPagoFacturae(AFactura.FormaPagoFacturae);
  if sCodigoPago = '' then
    sCodigoPago := '01';
  Linea(ASb, 3, '<PaymentDetails>');
  Linea(ASb, 4, '<Installment>');
  Nodo(ASb, 5, 'InstallmentDueDate',
    FormatDateTime('yyyy-mm-dd', dVencimiento));
  Nodo(ASb, 5, 'InstallmentAmount', DecimalFacturae(ATotal));
  Nodo(ASb, 5, 'PaymentMeans', sCodigoPago);
  Linea(ASb, 4, '</Installment>');
  Linea(ASb, 3, '</PaymentDetails>');
end;

// --- Metodos de los records ------------------------------------------------

function TFacturaeLinea.Base: Double;
begin
  Result := RoundTo(Cantidad * PrecioUnitario, -2);
end;

function TFacturaeLinea.CuotaIva: Double;
begin
  Result := RoundTo(Base * TipoIva / 100, -2);
end;

function TFacturaeLinea.CuotaRecargo: Double;
begin
  Result := RoundTo(Base * TipoRecargo / 100, -2);
end;

procedure TFacturaeFactura.AnadirLinea(const ADescripcion: string;
  ACantidad, APrecioUnitario, ATipoIva, ATipoRecargo: Double);
var
  oLinea: TFacturaeLinea;
begin
  oLinea := Default(TFacturaeLinea);
  oLinea.Descripcion := ADescripcion;
  oLinea.Cantidad := ACantidad;
  oLinea.PrecioUnitario := APrecioUnitario;
  oLinea.TipoIva := ATipoIva;
  oLinea.TipoRecargo := ATipoRecargo;
  Lineas := Lineas + [oLinea];
end;

function TFacturaeFactura.BaseImponibleTotal: Double;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(Lineas) do
    Result := Result + Lineas[i].Base;
end;

function TFacturaeFactura.CuotaIvaTotal: Double;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(Lineas) do
    Result := Result + Lineas[i].CuotaIva;
end;

function TFacturaeFactura.CuotaRecargoTotal: Double;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(Lineas) do
    Result := Result + Lineas[i].CuotaRecargo;
end;

function TFacturaeFactura.ImporteRetencion: Double;
begin
  Result := RoundTo(BaseImponibleTotal * TipoRetencion / 100, -2);
end;

function TFacturaeFactura.TotalFactura: Double;
begin
  Result := BaseImponibleTotal + CuotaIvaTotal + CuotaRecargoTotal -
    ImporteRetencion;
end;

// --- Construccion del documento --------------------------------------------

function ConstruirXmlFacturae(const AFactura: TFacturaeFactura): string;
var
  SB: TStringBuilder;
  aImpuestos: TArray<TBucketIva>;
  oLinea: TFacturaeLinea;
  i: Integer;
  sVersion: string;
  sMoneda: string;
  sIdioma: string;
  sPaisEmi: string;
  sPaisRec: string;
  dRetencion: Double;
  dTotal: Double;
begin
  SB := TStringBuilder.Create;
  try
    sVersion := Trim(AFactura.Version);
    if sVersion = '' then
      sVersion := '3.2.2';
    sMoneda := Trim(AFactura.Moneda);
    if sMoneda = '' then
      sMoneda := 'EUR';
    sIdioma := Trim(AFactura.Idioma);
    if sIdioma = '' then
      sIdioma := 'es';
    sPaisEmi := CodigoPaisFacturae(AFactura.Emisor.CodigoPais,
      AFactura.Emisor.NombrePais);
    sPaisRec := CodigoPaisFacturae(AFactura.Receptor.CodigoPais,
      AFactura.Receptor.NombrePais);
    dRetencion := AFactura.ImporteRetencion;
    dTotal := AFactura.TotalFactura;

    SB.AppendLine('<?xml version="1.0" encoding="UTF-8"?>');
    Linea(SB, 0, '<fe:Facturae xmlns:fe="' + NamespaceFacturae(sVersion) +
      '">');

    // FileHeader
    Linea(SB, 1, '<FileHeader>');
    Nodo(SB, 2, 'SchemaVersion', sVersion);
    Nodo(SB, 2, 'Modality', 'I');
    Nodo(SB, 2, 'InvoiceIssuerType', 'EM');
    Linea(SB, 2, '<Batch>');
    Nodo(SB, 3, 'BatchIdentifier',
      NormalizarNif(AFactura.Emisor.Nif) + '-' + AFactura.Serie + '-' +
      AFactura.Numero);
    Nodo(SB, 3, 'InvoicesCount', '1');
    Linea(SB, 3, '<TotalInvoicesAmount>');
    Nodo(SB, 4, 'TotalAmount', DecimalFacturae(dTotal));
    Linea(SB, 3, '</TotalInvoicesAmount>');
    Linea(SB, 3, '<TotalOutstandingAmount>');
    Nodo(SB, 4, 'TotalAmount', DecimalFacturae(dTotal));
    Linea(SB, 3, '</TotalOutstandingAmount>');
    Linea(SB, 3, '<TotalExecutableAmount>');
    Nodo(SB, 4, 'TotalAmount', DecimalFacturae(dTotal));
    Linea(SB, 3, '</TotalExecutableAmount>');
    Nodo(SB, 3, 'InvoiceCurrencyCode', sMoneda);
    Linea(SB, 2, '</Batch>');
    Linea(SB, 1, '</FileHeader>');

    // Parties
    Linea(SB, 1, '<Parties>');
    AnadirParte(SB, 'SellerParty', AFactura.Emisor, sPaisEmi, False);
    AnadirParte(SB, 'BuyerParty', AFactura.Receptor, sPaisRec, True);
    Linea(SB, 1, '</Parties>');

    // Invoices / Invoice
    Linea(SB, 1, '<Invoices>');
    Linea(SB, 2, '<Invoice>');
    Linea(SB, 3, '<InvoiceHeader>');
    Nodo(SB, 4, 'InvoiceNumber', AFactura.Numero);
    Nodo(SB, 4, 'InvoiceSeriesCode', AFactura.Serie);
    Nodo(SB, 4, 'InvoiceDocumentType', 'FC');
    Nodo(SB, 4, 'InvoiceClass', 'OO');
    Linea(SB, 3, '</InvoiceHeader>');
    Linea(SB, 3, '<InvoiceIssueData>');
    Nodo(SB, 4, 'IssueDate',
      FormatDateTime('yyyy-mm-dd', AFactura.FechaExpedicion));
    Nodo(SB, 4, 'InvoiceCurrencyCode', sMoneda);
    Nodo(SB, 4, 'TaxCurrencyCode', sMoneda);
    Nodo(SB, 4, 'LanguageName', sIdioma);
    Linea(SB, 3, '</InvoiceIssueData>');

    // TaxesOutputs (desglose de IVA agrupado)
    aImpuestos := AgruparImpuestos(AFactura);
    Linea(SB, 3, '<TaxesOutputs>');
    if Length(aImpuestos) = 0 then
      AnadirImpuesto(SB, 4, 0, AFactura.BaseImponibleTotal, 0, 0, 0)
    else
      for i := 0 to High(aImpuestos) do
        AnadirImpuesto(SB, 4, aImpuestos[i].TipoIva, aImpuestos[i].Base,
          aImpuestos[i].CuotaIva, aImpuestos[i].TipoRecargo,
          aImpuestos[i].CuotaRecargo);
    Linea(SB, 3, '</TaxesOutputs>');

    // TaxesWithheld (retencion IRPF, si la hay)
    if dRetencion > 0.000001 then
    begin
      Linea(SB, 3, '<TaxesWithheld>');
      Linea(SB, 4, '<Tax>');
      Nodo(SB, 5, 'TaxTypeCode', '04');
      Nodo(SB, 5, 'TaxRate', DecimalFacturae(AFactura.TipoRetencion));
      Linea(SB, 5, '<TaxableBase>');
      Nodo(SB, 6, 'TotalAmount',
        DecimalFacturae(AFactura.BaseImponibleTotal));
      Linea(SB, 5, '</TaxableBase>');
      Linea(SB, 5, '<TaxAmount>');
      Nodo(SB, 6, 'TotalAmount', DecimalFacturae(dRetencion));
      Linea(SB, 5, '</TaxAmount>');
      Linea(SB, 4, '</Tax>');
      Linea(SB, 3, '</TaxesWithheld>');
    end;

    // InvoiceTotals
    Linea(SB, 3, '<InvoiceTotals>');
    Nodo(SB, 4, 'TotalGrossAmount',
      DecimalFacturae(AFactura.BaseImponibleTotal));
    Nodo(SB, 4, 'TotalGrossAmountBeforeTaxes',
      DecimalFacturae(AFactura.BaseImponibleTotal));
    Nodo(SB, 4, 'TotalTaxOutputs',
      DecimalFacturae(AFactura.CuotaIvaTotal + AFactura.CuotaRecargoTotal));
    Nodo(SB, 4, 'TotalTaxesWithheld', DecimalFacturae(dRetencion));
    Nodo(SB, 4, 'InvoiceTotal', DecimalFacturae(dTotal));
    Nodo(SB, 4, 'TotalOutstandingAmount', DecimalFacturae(dTotal));
    Nodo(SB, 4, 'TotalExecutableAmount', DecimalFacturae(dTotal));
    Linea(SB, 3, '</InvoiceTotals>');

    // Items
    Linea(SB, 3, '<Items>');
    for i := 0 to High(AFactura.Lineas) do
    begin
      oLinea := AFactura.Lineas[i];
      Linea(SB, 4, '<InvoiceLine>');
      Nodo(SB, 5, 'ItemDescription', oLinea.Descripcion);
      Nodo(SB, 5, 'Quantity', DecimalFacturae(oLinea.Cantidad, 6));
      Nodo(SB, 5, 'UnitOfMeasure', '01');
      Nodo(SB, 5, 'UnitPriceWithoutTax',
        DecimalFacturae(oLinea.PrecioUnitario, 6));
      Nodo(SB, 5, 'TotalCost', DecimalFacturae(oLinea.Base));
      Nodo(SB, 5, 'GrossAmount', DecimalFacturae(oLinea.Base));
      Linea(SB, 5, '<TaxesOutputs>');
      AnadirImpuesto(SB, 6, oLinea.TipoIva, oLinea.Base, oLinea.CuotaIva,
        oLinea.TipoRecargo, oLinea.CuotaRecargo);
      Linea(SB, 5, '</TaxesOutputs>');
      Linea(SB, 4, '</InvoiceLine>');
    end;
    Linea(SB, 3, '</Items>');

    AnadirPaymentDetails(SB, AFactura, dTotal);

    Linea(SB, 2, '</Invoice>');
    Linea(SB, 1, '</Invoices>');
    Linea(SB, 0, '</fe:Facturae>');
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

// --- Validacion ------------------------------------------------------------

procedure ValidarObligatorio(AErrores: TStrings; const ATexto, AValor: string);
begin
  if Trim(AValor) = '' then
    AErrores.Add('- Falta ' + ATexto + '.');
end;

procedure ValidarParteFacturae(AErrores: TStrings; const ATexto: string;
                               const AParte: TFacturaeParte);
var
  sPais: string;
begin
  ValidarObligatorio(AErrores, 'NIF de ' + ATexto, AParte.Nif);
  ValidarObligatorio(AErrores, 'razon social de ' + ATexto, AParte.RazonSocial);
  ValidarObligatorio(AErrores, 'direccion de ' + ATexto, AParte.Direccion);
  ValidarObligatorio(AErrores, 'codigo postal de ' + ATexto,
    AParte.CodigoPostal);
  ValidarObligatorio(AErrores, 'poblacion de ' + ATexto, AParte.Poblacion);
  ValidarObligatorio(AErrores, 'provincia de ' + ATexto, AParte.Provincia);
  sPais := CodigoPaisFacturae(AParte.CodigoPais, AParte.NombrePais);
  if (sPais = 'ESP') and (Trim(AParte.Nif) <> '') and
     (not DocumentoFiscalValido(AParte.Nif)) then
    AErrores.Add('- ' + MensajeDocumentoFiscalInvalido(AParte.Nif) + ' (' +
      ATexto + ').');
end;

procedure ValidarDir3Facturae(AErrores: TStrings; const AParte: TFacturaeParte);

  procedure ValidarCodigo(const ATexto, ACodigo: string);
  begin
    if Trim(ACodigo) = '' then
      AErrores.Add('- Falta el codigo DIR3 de ' + ATexto + '.')
    else if Length(Trim(ACodigo)) > 10 then
      AErrores.Add('- El codigo DIR3 de ' + ATexto + ' supera 10 caracteres.');
  end;

begin
  // DIR3 es opcional, pero si se rellena uno han de estar los tres (FACe).
  if (Trim(AParte.OficinaContable) = '') and
     (Trim(AParte.OrganoGestor) = '') and
     (Trim(AParte.UnidadTramitadora) = '') then
    Exit;
  ValidarCodigo('la oficina contable', AParte.OficinaContable);
  ValidarCodigo('el organo gestor', AParte.OrganoGestor);
  ValidarCodigo('la unidad tramitadora', AParte.UnidadTramitadora);
end;

procedure ValidarFacturae(const AFactura: TFacturaeFactura);
var
  oErrores: TStringList;
  i: Integer;
begin
  oErrores := TStringList.Create;
  try
    ValidarObligatorio(oErrores, 'la serie de la factura', AFactura.Serie);
    ValidarObligatorio(oErrores, 'el numero de la factura', AFactura.Numero);
    if AFactura.FechaExpedicion <= 0 then
      oErrores.Add('- Falta la fecha de expedicion de la factura.');
    ValidarParteFacturae(oErrores, 'empresa emisora', AFactura.Emisor);
    ValidarParteFacturae(oErrores, 'cliente', AFactura.Receptor);
    ValidarDir3Facturae(oErrores, AFactura.Receptor);
    if NormalizarFormaPagoFacturae(AFactura.FormaPagoFacturae) = '' then
      oErrores.Add('- El codigo Facturae de la forma de pago debe estar ' +
        'entre 01 y 19.');
    if Length(AFactura.Lineas) = 0 then
      oErrores.Add('- La factura no tiene lineas.');
    for i := 0 to High(AFactura.Lineas) do
    begin
      if Trim(AFactura.Lineas[i].Descripcion) = '' then
        oErrores.Add('- La linea ' + IntToStr(i + 1) +
          ' no tiene descripcion.');
      if Abs(AFactura.Lineas[i].Cantidad) <= 0.000001 then
        oErrores.Add('- La linea ' + IntToStr(i + 1) + ' tiene cantidad cero.');
    end;
    if oErrores.Count > 0 then
      raise EFacturaeError.Create('No se puede emitir Facturae:' + sLineBreak +
        oErrores.Text);
  finally
    FreeAndNil(oErrores);
  end;
end;

// --- Emision firmada -------------------------------------------------------

function EmitirFacturaeFirmada(const AFactura: TFacturaeFactura;
  const ASerialCert, ATitularCert: string;
  out ADatosCert: TXadesDatosCertificado): string;
var
  oOpciones: TXadesOpciones;
  sXmlBase: string;
begin
  ValidarFacturae(AFactura);
  sXmlBase := ConstruirXmlFacturae(AFactura);
  // Politica de firma Facturae y rol emisor (lo aporta Fiscal.Xades).
  oOpciones := OpcionesXadesFacturae(
    IdFacturaeSeguro(AFactura.Serie, AFactura.Numero));
  oOpciones.RolFirmante := 'emisor';
  Result := FirmarXmlXadesEnveloped(sXmlBase, ASerialCert, ATitularCert,
    oOpciones, ADatosCert);
end;

end.
