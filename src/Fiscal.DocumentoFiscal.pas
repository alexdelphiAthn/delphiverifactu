{******************************************************************************}
{                                                                              }
{  Modulo:       Fiscal.DocumentoFiscal                                        }
{    Tipo:       Libreria Delphi                                               }
{   Autor:       Alejandro Laorden Hidalgo                                     }
{                                                                              }
{  SPDX-License-Identifier: MIT                                                }
{                                                                              }
{  Descripcion:                                                                }
{    Validacion local de NIF, NIE y CIF espanoles.                             }
{******************************************************************************}
unit Fiscal.DocumentoFiscal;

interface

type
  TTipoDocumentoFiscal = (tdfNIF, tdfNIE, tdfCIF, tdfDesconocido);

function LimpiarDocumentoFiscal(const ADocumento: string): string;
function DocumentoFiscalValido(const ADocumento: string): Boolean;
function DocumentoFiscalValidoConTipo(const ADocumento: string;
                                      out ATipo: TTipoDocumentoFiscal):
                                      Boolean;
function MensajeDocumentoFiscalInvalido(const ADocumento: string): string;
function PaisEsEspana(const ACodigoPais, ANombrePais: string): Boolean;

implementation

uses
  System.SysUtils;

const
  cLetrasNif = 'TRWAGMYFPDXBNJZSQVHLCKE';
  cLetrasCifOrganizacion = 'ABCDEFGHJNPQRSUVW';
  cLetrasCifControl = 'JABCDEFGHI';

function LimpiarDocumentoFiscal(const ADocumento: string): string;
begin
  Result := UpperCase(Trim(ADocumento));
  Result := StringReplace(Result, ' ', '', [rfReplaceAll]);
  Result := StringReplace(Result, '-', '', [rfReplaceAll]);
  Result := StringReplace(Result, '.', '', [rfReplaceAll]);
end;

function NormalizarTextoPais(const AValor: string): string;
begin
  Result := UpperCase(Trim(AValor));
end;

function PaisEsEspana(const ACodigoPais, ANombrePais: string): Boolean;
var
  sCodigo: string;
  sNombre: string;
begin
  sCodigo := NormalizarTextoPais(ACodigoPais);
  sNombre := NormalizarTextoPais(ANombrePais);
  Result := (sCodigo = '724') or (sCodigo = 'ES') or (sCodigo = 'ESP') or
            (Copy(sNombre, 1, 4) = 'ESPA') or (sNombre = 'SPAIN');
end;

function EsNumero(const AValor: string): Boolean;
var
  i: Integer;
begin
  Result := AValor <> '';
  i := 1;
  while (i <= Length(AValor)) and Result do
  begin
    if not CharInSet(AValor[i], ['0'..'9']) then
      Result := False;
    Inc(i);
  end;
end;

function LetraNif(ANumero: Integer): Char;
begin
  Result := cLetrasNif[(ANumero mod 23) + 1];
end;

function ValidarNifInterno(const ADocumento: string): Boolean;
var
  sDocumento: string;
  sNumero: string;
  iNumero: Integer;
begin
  Result := False;
  sDocumento := LimpiarDocumentoFiscal(ADocumento);
  if Length(sDocumento) = 9 then
  begin
    sNumero := Copy(sDocumento, 1, 8);
    if EsNumero(sNumero) and TryStrToInt(sNumero, iNumero) then
      Result := sDocumento[9] = LetraNif(iNumero);
  end;
end;

function ValidarNieInterno(const ADocumento: string): Boolean;
var
  sDocumento: string;
  sNumero: string;
  iNumero: Integer;
begin
  Result := False;
  sDocumento := LimpiarDocumentoFiscal(ADocumento);
  if (Length(sDocumento) = 9) and
     CharInSet(sDocumento[1], ['X', 'Y', 'Z']) and
     EsNumero(Copy(sDocumento, 2, 7)) and
     (Pos(sDocumento[9], cLetrasNif) > 0) then
  begin
    case sDocumento[1] of
      'X':
        sNumero := '0' + Copy(sDocumento, 2, 7);
      'Y':
        sNumero := '1' + Copy(sDocumento, 2, 7);
      'Z':
        sNumero := '2' + Copy(sDocumento, 2, 7);
    end;
    if TryStrToInt(sNumero, iNumero) then
      Result := sDocumento[9] = LetraNif(iNumero);
  end;
