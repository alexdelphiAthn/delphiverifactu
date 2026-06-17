{******************************************************************************}
{  ValidarDocumentoFiscal - Ejemplo                                            }
{                                                                              }
{  Autor:  Alejandro Laorden Hidalgo                                           }
{  Email:  alejandro.laorden@protonmail.com                                    }
{******************************************************************************}

program ValidarDocumentoFiscal;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Fiscal.DocumentoFiscal in '..\..\src\Fiscal.DocumentoFiscal.pas';

function TipoDocumentoTexto(ATipo: TTipoDocumentoFiscal): string;
begin
  case ATipo of
    tdfNIF:
      Result := 'NIF';
    tdfNIE:
      Result := 'NIE';
    tdfCIF:
      Result := 'CIF';
  else
    Result := 'DESCONOCIDO';
  end;
end;

var
  i: Integer;
  oTipo: TTipoDocumentoFiscal;
  sDocumento: string;

begin
  if ParamCount = 0 then
  begin
    Writeln('Uso: ValidarDocumentoFiscal NIF [NIF...]');
    Halt(1);
  end;
  for i := 1 to ParamCount do
  begin
    sDocumento := ParamStr(i);
    if DocumentoFiscalValidoConTipo(sDocumento, oTipo) then
      Writeln(sDocumento + ': valido (' + TipoDocumentoTexto(oTipo) + ')')
    else
      Writeln(sDocumento + ': ' +
        MensajeDocumentoFiscalInvalido(sDocumento));
  end;
end.
