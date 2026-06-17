{******************************************************************************}
{  RegistrarFacturasNoVerifactu - Ejemplo integral NO VERI*FACTU               }
{                                                                              }
{  Lee facturas desde un XML sencillo (sin base de datos) y genera los dos     }
{  ficheros que exige el modo NO VERI*FACTU:                                   }
{                                                                              }
{    1. Comprueba el reloj fiscal (margen de un minuto). Si esta desfasado,    }
{       DENIEGA y no emite nada (Fiscal.RelojFiscal).                          }
{    2. Por cada factura construye el RegistroAlta (Fiscal.EnvioVerifactu),    }
{       encadena su huella SHA-256 y lo firma con XAdES si hay certificado     }
{       (Fiscal.NoVerifactu + Fiscal.Xades).                                   }
{    3. Lleva un libro de eventos en paralelo (abrir programa, factura         }
{       creada, exportaciones...).                                            }
{    4. Escribe <base>_facturacion.xml y <base>_eventos.xml.                   }
{                                                                              }
{  Uso:  RegistrarFacturasNoVerifactu.exe facturas.xml [salidaBase]            }
{                                          [serialCert] [titular]              }
{        Sin serial/titular -> modo DEMO (huella SHA-256, sin firma).          }
{        Con serial/titular -> firma XAdES con el certificado de Windows.      }
{******************************************************************************}
program RegistrarFacturasNoVerifactu;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.StrUtils,
  System.Variants,
  System.IOUtils,
  Xml.XMLDoc,
  Xml.XMLIntf,
  Fiscal.Xades in '..\..\src\Fiscal.Xades.pas',
  Fiscal.RelojFiscal in '..\..\src\Fiscal.RelojFiscal.pas',
  Fiscal.EnvioVerifactu in '..\..\src\Fiscal.EnvioVerifactu.pas',
  Fiscal.NoVerifactu in '..\..\src\Fiscal.NoVerifactu.pas';

// --- Pequenos ayudantes de lectura del XML ---------------------------------

// Lee un atributo de un nodo, con valor por defecto si no existe.
function Attr(const ANodo: IXMLNode; const ANombre, ADef: string): string;
begin
  if (ANodo <> nil) and ANodo.HasAttribute(ANombre) then
    Result := VarToStr(ANodo.Attributes[ANombre])
  else
    Result := ADef;
end;

// Convierte un texto con punto decimal a Currency.
function ParsearImporte(const ATexto: string): Currency;
var
  oFmt: TFormatSettings;
begin
  oFmt := TFormatSettings.Create;
  oFmt.DecimalSeparator  := '.';
  oFmt.ThousandSeparator := #0;
  Result := StrToCurrDef(Trim(ATexto), 0, oFmt);
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

// --- Reloj fiscal ----------------------------------------------------------

// Aplica el control de reloj antes de emitir. Lanza si esta desfasado.
procedure ComprobarReloj(const ARaiz: IXMLNode);
var
  iMargen:     Integer;
  dDesfaseSim: Double;
  oFmt:        TFormatSettings;
  dSistemaSim: TDateTime;
  dReferencia: TDateTime;
  oResultado:  TResultadoReloj;
begin
  if Attr(ARaiz, 'comprobarReloj', '1') = '0' then
  begin
    Writeln('Reloj fiscal       : comprobacion desactivada (demo).');
    Exit;
  end;
  oFmt := TFormatSettings.Create;
  oFmt.DecimalSeparator  := '.';
  oFmt.ThousandSeparator := #0;
  iMargen     := StrToIntDef(Attr(ARaiz, 'margenSegundos', '60'), 60);
  dDesfaseSim := StrToFloatDef(Attr(ARaiz, 'desfaseSimuladoSegundos', '0'),
    0, oFmt);
  // Sin conexion: la referencia es la propia hora del sistema; el desfase
  // simulado permite probar el bloqueo (pon 90 en el XML para ver DENEGADO).
  dReferencia := HoraSistemaUtc;
  dSistemaSim := HoraSistemaUtc + (dDesfaseSim / (24 * 60 * 60));
  oResultado := EvaluarReloj(dSistemaSim, dReferencia, iMargen, 'SIMULADO');
  Writeln('Reloj fiscal       : ', oResultado.Resumen);
  // Si esta desfasado, ExigirReloj lanza ERelojFiscalDesfasado y no se emite.
  ExigirReloj(oResultado, 'Registro de facturacion NO VERI*FACTU');
end;

// --- Programa --------------------------------------------------------------

