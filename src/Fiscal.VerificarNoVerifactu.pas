{******************************************************************************}
{                                                                              }
{  Modulo:       Fiscal.VerificarNoVerifactu                                   }
{    Tipo:       Libreria Delphi (ejemplo didactico)                           }
{   Autor:       Alejandro Laorden Hidalgo                                     }
{                                                                              }
{  SPDX-License-Identifier: MIT                                                }
{                                                                              }
{  Descripcion:                                                                }
{    Verificacion LOCAL de los ficheros NO VERI*FACTU exportados por           }
{    Fiscal.NoVerifactu (registro de eventos y registro de facturacion).       }
{    Comprueba, sin red ni procesos externos:                                  }
{                                                                              }
{      1. Estructura: raices y que cada fichero tenga registros.               }
{      2. Cadena de eventos: HashAnterior enlaza con el HashPropio del         }
{         evento previo (el primero arranca con 64 ceros).                     }
{      3. Coherencia de huella: la huella del contenedor coincide con la del   }
{         registro/evento firmado embebido.                                    }
{      4. Coherencia de firma: el SignatureValue del XML coincide con la       }
{         firma guardada y, en eventos, FirmaDigital = SHA-256 de la firma.    }
{      5. Perfil XAdES: algoritmos (RSA-SHA256, SHA-256, C14N) y politica AGE  }
{         (urn:oid:2.16.724.1.3.1.1.2.1.9) exigidos por la AEAT.               }
{                                                                              }
{    IMPORTANTE: NO valida criptograficamente la firma RSA (no rehace el       }
{    digest ni comprueba la cadena del certificado). Para esa validacion       }
{    legal completa hay que llevar un registro individual firmado a VALIDe.    }
{    Esto comprueba estructura, encadenamiento y coherencia/perfil de firma.   }
{                                                                              }
{    El modo se lee del atributo ModoVerifactu del XML: en NO_VERIFACTU la     }
{    falta de firma es ERROR; en SIN (demo) es solo un AVISO.                  }
{******************************************************************************}
unit Fiscal.VerificarNoVerifactu;

interface

uses
  System.SysUtils;

type
  // Resultado de verificar uno o los dos ficheros exportados.
  TResultadoVerificacion = record
    ArchivoEventos:       string;
    ArchivoFacturacion:   string;
    ModoExportacion:      string;   // NO_VERIFACTU / SIN (del atributo del XML)
    Eventos:              Integer;
    RegistrosFacturacion: Integer;
    Errores:              Integer;
    Avisos:               Integer;
    Detalle:              string;   // lineas 'ERROR: ...' / 'AVISO: ...'
    // True si no hay errores (los avisos no invalidan la verificacion).
    function Correcto: Boolean;
    // Resumen de varias lineas para mostrar por pantalla.
    function Resumen: string;
  end;

// A partir del fichero seleccionado deduce los dos ficheros hermanos
// (<base>_eventos.xml y <base>_facturacion.xml).
procedure InferirFicheros(const AArchivoSeleccionado: string;
                          out AArchivoEventos, AArchivoFacturacion: string);
// Verifica los ficheros indicados. Cualquiera de los dos puede ir vacio ('')
// para omitirlo (p.ej. verificar solo el libro de eventos).
function VerificarFicheros(const AArchivoEventos,
                           AArchivoFacturacion: string):
                           TResultadoVerificacion;
// Igual que VerificarFicheros pero recibiendo el XML en memoria (util para
// pruebas o para verificar lo que se acaba de generar sin pasar por disco).
function VerificarContenido(const AXmlEventos,
                            AXmlFacturacion: string):
                            TResultadoVerificacion;

implementation

uses
  System.Hash, System.IOUtils, System.StrUtils,
  Xml.xmldom, Xml.omnixmldom,
  Xml.XMLDoc, Xml.XMLIntf,
  Fiscal.NoVerifactu;

const
  // Perfil de firma exigido por la AEAT (coincide con OpcionesXadesNoVerifactu)
  cAlgC14n      = 'http://www.w3.org/TR/2001/REC-xml-c14n-20010315';
  cAlgEnveloped = 'http://www.w3.org/2000/09/xmldsig#enveloped-signature';
  cAlgRsaSha256 = 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256';
  cAlgSha1      = 'http://www.w3.org/2000/09/xmldsig#sha1';
  cAlgSha256    = 'http://www.w3.org/2001/04/xmlenc#sha256';
  cTipoSignedProperties = 'http://uri.etsi.org/01903#SignedProperties';
  cPoliticaAeatId  = 'urn:oid:2.16.724.1.3.1.1.2.1.9';
  cPoliticaAeatUrl =
    'https://sede.administracion.gob.es/politica_de_firma_anexo_1.pdf';
  cPoliticaAeatHashSha1 = 'G7roucf600+f03r/o0bAOQ6WAs0=';

