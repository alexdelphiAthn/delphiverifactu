{******************************************************************************}
{  EmitirFacturae - Ejemplo Facturae 3.2.2 firmada (XAdES)                      }
{                                                                              }
{  Lee una factura desde un XML sencillo (sin base de datos), construye el      }
{  documento Facturae 3.2.2 con Fiscal.Facturae y, si se indica certificado,    }
{  lo firma con XAdES (politica Facturae) reutilizando Fiscal.Xades.            }
{                                                                              }
{    1. Carga emisor, receptor y lineas del XML de entrada.                    }
{    2. Valida los datos minimos (NIF/CIF con Fiscal.DocumentoFiscal).         }
{    3. Construye el XML Facturae (ConstruirXmlFacturae).                       }
{    4. Sin certificado -> escribe el XML SIN firmar (.xml, demo).             }
{       Con certificado  -> firma y escribe el .xsig (EmitirFacturaeFirmada).  }
{                                                                              }
{  Uso:  EmitirFacturae.exe [factura.xml] [salida] [serialCert] [titular]      }
{        Sin serial/titular -> modo DEMO (XML sin firmar).                     }
{        Con serial/titular -> firma XAdES con el certificado de Windows.      }
{******************************************************************************}
program EmitirFacturae;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.StrUtils,
  System.Variants,
  System.IOUtils,
  Xml.xmldom,
  Xml.omnixmldom,
  Xml.XMLDoc,
  Xml.XMLIntf,
  Fiscal.Xades in '..\..\src\Fiscal.Xades.pas',
  Fiscal.DocumentoFiscal in '..\..\src\Fiscal.DocumentoFiscal.pas',
  Fiscal.Facturae in '..\..\src\Fiscal.Facturae.pas';

// --- Pequenos ayudantes de lectura del XML ---------------------------------

// Lee un atributo de un nodo, con valor por defecto si no existe.
function Attr(const ANodo: IXMLNode; const ANombre, ADef: string): string;
begin
  if (ANodo <> nil) and ANodo.HasAttribute(ANombre) then
    Result := VarToStr(ANodo.Attributes[ANombre])
  else
    Result := ADef;
end;

// Convierte un texto con punto decimal a Double.
function ParsearNumero(const ATexto: string): Double;
var
  oFmt: TFormatSettings;
begin
  oFmt := TFormatSettings.Create;
  oFmt.DecimalSeparator  := '.';
  oFmt.ThousandSeparator := #0;
  Result := StrToFloatDef(Trim(ATexto), 0, oFmt);
end;

// Convierte una fecha dd-mm-aaaa a TDateTime.
function ParsearFecha(const ATexto: string): TDateTime;
var
  oFmt: TFormatSettings;
begin
  oFmt := TFormatSettings.Create;
  oFmt.DateSeparator   := '-';
  oFmt.ShortDateFormat := 'dd-mm-yyyy';
  Result := StrToDateDef(Trim(ATexto), Now, oFmt);
end;

// Rellena una parte (emisor o receptor) desde su nodo XML.
procedure LeerParte(const ANodo: IXMLNode; out AParte: TFacturaeParte);
begin
  AParte := Default(TFacturaeParte);
  if ANodo = nil then
    Exit;
  AParte.Nif          := Attr(ANodo, 'Nif', '');
  AParte.RazonSocial  := Attr(ANodo, 'RazonSocial', '');
  AParte.Direccion    := Attr(ANodo, 'Direccion', '');
  AParte.CodigoPostal := Attr(ANodo, 'CodigoPostal', '');
  AParte.Poblacion    := Attr(ANodo, 'Poblacion', '');
  AParte.Provincia    := Attr(ANodo, 'Provincia', '');
  AParte.CodigoPais   := Attr(ANodo, 'Pais', 'ESP');
  // Centros DIR3 (solo receptor publico FACe; opcionales).
  AParte.OficinaContable   := Attr(ANodo, 'OficinaContable', '');
  AParte.OrganoGestor      := Attr(ANodo, 'OrganoGestor', '');
  AParte.UnidadTramitadora := Attr(ANodo, 'UnidadTramitadora', '');
end;

// --- Programa --------------------------------------------------------------

procedure Ejecutar(const ARutaXml, ASalida, ASerial, ATitular: string);
var
  oDoc:       IXMLDocument;
  oRaiz:      IXMLNode;
  oNodo:      IXMLNode;
  oFactura:   TFacturaeFactura;
  oDatosCert: TXadesDatosCertificado;
  bFirmar:    Boolean;
  i:          Integer;
  sXml:       string;
  sArchivo:   string;