end;

function DigitoControlCif(const ACif: string): Char;
var
  i: Integer;
  iDigito: Integer;
  iSuma: Integer;
  iPares: Integer;
  iImpares: Integer;
  sNumero: string;
begin
  sNumero := Copy(ACif, 2, 7);
  iPares := 0;
  iImpares := 0;
  i := 2;
  while i <= 6 do
  begin
    if (i mod 2) = 0 then
      iPares := iPares + StrToInt(sNumero[i]);
    Inc(i);
  end;
  i := 1;
  while i <= 7 do
  begin
    if (i mod 2) = 1 then
    begin
      iDigito := StrToInt(sNumero[i]) * 2;
      iImpares := iImpares + (iDigito div 10) + (iDigito mod 10);
    end;
    Inc(i);
  end;
  iSuma := iPares + iImpares;
  iDigito := 10 - (iSuma mod 10);
  if iDigito = 10 then
    iDigito := 0;
  case ACif[1] of
    'G', 'K', 'L', 'M', 'N', 'P', 'Q', 'R', 'S', 'W':
      Result := cLetrasCifControl[iDigito + 1];
  else
    Result := Chr(Ord('0') + iDigito);
  end;
end;

function ValidarCifInterno(const ADocumento: string): Boolean;
var
  sDocumento: string;
begin
  Result := False;
  sDocumento := LimpiarDocumentoFiscal(ADocumento);
  if (Length(sDocumento) = 9) and
     (Pos(sDocumento[1], cLetrasCifOrganizacion) > 0) and
     EsNumero(Copy(sDocumento, 2, 7)) then
    Result := sDocumento[9] = DigitoControlCif(sDocumento);
end;

function DetectarTipoDocumentoFiscal(const ADocumento: string):
  TTipoDocumentoFiscal;
var
  sDocumento: string;
begin
  Result := tdfDesconocido;
  sDocumento := LimpiarDocumentoFiscal(ADocumento);
  if (Length(sDocumento) = 9) and CharInSet(sDocumento[1], ['X', 'Y', 'Z']) then
    Result := tdfNIE
  else if (Length(sDocumento) = 9) and
          CharInSet(sDocumento[1], ['0'..'9']) then
    Result := tdfNIF
  else if (Length(sDocumento) = 9) and
          (Pos(sDocumento[1], cLetrasCifOrganizacion) > 0) then
    Result := tdfCIF;
end;

function DocumentoFiscalValidoConTipo(const ADocumento: string;
                                      out ATipo: TTipoDocumentoFiscal):
                                      Boolean;
begin
  ATipo := DetectarTipoDocumentoFiscal(ADocumento);
  case ATipo of
    tdfNIF:
      Result := ValidarNifInterno(ADocumento);
    tdfNIE:
      Result := ValidarNieInterno(ADocumento);
    tdfCIF:
      Result := ValidarCifInterno(ADocumento);
  else
    Result := False;
  end;
end;

function DocumentoFiscalValido(const ADocumento: string): Boolean;
var
  oTipo: TTipoDocumentoFiscal;
begin
  Result := DocumentoFiscalValidoConTipo(ADocumento, oTipo);
end;

function MensajeDocumentoFiscalInvalido(const ADocumento: string): string;
var
  oTipo: TTipoDocumentoFiscal;
begin
  oTipo := DetectarTipoDocumentoFiscal(ADocumento);
  case oTipo of
    tdfNIF:
      Result := 'NIF invalido. Formato esperado: 12345678A';
    tdfNIE:
      Result := 'NIE invalido. Formato esperado: X1234567A';
    tdfCIF:
      Result := 'CIF invalido. Formato esperado: A12345674';
  else
    Result := 'NIF, NIE o CIF vacio o no reconocido: ' + ADocumento;
  end;
end;

end.