// --- Acumulacion de incidencias --------------------------------------------

procedure AgregarDetalle(var AResultado: TResultadoVerificacion;
                         const ATipo, AMensaje: string);
begin
  if AResultado.Detalle <> '' then
    AResultado.Detalle := AResultado.Detalle + sLineBreak;
  AResultado.Detalle := AResultado.Detalle + ATipo + ': ' + AMensaje;
  if SameText(ATipo, 'ERROR') then
    Inc(AResultado.Errores)
  else
    Inc(AResultado.Avisos);
end;

// True cuando el fichero declara modo legal (NO_VERIFACTU). En ese caso la
// falta de firma es ERROR; en SIN/demo es solo AVISO.
function VerificacionLegal(const AResultado: TResultadoVerificacion): Boolean;
begin
  Result := SameText(AResultado.ModoExportacion, cModoNoVerifactu);
end;

function TipoIncidenciaFirma(const AResultado: TResultadoVerificacion): string;
begin
  if VerificacionLegal(AResultado) then
    Result := 'ERROR'
  else
    Result := 'AVISO';
end;

// --- Ayudantes XML (independientes del prefijo de namespace) ---------------

function NombreLocal(const ANodeName: string): string;
var
  iPos: Integer;
begin
  Result := ANodeName;
  iPos := Pos(':', Result);
  if iPos > 0 then
    Result := Copy(Result, iPos + 1, MaxInt);
end;

function EsNodo(const ANode: IXMLNode; const ANombreLocal: string): Boolean;
begin
  Result := (ANode <> nil) and
            SameText(NombreLocal(ANode.NodeName), ANombreLocal);
end;

function BuscarHijo(const ANode: IXMLNode; const ANombreLocal: string):
  IXMLNode;
var
  i: Integer;
begin
  Result := nil;
  if ANode <> nil then
    for i := 0 to ANode.ChildNodes.Count - 1 do
      if (Result = nil) and EsNodo(ANode.ChildNodes[i], ANombreLocal) then
        Result := ANode.ChildNodes[i];
end;

function BuscarDescendiente(const ANode: IXMLNode;
                            const ANombreLocal: string): IXMLNode;
var
  i:     Integer;
  oHijo: IXMLNode;
begin
  Result := nil;
  if ANode <> nil then
  begin
    i := 0;
    while (Result = nil) and (i < ANode.ChildNodes.Count) do
    begin
      oHijo := ANode.ChildNodes[i];
      if EsNodo(oHijo, ANombreLocal) then
        Result := oHijo
      else
        Result := BuscarDescendiente(oHijo, ANombreLocal);
      Inc(i);
    end;
  end;
end;

function AtributoNodo(const ANode: IXMLNode; const ANombre: string): string;
var
  oAtributo: IXMLNode;
begin
  Result := '';
  if ANode <> nil then
  begin
    oAtributo := ANode.AttributeNodes.FindNode(ANombre);
    if oAtributo <> nil then
      Result := Trim(oAtributo.Text);
  end;
end;

function BuscarHijoConAtributo(const ANode: IXMLNode; const ANombreLocal,
                               AAtributo, AValor: string): IXMLNode;
var
  i:     Integer;
  oHijo: IXMLNode;
begin
  Result := nil;
  if ANode <> nil then
    for i := 0 to ANode.ChildNodes.Count - 1 do
    begin
      oHijo := ANode.ChildNodes[i];
      if (Result = nil) and EsNodo(oHijo, ANombreLocal) and
         SameText(AtributoNodo(oHijo, AAtributo), AValor) then
        Result := oHijo;
    end;
end;

function BuscarDescendienteConAtributo(const ANode: IXMLNode;
                                       const ANombreLocal, AAtributo,
                                       AValor: string): IXMLNode;
var
  i:     Integer;
  oHijo: IXMLNode;