begin
  if not FileExists(ARutaXml) then
    raise Exception.Create('No se encuentra el XML de entrada: ' + ARutaXml);
  bFirmar := (ASerial <> '') or (ATitular <> '');

  DefaultDOMVendor := sOmniXmlVendor;
  oDoc := LoadXMLDocument(ARutaXml);
  oRaiz := oDoc.DocumentElement;

  Writeln('====================================================');
  Writeln(' Emision Facturae 3.2.2');
  if bFirmar then
    Writeln(' (firmada XAdES)')
  else
    Writeln(' (demo, sin firma)');
  Writeln('====================================================');

  oFactura := Default(TFacturaeFactura);
  oFactura.Version          := Attr(oRaiz, 'Version', '3.2.2');
  oFactura.Serie            := Attr(oRaiz, 'Serie', '');
  oFactura.Numero           := Attr(oRaiz, 'Numero', '');
  oFactura.FechaExpedicion  := ParsearFecha(Attr(oRaiz, 'Fecha', ''));
  oFactura.FormaPagoFacturae := Attr(oRaiz, 'FormaPago', '01');
  oFactura.TipoRetencion    := ParsearNumero(Attr(oRaiz, 'Retencion', '0'));

  LeerParte(oRaiz.ChildNodes.FindNode('Emisor'),   oFactura.Emisor);
  LeerParte(oRaiz.ChildNodes.FindNode('Receptor'), oFactura.Receptor);

  // Una pasada por cada <Linea> del XML.
  for i := 0 to oRaiz.ChildNodes.Count - 1 do
  begin
    oNodo := oRaiz.ChildNodes[i];
    if not SameText(oNodo.NodeName, 'Linea') then
      Continue;
    oFactura.AnadirLinea(
      Attr(oNodo, 'Descripcion', ''),
      ParsearNumero(Attr(oNodo, 'Cantidad', '0')),
      ParsearNumero(Attr(oNodo, 'PrecioUnitario', '0')),
      ParsearNumero(Attr(oNodo, 'TipoIva', '0')),
      ParsearNumero(Attr(oNodo, 'TipoRecargo', '0')));
  end;

  // Valida (lanza EFacturaeError con el detalle si algo falla).
  ValidarFacturae(oFactura);

  Writeln(Format('  Factura            : %s-%s',
    [oFactura.Serie, oFactura.Numero]));
  Writeln(Format('  Lineas             : %d', [Length(oFactura.Lineas)]));
  Writeln(Format('  Base imponible     : %.2f', [oFactura.BaseImponibleTotal]));
  Writeln(Format('  Cuota IVA          : %.2f', [oFactura.CuotaIvaTotal]));
  if oFactura.ImporteRetencion > 0 then
    Writeln(Format('  Retencion IRPF     : %.2f', [oFactura.ImporteRetencion]));
  Writeln(Format('  Total factura      : %.2f', [oFactura.TotalFactura]));

  if bFirmar then
  begin
    // Valida + construye + firma en un paso. Si el certificado falla, sube la
    // excepcion y no se escribe nada (no hay XML sin firma como sustituto).
    sXml := EmitirFacturaeFirmada(oFactura, ASerial, ATitular, oDatosCert);
    sArchivo := ASalida;
    if sArchivo = '' then
      sArchivo := NombreArchivoFacturae(oFactura.Serie, oFactura.Numero);
    TFile.WriteAllText(sArchivo, sXml, TEncoding.UTF8);
    Writeln('');
    Writeln('Facturae firmada   : ', sArchivo);
    Writeln('Certificado        : ', oDatosCert.Titular);
    Writeln('Huella SHA-1 cert. : ', oDatosCert.HuellaSha1);
  end
  else
  begin
    // Demo: solo el XML Facturae sin firmar (NO valido como factura legal).
    sXml := ConstruirXmlFacturae(oFactura);
    sArchivo := ASalida;
    if sArchivo = '' then
      sArchivo := 'facturae_demo.xml';
    TFile.WriteAllText(sArchivo, sXml, TEncoding.UTF8);
    Writeln('');
    Writeln('Facturae SIN firmar: ', sArchivo);
    Writeln('(demo: anade serial + titular del certificado para firmar .xsig)');
  end;
end;

var
  sRutaXml: string;
begin
  try
    sRutaXml := ParamStr(1);
    if sRutaXml = '' then
      sRutaXml := 'factura.xml';
    Ejecutar(sRutaXml, ParamStr(2), ParamStr(3), ParamStr(4));
  except
    on E: Exception do
    begin
      Writeln('ERROR: ', E.ClassName, ': ', E.Message);
      Halt(2);
    end;
  end;
  Writeln('');
  Write('Pulsa Intro para salir...');
  Readln;
end.
