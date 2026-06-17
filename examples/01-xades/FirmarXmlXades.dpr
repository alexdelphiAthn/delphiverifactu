{******************************************************************************}
{  FirmarXmlXades - Ejemplo                                                    }
{                                                                              }
{  Autor:  Alejandro Laorden Hidalgo                                           }
{  Email:  alejandro.laorden@protonmail.com                                    }
{******************************************************************************}

program FirmarXmlXades;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  Fiscal.Xades in '..\..\src\Fiscal.Xades.pas';

var
  oDatosCert: TXadesDatosCertificado;
  oOpciones: TXadesOpciones;
  sEntrada: string;
  sSalida: string;
  sSerial: string;
  sTitular: string;
  sXml: string;
  sXmlFirmado: string;

begin
  try
    if ParamCount < 4 then
    begin
      Writeln('Uso: FirmarXmlXades entrada.xml salida.xsig serial titular');
      Halt(1);
    end;
    sEntrada := ParamStr(1);
    sSalida := ParamStr(2);
    sSerial := ParamStr(3);
    sTitular := ParamStr(4);
    sXml := TFile.ReadAllText(sEntrada, TEncoding.UTF8);
    oOpciones := OpcionesXadesFacturae('DEMO-XADES');
    oOpciones.RolFirmante := 'emisor';
    sXmlFirmado := FirmarXmlXadesEnveloped(sXml, sSerial, sTitular,
      oOpciones, oDatosCert);
    TFile.WriteAllText(sSalida, sXmlFirmado, TEncoding.UTF8);
    Writeln('XML firmado: ' + sSalida);
    Writeln('Certificado: ' + oDatosCert.Titular);
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      Halt(2);
    end;
  end;
end.