begin
  Result := nil;
  if ANode <> nil then
  begin
    i := 0;
    while (Result = nil) and (i < ANode.ChildNodes.Count) do
    begin
      oHijo := ANode.ChildNodes[i];
      if EsNodo(oHijo, ANombreLocal) and
         SameText(AtributoNodo(oHijo, AAtributo), AValor) then
        Result := oHijo
      else
        Result := BuscarDescendienteConAtributo(oHijo, ANombreLocal,
          AAtributo, AValor);
      Inc(i);
    end;
  end;
end;

function BuscarRuta(const ANode: IXMLNode;
                    const ANombres: array of string): IXMLNode;
var
  i: Integer;
begin
  Result := ANode;
  i := Low(ANombres);
  while (Result <> nil) and (i <= High(ANombres)) do
  begin
    Result := BuscarHijo(Result, ANombres[i]);
    Inc(i);
  end;
end;

function TextoRuta(const ANode: IXMLNode;
                   const ANombres: array of string): string;
var
  oNodo: IXMLNode;
begin
  Result := '';
  oNodo := BuscarRuta(ANode, ANombres);
  if oNodo <> nil then
    Result := Trim(oNodo.Text);
end;

function ContarHijos(const ANode: IXMLNode; const ANombreLocal: string):
  Integer;
var
  i: Integer;
begin
  Result := 0;
  if ANode <> nil then
    for i := 0 to ANode.ChildNodes.Count - 1 do
      if EsNodo(ANode.ChildNodes[i], ANombreLocal) then
        Inc(Result);
end;

function TextoHijo(const ANode: IXMLNode; const ANombreLocal: string): string;
var
  oHijo: IXMLNode;
begin
  Result := '';
  oHijo := BuscarHijo(ANode, ANombreLocal);
  if oHijo <> nil then
    Result := Trim(oHijo.Text);
end;

function CargarXmlArchivo(const AArchivo: string): IXMLDocument;
begin
  DefaultDOMVendor := sOmniXmlVendor;
  Result := TXMLDocument.Create(nil);
  Result.LoadFromFile(AArchivo);
  Result.Active := True;
end;

function CargarXmlTexto(const AXml: string; out ADocumento: IXMLDocument):
  Boolean;
begin
  Result := False;
  ADocumento := nil;
  if Trim(AXml) <> '' then
    try
      DefaultDOMVendor := sOmniXmlVendor;
      ADocumento := TXMLDocument.Create(nil);
      ADocumento.LoadFromXML(AXml);
      ADocumento.Active := True;
      Result := True;
    except
      ADocumento := nil;
    end;
end;

// Texto del primer descendiente con ese nombre local dentro de un XML suelto.
function TextoEtiquetaXml(const AXml, ANombreLocal: string): string;
var
  oDoc:  IXMLDocument;
  oNodo: IXMLNode;
begin
  Result := '';
  if CargarXmlTexto(AXml, oDoc) then
  begin
    oNodo := BuscarDescendiente(oDoc.DocumentElement, ANombreLocal);
    if oNodo <> nil then
      Result := Trim(oNodo.Text);
  end;
end;

// Huella propia (HuellaEvento) del evento embebido.
function TextoHuellaEventoPropia(const AXml: string): string;
var
  oDoc:    IXMLDocument;
  oRaiz:   IXMLNode;
  oEvento: IXMLNode;
  oHuella: IXMLNode;
begin
  Result := '';
  if CargarXmlTexto(AXml, oDoc) then
  begin
    oRaiz := oDoc.DocumentElement;
    if EsNodo(oRaiz, 'RegistroEvento') then
      oEvento := BuscarHijo(oRaiz, 'Evento')
    else if EsNodo(oRaiz, 'Evento') then
      oEvento := oRaiz
    else
      oEvento := nil;
    oHuella := BuscarHijo(oEvento, 'HuellaEvento');
    if oHuella <> nil then
      Result := Trim(oHuella.Text);
  end;
end;

// Huella propia (Huella) del registro de facturacion embebido.
function TextoHuellaRegistroPropia(const AXml: string): string;
var
  oDoc:    IXMLDocument;
  oRaiz:   IXMLNode;
  oHuella: IXMLNode;
begin
  Result := '';
  if CargarXmlTexto(AXml, oDoc) then
  begin
    oRaiz := oDoc.DocumentElement;
    if EsNodo(oRaiz, 'RegistroAlta') or EsNodo(oRaiz, 'RegistroAnulacion') then
    begin
      // Huella propia = hijo directo (la del encadenamiento es nieta).
      oHuella := BuscarHijo(oRaiz, 'Huella');
      if oHuella <> nil then
        Result := Trim(oHuella.Text);
    end;
  end;
