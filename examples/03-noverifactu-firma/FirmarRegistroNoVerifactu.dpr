program FirmarRegistroNoVerifactu;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  Fiscal.Xades in '..\..\src\Fiscal.Xades.pas';

var
  oDatosCert: TXadesDatosCertificado;
  oOpciones: TXadesOpciones;
  sEntrada: string;
  sHuella: string;
  sSalida: string;
  sSerial: string;
  sTitular: string;
  sXml: string;
  sXmlFirmado: string;

begin
  try
    if ParamCount < 5 then
    begin
      Writeln('Uso: FirmarRegistroNoVerifactu registro.xml salida.xml ' +
        'huella serial titular');
      Halt(1);
    end;
    sEntrada := ParamStr(1);
    sSalida := ParamStr(2);
    sHuella := ParamStr(3);
    sSerial := ParamStr(4);
    sTitular := ParamStr(5);
    sXml := TFile.ReadAllText(sEntrada, TEncoding.UTF8);
    oOpciones := OpcionesXadesNoVerifactu('FZ-REGISTRO-' + sHuella);
    sXmlFirmado := FirmarXmlXadesEnveloped(sXml, sSerial, sTitular,
      oOpciones, oDatosCert);
    TFile.WriteAllText(sSalida, sXmlFirmado, TEncoding.UTF8);
    Writeln('Registro firmado: ' + sSalida);
    Writeln('Certificado: ' + oDatosCert.Titular);
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      Halt(2);
    end;
  end;
end.
