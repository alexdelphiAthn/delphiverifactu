{******************************************************************************}
{  EnviarDatosVerifactu - Ejemplo de uso de Fiscal.EnvioVerifactu              }
{                                                                              }
{  Lee los datos variables de un .ini (NIF productor, factura, eslabon         }
{  anterior de la cadena, entorno...), construye el registro de ALTA           }
{  Veri*factu, calcula su huella SHA-256, compone el QR y el sobre SOAP, y     }
{  opcionalmente lo remite a la AEAT.                                          }
{                                                                              }
{  Uso:  EnviarDatosVerifactu.exe [ruta_al_ini]                               }
{        Si no se pasa ruta, busca EnviarDatosVerifactu.ini junto al .exe.     }
{******************************************************************************}
program EnviarDatosVerifactu;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IniFiles,
  Fiscal.EnvioVerifactu in '..\..\src\Fiscal.EnvioVerifactu.pas';

// Fecha dd-mm-aaaa del .ini a TDateTime
function ParsearFecha(const ATexto: string): TDateTime;
var
  oFmt: TFormatSettings;
begin
  oFmt := TFormatSettings.Create;
  oFmt.DateSeparator   := '-';
  oFmt.ShortDateFormat := 'dd-mm-yyyy';
  Result := StrToDate(Trim(ATexto), oFmt);
end;

// Importe con punto decimal del .ini a Currency
function ParsearImporte(const ATexto: string): Currency;
var
  oFmt: TFormatSettings;
begin
  oFmt := TFormatSettings.Create;
  oFmt.DecimalSeparator  := '.';
  oFmt.ThousandSeparator := #0;
  Result := StrToCurr(Trim(ATexto), oFmt);
end;

procedure Ejecutar(const ARutaIni: string);
var
  oIni:       TMemIniFile;
  oFactura:   TFacturaVerifactu;
  oAnterior:  TEslabonCadena;
  oRegistro:  TRegistroVerifactu;
  sSif:       string;
  sEntorno:   string;
  sUrlEnvio:  string;
  bPro:       Boolean;
  iStatus:    Integer;
  sRespuesta: string;
begin
  if not FileExists(ARutaIni) then
    raise Exception.Create('No se encuentra el .ini: ' + ARutaIni);
  oIni := TMemIniFile.Create(ARutaIni);
  try
    // 1) SIF: identificacion del software productor
    sSif := ConstruirSistemaInformatico(
      oIni.ReadString('Productor', 'NombreRazon', ''),
      oIni.ReadString('Productor', 'NIF', ''),
      oIni.ReadString('Productor', 'NombreSistema', 'Ejemplo');
      oIni.ReadString('Productor', 'IdSistema', 'EJ'),
      oIni.ReadString('Productor', 'Version', '1.0.0'),
      oIni.ReadString('Productor', 'NumeroInstalacion', '1'));
    // 2) Factura (mapea columnas *_FAC de fza_facturas)
    oFactura := Default(TFacturaVerifactu);
    oFactura.NifEmisor    := oIni.ReadString('Emisor', 'NIF', '');
    oFactura.NombreEmisor := oIni.ReadString('Emisor', 'NombreRazon', '');
    oFactura.Serie  := oIni.ReadString('Factura', 'Serie', '');
    oFactura.Numero := oIni.ReadString('Factura', 'Numero', '');
    oFactura.Fecha  := ParsearFecha(oIni.ReadString('Factura', 'Fecha', ''));
    oFactura.Tipo   := oIni.ReadString('Factura', 'Tipo', 'NORMAL');
    oFactura.NifCliente    := oIni.ReadString('Factura', 'NifCliente', '');
    oFactura.NombreCliente := oIni.ReadString('Factura', 'NombreCliente', '');
    oFactura.DescripcionOperacion :=
      oIni.ReadString('Factura', 'Descripcion', 'Venta');
    oFactura.AnadirBanda(
      ParsearImporte(oIni.ReadString('Factura', 'PorcentajeIva', '0')),
      ParsearImporte(oIni.ReadString('Factura', 'BaseImponible', '0')));
    // 3) Eslabon anterior de la cadena (fza_verifactu_cadena). Si Huella
    // queda vacia, la libreria genera <PrimerRegistro>S</PrimerRegistro>.
    oAnterior.Serie  := oIni.ReadString('CadenaAnterior', 'Serie', '');
    oAnterior.Numero := oIni.ReadString('CadenaAnterior', 'Numero', '');
    oAnterior.Fecha  := oIni.ReadString('CadenaAnterior', 'Fecha', '');
    oAnterior.Huella := Trim(oIni.ReadString('CadenaAnterior', 'Huella', ''));
    // 4) Entorno y construccion del registro de alta
    sEntorno := UpperCase(Trim(oIni.ReadString('Envio', 'Entorno', 'PRE')));
    bPro := sEntorno = 'PRO';
    oRegistro := PrepararRegistroAlta(oFactura, oAnterior, sSif, bPro);
    Writeln('====================================================');
    Writeln(' Veri*factu - Registro de ALTA  [', sEntorno, ']');
    Writeln('====================================================');
    Writeln('NumSerieFactura : ', oRegistro.NumSerieFactura);
    Writeln('Tipo factura    : ', oFactura.TipoVerifactu);
    Writeln('Cuota total     : ', FormatearImporte(oRegistro.CuotaTotal));
    Writeln('Importe total   : ', FormatearImporte(oRegistro.ImporteTotal));
    Writeln('Generado        : ', oRegistro.FechaHoraHusoGen);
    Writeln('Huella SHA-256  : ', oRegistro.Huella);
    Writeln('');
    Writeln('--- URL de cotejo del QR ---');
    Writeln(oRegistro.UrlQR);
    Writeln('');
    Writeln('--- RegistroAlta (XML) ---');
    Writeln(oRegistro.XmlRegistro);
    Writeln('');
    Writeln('--- Sobre SOAP ---');
    Writeln(oRegistro.XmlSoap);
    // 5) Envio real opcional (requiere certificado + NIF dado de alta)
    if oIni.ReadInteger('Envio', 'EnviarReal', 0) = 1 then
    begin
      if bPro then
        sUrlEnvio := cVerifactuUrlEnvioPro
      else
        sUrlEnvio := cVerifactuUrlEnvioPre;
      Writeln('');
      Writeln('Enviando a la AEAT...');
      if EnviarSoapAeat(sUrlEnvio, oRegistro.XmlSoap,
                        oIni.ReadString('Emisor', 'SerieCertificado', ''),
                        oIni.ReadString('Emisor', 'TitularCertificado', ''),
                        iStatus, sRespuesta) then
        Writeln('Respuesta [HTTP ', iStatus, ']  EstadoEnvio = ',
                ExtraerEtiqueta(sRespuesta, 'EstadoEnvio'))
      else
        Writeln('Fallo de envio [HTTP ', iStatus, ']');
      Writeln(sRespuesta);
    end
    else
      Writeln('(Envio desactivado: [Envio] EnviarReal=0. Solo construido.)');
  finally
    FreeAndNil(oIni);
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