end;

function Sha256HexMayus(const AValor: string): string;
begin
  Result := UpperCase(THashSHA2.GetHashString(AValor));
end;

function EsHashSha256(const AValor: string): Boolean;
var
  i:      Integer;
  sValor: string;
begin
  sValor := UpperCase(Trim(AValor));
  Result := Length(sValor) = 64;
  i := 1;
  while Result and (i <= Length(sValor)) do
  begin
    Result := CharInSet(sValor[i], ['0'..'9', 'A'..'F']);
    Inc(i);
  end;
end;

function HayFirmaXml(const AXml: string): Boolean;
begin
  Result := (Pos('<ds:Signature', AXml) > 0) or (Pos('<Signature', AXml) > 0);
end;

// --- Perfil XAdES (estructura y politica AGE) ------------------------------

procedure VerificarPerfilXades(const AXml, AEtiqueta: string;
                               AEsEvento: Boolean;
                               var AResultado: TResultadoVerificacion);
var
  oDoc:          IXMLDocument;
  oRaiz:         IXMLNode;
  oNodoFirmado:  IXMLNode;
  oFirma:        IXMLNode;
  oSignedInfo:   IXMLNode;
  oMetodo:       IXMLNode;
  oRefDocumento: IXMLNode;
  oRefPropiedades: IXMLNode;
  oDigestMethod: IXMLNode;
  oPropiedades:  IXMLNode;
  oPolitica:     IXMLNode;
  sRaiz:         string;
  sTipo:         string;