procedure Ejecutar(const ARutaXml, ASalidaBase, ASerial, ATitular: string);
var
  oDoc:        IXMLDocument;
  oRaiz:       IXMLNode;
  oNodo:       IXMLNode;
  oBanda:      IXMLNode;
  oProductor:  IXMLNode;
  oEmisor:     IXMLNode;
  oCadenaNodo: IXMLNode;
  oSif:        TSistemaInformaticoSif;
  sSif:        string;
  oFactura:    TFacturaVerifactu;
  oAnterior:   TEslabonCadena;
  oRegistro:   TRegistroVerifactu;
  oLibro:      TLibroEventosNoVerifactu;
  oRegFac:     TRegistroFacturacionNoVerifactu;
  aRegistros:  TArray<TRegistroFacturacionNoVerifactu>;
  bFirmar:     Boolean;
  i:           Integer;
  sArchivoFac: string;
  sArchivoEvt: string;
begin
  if not FileExists(ARutaXml) then
    raise Exception.Create('No se encuentra el XML de facturas: ' + ARutaXml);
  bFirmar := (ASerial <> '') or (ATitular <> '');

  oDoc := LoadXMLDocument(ARutaXml);
  oRaiz := oDoc.DocumentElement;

  Writeln('====================================================');
  Writeln(' Registro de facturacion NO VERI*FACTU');
  if bFirmar then
    Writeln(' (firmado XAdES)')
  else
    Writeln(' (demo, sin firma)');
  Writeln('====================================================');

  // 1) Control del reloj fiscal: si falla, se lanza y no se emite nada.
  ComprobarReloj(oRaiz);

  // 2) Datos del productor (software) y del emisor (empresa).
  oProductor := oRaiz.ChildNodes.FindNode('Productor');
  oEmisor    := oRaiz.ChildNodes.FindNode('Emisor');

  oSif := Default(TSistemaInformaticoSif);
  oSif.NombreProductor   := Attr(oProductor, 'NombreRazon', 'Ejemplo');
  oSif.NifProductor      := Attr(oProductor, 'NIF', '99999999R');
  oSif.NombreSistema     := Attr(oProductor, 'NombreSistema', 'Ejemplo');
  oSif.IdSistema         := Attr(oProductor, 'IdSistema', 'EJ');
  oSif.Version           := Attr(oProductor, 'Version', '1.0.0');
  oSif.NumeroInstalacion := Attr(oProductor, 'NumeroInstalacion', '1');
  oSif.IndicadorMultiplesOT := 'N';
  oSif.NombreObligado    := Attr(oEmisor, 'NombreRazon', '');
  oSif.NifObligado       := Attr(oEmisor, 'NIF', '');

  // Bloque <SistemaInformatico> (con prefijo sum1) para el RegistroAlta.
  sSif := ConstruirSistemaInformatico(oSif.NombreProductor,
    oSif.NifProductor, oSif.NombreSistema, oSif.IdSistema, oSif.Version,
    oSif.NumeroInstalacion);

  // 3) Eslabon anterior de la cadena de facturacion (vacio = primer registro).
  oCadenaNodo := oRaiz.ChildNodes.FindNode('CadenaAnterior');
  oAnterior.Serie  := Attr(oCadenaNodo, 'Serie', '');
  oAnterior.Numero := Attr(oCadenaNodo, 'Numero', '');
  oAnterior.Fecha  := Attr(oCadenaNodo, 'Fecha', '');
  oAnterior.Huella := Trim(Attr(oCadenaNodo, 'Huella', ''));

  oLibro := TLibroEventosNoVerifactu.Create(oSif);
  try
    if bFirmar then
      oLibro.ConfigurarFirma(ASerial, ATitular);

    // Evento de arranque ("abrir programa").
    oLibro.Registrar(cEventoInicio, 'Abrir programa',
      'Arranque de la aplicacion');

    // 4) Una pasada por cada <Factura> del XML.
    SetLength(aRegistros, 0);
    for i := 0 to oRaiz.ChildNodes.Count - 1 do
    begin
      oNodo := oRaiz.ChildNodes[i];
      if not SameText(oNodo.NodeName, 'Factura') then
        Continue;

      oFactura := Default(TFacturaVerifactu);
      oFactura.Serie         := Attr(oNodo, 'Serie', '');
      oFactura.Numero        := Attr(oNodo, 'Numero', '');
      oFactura.Fecha         := ParsearFecha(Attr(oNodo, 'Fecha', ''));
      oFactura.Tipo          := Attr(oNodo, 'Tipo', 'NORMAL');
      oFactura.NifEmisor     := oSif.NifObligado;
      oFactura.NombreEmisor  := oSif.NombreObligado;
      oFactura.NifCliente    := Attr(oNodo, 'NifCliente', '');
      oFactura.NombreCliente := Attr(oNodo, 'NombreCliente', '');
      oFactura.DescripcionOperacion := Attr(oNodo, 'Descripcion', 'Venta');
      // Bandas de IVA (un <Banda> por tipo impositivo).
      oBanda := oNodo.ChildNodes.First;
      while oBanda <> nil do
      begin
        if SameText(oBanda.NodeName, 'Banda') then
          oFactura.AnadirBanda(
            ParsearImporte(Attr(oBanda, 'PorcentajeIva', '0')),
            ParsearImporte(Attr(oBanda, 'BaseImponible', '0')));
        oBanda := oBanda.NextSibling;
      end;

      // RegistroAlta + huella encadenada (lo mismo que en Veri*factu, pero
      // este registro NO se enviara a la AEAT).
      oRegistro := PrepararRegistroAlta(oFactura, oAnterior, sSif, False);

      oRegFac := Default(TRegistroFacturacionNoVerifactu);
      oRegFac.Serie         := oFactura.Serie;
      oRegFac.Numero        := oFactura.Numero;
      oRegFac.TipoOperacion := 'ALTA';
      oRegFac.Huella        := oRegistro.Huella;
      oRegFac.Xml           := EnvolverRegistroFacturacion(
        oRegistro.XmlRegistro, 'ALTA');
      oRegFac.XmlFirmado    := oRegFac.Xml;
      oRegFac.Firmado       := False;
      if bFirmar then
      begin
        // Firma XAdES del RegistroAlta (politica AGE). Si falla, sube la
        // excepcion y no se completa la emision.
        oRegFac.XmlFirmado := FirmarRegistroFacturacion(oRegistro.XmlRegistro,
          'ALTA', oRegistro.Huella, ASerial, ATitular,
          oRegFac.DatosCertificado, oRegFac.FirmaXades);
        oRegFac.Firmado := True;
      end;
      aRegistros := aRegistros + [oRegFac];

      // Evento "factura creada" para esta factura.
      oLibro.Registrar(cEventoOtros, 'Factura creada',
        'Registro NO VERI*FACTU', oFactura.Serie, oFactura.Numero);

      Writeln(Format('  Factura %-14s huella=%s...%s',
        [ComponerNumSerieFactura(oFactura.Serie, oFactura.Numero),
         Copy(oRegistro.Huella, 1, 12),
         IfThen(oRegFac.Firmado, '  (firmado)', '  (demo)')]));

      // Avanzamos la cadena: esta factura es el eslabon anterior de la
      // siguiente.
      oAnterior.Serie  := oFactura.Serie;
      oAnterior.Numero := oFactura.Numero;
      oAnterior.Fecha  := oFactura.FechaExpedicionTexto;
      oAnterior.Huella := oRegistro.Huella;
    end;

    if Length(aRegistros) = 0 then
      raise Exception.Create('El XML no contiene ninguna <Factura>.');

    // 5) Eventos de exportacion (se registran antes de volcar los XML).
    oLibro.Registrar(cEventoExportFact,
      'Exportacion del registro de facturacion');
    oLibro.Registrar(cEventoExportEventos,
      'Exportacion del registro de eventos');

    // 6) Volcado de los dos ficheros legales.
    sArchivoFac := ASalidaBase + '_facturacion.xml';
    sArchivoEvt := ASalidaBase + '_eventos.xml';
    TFile.WriteAllText(sArchivoFac,
      XmlExportacionFacturacion(aRegistros, '1.0.0', 'demo'), TEncoding.UTF8);
    TFile.WriteAllText(sArchivoEvt,
      oLibro.XmlExportacion('1.0.0', 'demo'), TEncoding.UTF8);

    Writeln('');
    Writeln('Facturas registradas: ', Length(aRegistros));
    Writeln('Eventos registrados : ', Length(oLibro.Eventos));
    Writeln('Registro facturacion: ', sArchivoFac);
    Writeln('Registro de eventos : ', sArchivoEvt);
  finally
    FreeAndNil(oLibro);
  end;
end;

var
  sRutaXml:    string;
  sSalidaBase: string;
begin
  try
    sRutaXml := ParamStr(1);
    if sRutaXml = '' then
      sRutaXml := 'facturas.xml';
    sSalidaBase := ParamStr(2);
    if sSalidaBase = '' then
      sSalidaBase := 'noverifactu';
    Ejecutar(sRutaXml, sSalidaBase, ParamStr(3), ParamStr(4));
  except
    on E: ERelojFiscalDesfasado do
    begin
      Writeln('=> DENEGADO (reloj fiscal): ', E.Message);
      Halt(3);
    end;
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