begin
  sTipo := TipoIncidenciaFirma(AResultado);
  if not CargarXmlTexto(AXml, oDoc) then
  begin
    AgregarDetalle(AResultado, sTipo,
      AEtiqueta + ': el XML firmado no se puede leer.');
    Exit;
  end;
  oRaiz := oDoc.DocumentElement;
  sRaiz := NombreLocal(oRaiz.NodeName);
  oNodoFirmado := oRaiz;
  if AEsEvento then
  begin
    if not SameText(sRaiz, 'RegistroEvento') then
      AgregarDetalle(AResultado, sTipo,
        AEtiqueta + ': la firma de evento debe envolver RegistroEvento.');
    oNodoFirmado := BuscarHijo(oRaiz, 'Evento');
    if oNodoFirmado = nil then
      AgregarDetalle(AResultado, sTipo,
        AEtiqueta + ': falta el nodo Evento firmado.');
  end
  else if (not SameText(sRaiz, 'RegistroAlta')) and
          (not SameText(sRaiz, 'RegistroAnulacion')) then
    AgregarDetalle(AResultado, sTipo,
      AEtiqueta + ': la firma debe envolver RegistroAlta o RegistroAnulacion.');

  oFirma := BuscarHijo(oNodoFirmado, 'Signature');
  if oFirma = nil then
  begin
    AgregarDetalle(AResultado, sTipo,
      AEtiqueta + ': la firma XAdES no esta en el nodo exigido por la AEAT.');
    Exit;
  end;

  if BuscarDescendiente(oFirma, 'X509Certificate') = nil then
    AgregarDetalle(AResultado, sTipo,
      AEtiqueta + ': falta certificado X509 en KeyInfo.');

  oSignedInfo := BuscarHijo(oFirma, 'SignedInfo');
  if oSignedInfo = nil then
    AgregarDetalle(AResultado, sTipo, AEtiqueta + ': falta SignedInfo.')
  else
  begin
    oMetodo := BuscarHijo(oSignedInfo, 'CanonicalizationMethod');
    if AtributoNodo(oMetodo, 'Algorithm') <> cAlgC14n then
      AgregarDetalle(AResultado, sTipo,
        AEtiqueta + ': CanonicalizationMethod no coincide con AEAT.');
    oMetodo := BuscarHijo(oSignedInfo, 'SignatureMethod');
    if AtributoNodo(oMetodo, 'Algorithm') <> cAlgRsaSha256 then
      AgregarDetalle(AResultado, sTipo,
        AEtiqueta + ': SignatureMethod debe ser RSA-SHA256.');
    if ContarHijos(oSignedInfo, 'Reference') <> 2 then
      AgregarDetalle(AResultado, sTipo,
        AEtiqueta + ': SignedInfo debe tener referencia al documento y a ' +
        'SignedProperties.');
    oRefDocumento := BuscarHijoConAtributo(oSignedInfo, 'Reference', 'URI', '');
    if oRefDocumento = nil then
      AgregarDetalle(AResultado, sTipo,
        AEtiqueta + ': falta Reference URI vacio al registro firmado.')
    else
    begin
      if BuscarDescendienteConAtributo(oRefDocumento, 'Transform',
         'Algorithm', cAlgEnveloped) = nil then
        AgregarDetalle(AResultado, sTipo,
          AEtiqueta + ': falta transform enveloped-signature.');
      oDigestMethod := BuscarDescendiente(oRefDocumento, 'DigestMethod');
      if AtributoNodo(oDigestMethod, 'Algorithm') <> cAlgSha256 then
        AgregarDetalle(AResultado, sTipo,
          AEtiqueta + ': digest del registro debe ser SHA-256.');
    end;
    oRefPropiedades := BuscarHijoConAtributo(oSignedInfo, 'Reference',
      'Type', cTipoSignedProperties);
    if oRefPropiedades = nil then
      AgregarDetalle(AResultado, sTipo,
        AEtiqueta + ': falta Reference a SignedProperties.')
    else
    begin
      oDigestMethod := BuscarDescendiente(oRefPropiedades, 'DigestMethod');
      if AtributoNodo(oDigestMethod, 'Algorithm') <> cAlgSha256 then
        AgregarDetalle(AResultado, sTipo,
          AEtiqueta + ': digest de SignedProperties debe ser SHA-256.');
    end;
  end;

  oPropiedades := BuscarDescendiente(oFirma, 'QualifyingProperties');
  if oPropiedades = nil then
    AgregarDetalle(AResultado, sTipo,
      AEtiqueta + ': falta QualifyingProperties XAdES.')
  else
  begin
    if BuscarDescendiente(oPropiedades, 'SignedProperties') = nil then
      AgregarDetalle(AResultado, sTipo,
        AEtiqueta + ': falta SignedProperties XAdES.');
    if BuscarDescendiente(oPropiedades, 'SigningCertificate') = nil then
      AgregarDetalle(AResultado, sTipo,
        AEtiqueta + ': falta SigningCertificate.');
    oPolitica := BuscarRuta(oPropiedades,
      ['SignedProperties', 'SignedSignatureProperties',
       'SignaturePolicyIdentifier', 'SignaturePolicyId']);
    if oPolitica = nil then
      AgregarDetalle(AResultado, sTipo,
        AEtiqueta + ': falta politica de firma AGE.')
    else
    begin
      if TextoRuta(oPolitica, ['SigPolicyId', 'Identifier']) <>
         cPoliticaAeatId then
        AgregarDetalle(AResultado, sTipo,
          AEtiqueta + ': identificador de politica AGE incorrecto.');
      oDigestMethod := BuscarRuta(oPolitica, ['SigPolicyHash', 'DigestMethod']);
      if AtributoNodo(oDigestMethod, 'Algorithm') <> cAlgSha1 then
        AgregarDetalle(AResultado, sTipo,
          AEtiqueta + ': digest de politica AGE debe ser SHA-1.');
      if TextoRuta(oPolitica, ['SigPolicyHash', 'DigestValue']) <>
         cPoliticaAeatHashSha1 then
        AgregarDetalle(AResultado, sTipo,
          AEtiqueta + ': DigestValue de politica AGE incorrecto.');
      if TextoRuta(oPolitica, ['SigPolicyQualifiers', 'SigPolicyQualifier',
         'SPURI']) <> cPoliticaAeatUrl then
        AgregarDetalle(AResultado, sTipo,
          AEtiqueta + ': URL de politica AGE incorrecta.');
    end;
  end;
end;

// --- Verificacion de un evento y de un registro de facturacion -------------

procedure VerificarEvento(const AEvento: IXMLNode; AIndice: Integer;
                          var AHashAnteriorEsperado: string;
                          var AResultado: TResultadoVerificacion);
var
  sId:             string;
  sHashAnterior:   string;
  sHashPropio:     string;
  sFirmaDigital:   string;
  sRegistroXml:    string;
  sFirmaXades:     string;
  sHuellaXml:      string;
  sSignatureValue: string;
  sTipo:           string;
begin
  sTipo := TipoIncidenciaFirma(AResultado);
  sId := TextoHijo(AEvento, 'Id');
  sHashAnterior := UpperCase(TextoHijo(AEvento, 'HashAnterior'));
  sHashPropio   := UpperCase(TextoHijo(AEvento, 'HashPropio'));
  sFirmaDigital := UpperCase(TextoHijo(AEvento, 'FirmaDigital'));
  sRegistroXml  := TextoHijo(AEvento, 'RegistroXmlFirmado');
  sFirmaXades   := TextoHijo(AEvento, 'FirmaXades');

  if not EsHashSha256(sHashPropio) then
    AgregarDetalle(AResultado, 'ERROR',
      'Evento ' + sId + ': HashPropio no es SHA-256 hexadecimal.');
  if AIndice = 1 then
  begin
    if (sHashAnterior <> '') and (sHashAnterior <> StringOfChar('0', 64)) then
      AgregarDetalle(AResultado, 'AVISO',
        'Evento ' + sId + ': primer HashAnterior no es cero.');
  end
  else if sHashAnterior <> AHashAnteriorEsperado then
    AgregarDetalle(AResultado, 'ERROR',
      'Evento ' + sId + ': HashAnterior no coincide con el evento anterior.');

  if Trim(sRegistroXml) = '' then
    AgregarDetalle(AResultado, sTipo,
      'Evento ' + sId + ': falta RegistroXmlFirmado.')
  else
  begin
    sHuellaXml := UpperCase(TextoHuellaEventoPropia(sRegistroXml));
    if (sHuellaXml <> '') and (sHuellaXml <> sHashPropio) then
      AgregarDetalle(AResultado, 'ERROR',
        'Evento ' + sId + ': HuellaEvento no coincide con HashPropio.');
    if (sFirmaXades <> '') and (not HayFirmaXml(sRegistroXml)) then
      AgregarDetalle(AResultado, sTipo,
        'Evento ' + sId + ': hay FirmaXades pero el XML no contiene firma.');
    if sFirmaXades = '' then
      AgregarDetalle(AResultado, sTipo,
        'Evento ' + sId + ': falta FirmaXades legal.')
    else
    begin
      sSignatureValue := TextoEtiquetaXml(sRegistroXml, 'SignatureValue');
      if (sSignatureValue <> '') and (sSignatureValue <> sFirmaXades) then
        AgregarDetalle(AResultado, 'ERROR',
          'Evento ' + sId + ': SignatureValue no coincide con FirmaXades.');
      if (sFirmaDigital <> '') and
         (sFirmaDigital <> Sha256HexMayus(sFirmaXades)) then
        AgregarDetalle(AResultado, 'ERROR',
          'Evento ' + sId + ': FirmaDigital no coincide con FirmaXades.');
      VerificarPerfilXades(sRegistroXml, 'Evento ' + sId, True, AResultado);
    end;
  end;
  AHashAnteriorEsperado := sHashPropio;
end;

procedure VerificarRegistroFactura(const ARegistro: IXMLNode; AIndice: Integer;
                                   var AResultado: TResultadoVerificacion);
var
  sSerie:          string;
  sNumero:         string;
  sEtiqueta:       string;
  sRegistroXml:    string;
  sHuella:         string;
  sHuellaXml:      string;
  sFirma:          string;
  sSignatureValue: string;
  sTipo:           string;
begin
  sTipo := TipoIncidenciaFirma(AResultado);
  sSerie  := TextoHijo(ARegistro, 'Serie');
  sNumero := TextoHijo(ARegistro, 'Numero');
  sEtiqueta := sSerie + '/' + sNumero;
  if Trim(sEtiqueta) = '/' then
    sEtiqueta := 'registro ' + IntToStr(AIndice);
  sRegistroXml := TextoHijo(ARegistro, 'RegistroXmlFirmado');
  sHuella := UpperCase(TextoHijo(ARegistro, 'Huella'));
  sFirma  := TextoHijo(ARegistro, 'FirmaDigitalXades');

  if (sHuella <> '') and (not EsHashSha256(sHuella)) then
    AgregarDetalle(AResultado, 'ERROR',
      'Factura ' + sEtiqueta + ': Huella no es SHA-256 hexadecimal.');
  if Trim(sRegistroXml) = '' then
    AgregarDetalle(AResultado, sTipo,
      'Factura ' + sEtiqueta + ': falta RegistroXmlFirmado.')
  else
  begin
    sHuellaXml := UpperCase(TextoHuellaRegistroPropia(sRegistroXml));
    if (sHuellaXml <> '') and (sHuella <> '') and (sHuellaXml <> sHuella) then
      AgregarDetalle(AResultado, 'ERROR',
        'Factura ' + sEtiqueta + ': Huella no coincide con la del registro ' +
        'firmado.');
    if (sFirma <> '') and (not HayFirmaXml(sRegistroXml)) then
      AgregarDetalle(AResultado, sTipo,
        'Factura ' + sEtiqueta + ': hay firma guardada pero el XML no firma.');
    if sFirma = '' then
      AgregarDetalle(AResultado, sTipo,
        'Factura ' + sEtiqueta + ': falta FirmaDigitalXades legal.')
    else
    begin
      sSignatureValue := TextoEtiquetaXml(sRegistroXml, 'SignatureValue');
      if (sSignatureValue <> '') and (sSignatureValue <> sFirma) then
        AgregarDetalle(AResultado, 'ERROR',
          'Factura ' + sEtiqueta + ': SignatureValue no coincide.');
      VerificarPerfilXades(sRegistroXml, 'Factura ' + sEtiqueta, False,
        AResultado);
    end;
  end;
end;

// --- Recorrido de los contenedores -----------------------------------------

procedure CapturarModo(var AResultado: TResultadoVerificacion;
                       const ARaiz: IXMLNode; const AEtiqueta: string);
var
  sModo: string;
begin
  sModo := UpperCase(Trim(AtributoNodo(ARaiz, 'ModoVerifactu')));
  if sModo <> '' then
  begin
    if AResultado.ModoExportacion = '' then
      AResultado.ModoExportacion := sModo
    else if AResultado.ModoExportacion <> sModo then
      AgregarDetalle(AResultado, 'ERROR',
        AEtiqueta + ': ModoVerifactu no coincide con el otro fichero.');
  end;
end;

procedure VerificarRaizEventos(const ARaiz: IXMLNode;
                               var AResultado: TResultadoVerificacion);
var
  oNodo: IXMLNode;
  sHashAnterior: string;
  i: Integer;
begin
  if ARaiz = nil then
  begin
    AgregarDetalle(AResultado, 'ERROR', 'Eventos: XML vacio o ilegible.');
    Exit;
  end;
  CapturarModo(AResultado, ARaiz, 'Eventos');
  if not EsNodo(ARaiz, 'RegistroEventosNoVerifactu') then
    AgregarDetalle(AResultado, 'ERROR',
      'El fichero de eventos no tiene la raiz esperada.');
  sHashAnterior := '';
  for i := 0 to ARaiz.ChildNodes.Count - 1 do
  begin
    oNodo := ARaiz.ChildNodes[i];
    if EsNodo(oNodo, 'Evento') then
    begin
      Inc(AResultado.Eventos);
      VerificarEvento(oNodo, AResultado.Eventos, sHashAnterior, AResultado);
    end;
  end;
  if AResultado.Eventos = 0 then
    AgregarDetalle(AResultado, 'ERROR',
      'El fichero de eventos no contiene eventos.');
end;

procedure VerificarRaizFacturacion(const ARaiz: IXMLNode;
                                   var AResultado: TResultadoVerificacion);
var
  oNodo: IXMLNode;
  i: Integer;
begin
  if ARaiz = nil then
  begin
    AgregarDetalle(AResultado, 'ERROR', 'Facturacion: XML vacio o ilegible.');
    Exit;
  end;
  CapturarModo(AResultado, ARaiz, 'Facturacion');
  if not EsNodo(ARaiz, 'RegistroFacturacionNoVerifactu') then
    AgregarDetalle(AResultado, 'ERROR',
      'El fichero de facturacion no tiene la raiz esperada.');
  for i := 0 to ARaiz.ChildNodes.Count - 1 do
  begin
    oNodo := ARaiz.ChildNodes[i];
    if EsNodo(oNodo, 'RegistroFactura') then
    begin
      Inc(AResultado.RegistrosFacturacion);
      VerificarRegistroFactura(oNodo, AResultado.RegistrosFacturacion,
        AResultado);
    end;
  end;
  if AResultado.RegistrosFacturacion = 0 then
    AgregarDetalle(AResultado, 'ERROR',
      'El fichero de facturacion no contiene registros.');
end;

// --- API publica -----------------------------------------------------------

function NuevoResultado(const AArchivoEventos,
                        AArchivoFacturacion: string): TResultadoVerificacion;
begin
  Result := Default(TResultadoVerificacion);
  Result.ArchivoEventos     := AArchivoEventos;
  Result.ArchivoFacturacion := AArchivoFacturacion;
end;

procedure InferirFicheros(const AArchivoSeleccionado: string;
                          out AArchivoEventos, AArchivoFacturacion: string);
var
  sDir:    string;
  sNombre: string;
  sBase:   string;
begin
  sDir := TPath.GetDirectoryName(AArchivoSeleccionado);
  sNombre := TPath.GetFileNameWithoutExtension(AArchivoSeleccionado);
  if EndsText('_eventos', sNombre) then
    sBase := Copy(sNombre, 1, Length(sNombre) - Length('_eventos'))
  else if EndsText('_facturacion', sNombre) then
    sBase := Copy(sNombre, 1, Length(sNombre) - Length('_facturacion'))
  else
    sBase := sNombre;
  AArchivoEventos     := TPath.Combine(sDir, sBase + '_eventos.xml');
  AArchivoFacturacion := TPath.Combine(sDir, sBase + '_facturacion.xml');
end;

function VerificarFicheros(const AArchivoEventos,
                           AArchivoFacturacion: string):
                           TResultadoVerificacion;
begin
  Result := NuevoResultado(AArchivoEventos, AArchivoFacturacion);
  if (Trim(AArchivoEventos) = '') and (Trim(AArchivoFacturacion) = '') then
  begin
    AgregarDetalle(Result, 'ERROR', 'No se indico ningun fichero a verificar.');
    Exit;
  end;
  if Trim(AArchivoEventos) <> '' then
    try
      if TFile.Exists(AArchivoEventos) then
        VerificarRaizEventos(CargarXmlArchivo(AArchivoEventos).DocumentElement,
          Result)
      else
        AgregarDetalle(Result, 'ERROR',
          'No existe el fichero de eventos: ' + AArchivoEventos);
    except
      on E: Exception do
        AgregarDetalle(Result, 'ERROR',
          'No se pudo verificar eventos: ' + E.Message);
    end;
  if Trim(AArchivoFacturacion) <> '' then
    try
      if TFile.Exists(AArchivoFacturacion) then
        VerificarRaizFacturacion(
          CargarXmlArchivo(AArchivoFacturacion).DocumentElement, Result)
      else
        AgregarDetalle(Result, 'ERROR',
          'No existe el fichero de facturacion: ' + AArchivoFacturacion);
    except
      on E: Exception do
        AgregarDetalle(Result, 'ERROR',
          'No se pudo verificar facturacion: ' + E.Message);
    end;
  if Result.Detalle = '' then
    Result.Detalle := 'Verificacion correcta.';
end;

function VerificarContenido(const AXmlEventos,
                            AXmlFacturacion: string):
                            TResultadoVerificacion;
var
  oDoc: IXMLDocument;
begin
  Result := NuevoResultado('(memoria eventos)', '(memoria facturacion)');
  if Trim(AXmlEventos) <> '' then
  begin
    if CargarXmlTexto(AXmlEventos, oDoc) then
      VerificarRaizEventos(oDoc.DocumentElement, Result)
    else
      AgregarDetalle(Result, 'ERROR', 'El XML de eventos no se puede leer.');
  end;
  if Trim(AXmlFacturacion) <> '' then
  begin
    if CargarXmlTexto(AXmlFacturacion, oDoc) then
      VerificarRaizFacturacion(oDoc.DocumentElement, Result)
    else
      AgregarDetalle(Result, 'ERROR',
        'El XML de facturacion no se puede leer.');
  end;
  if Result.Detalle = '' then
    Result.Detalle := 'Verificacion correcta.';
end;

{ TResultadoVerificacion }

function TResultadoVerificacion.Correcto: Boolean;
begin
  Result := Errores = 0;
end;

function TResultadoVerificacion.Resumen: string;
var
  sModo: string;
begin
  sModo := ModoExportacion;
  if sModo = '' then
    sModo := '(no declarado)';
  Result :=
    'Modo                     : ' + sModo + sLineBreak +
    'Eventos                  : ' + IntToStr(Eventos) + sLineBreak +
    'Registros de facturacion : ' + IntToStr(RegistrosFacturacion) +
    sLineBreak +
    'Errores                  : ' + IntToStr(Errores) + sLineBreak +
    'Avisos                   : ' + IntToStr(Avisos);
end;

end.
