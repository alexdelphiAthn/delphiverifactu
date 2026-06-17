{******************************************************************************}
{                                                                              }
{  Modulo:       Fiscal.Xades                                                  }
{    Tipo:       Libreria Delphi                                               }
{   Autor:       Alejandro Laorden Hidalgo                                     }
{                                                                              }
{  SPDX-License-Identifier: MIT                                                }
{                                                                              }
{  Descripcion:                                                                }
{    Firma XAdES Enveloped con certificados del almacen de Windows.            }
{******************************************************************************}
unit Fiscal.Xades;

interface

uses
  System.SysUtils;

type
  EXadesError = class(Exception);

  TXadesTipoPolitica = (xtpNinguna, xtpFacturae, xtpExplicita);

  TXadesDatosCertificado = record
    NumeroSerie:       string;
    Titular:           string;
    HuellaSha1:        string;
    CertificadoBase64: string;
  end;

  TXadesOpciones = record
    IdFirma:                  string;
    IdObjeto:                 string;
    IdKeyInfo:                string;
    IdSignedProperties:       string;
    IdReferenciaDocumento:    string;
    IdNodoFirmado:            string;
    UriDocumentoVacia:        Boolean;
    IncluirReferenciaKeyInfo: Boolean;
    FirmaSilenciosa:          Boolean;
    EspacioNombresXades:      string;
    TipoSignedProperties:     string;
    Politica:                 TXadesTipoPolitica;
    PoliticaIdentificador:    string;
    PoliticaDescripcion:      string;
    PoliticaUrl:              string;
    PoliticaHashBase64:       string;
    PoliticaDigestMethod:     string;
    AlgoritmoCanonicalizacion: string;
    IncluirTransformCanonicoDocumento: Boolean;
    RolFirmante:              string;
    NombreNodoInsercionFirma: string;
    ObjetoDescripcion:        string;
    ObjetoIdentificador:      string;
    ObjetoEncoding:           string;
  end;

function OpcionesXadesBase(const APrefijoId: string): TXadesOpciones;
function OpcionesXadesFacturae(const APrefijoId: string): TXadesOpciones;
function OpcionesXadesNoVerifactu(const APrefijoId: string): TXadesOpciones;
function FirmarXmlXadesEnveloped(const AXml: string;
                                  const ASerialCert, ATitularCert: string;
                                  const AOpciones: TXadesOpciones;
                                  out ADatosCert: TXadesDatosCertificado):
                                  string;
function NormalizarSerieCertificadoXades(const AValor: string): string;

implementation

uses
  System.Classes, System.DateUtils, System.Hash, System.NetEncoding,
  System.StrUtils, System.TimeSpan, Winapi.Windows;

const
  cCrypt32 = 'crypt32.dll';
  cAdvApi32 = 'advapi32.dll';
  cNCrypt = 'ncrypt.dll';
  cXmlDsigNs = 'http://www.w3.org/2000/09/xmldsig#';
  cXadesNs122 = 'http://uri.etsi.org/01903/v1.2.2#';
  cXadesNs132 = 'http://uri.etsi.org/01903/v1.3.2#';
  cXadesSignedProperties122 =
    'http://uri.etsi.org/01903/v1.2.2#SignedProperties';
  cXadesSignedPropertiesFacturae =
    'http://uri.etsi.org/01903#SignedProperties';
  cAlgC14n = 'http://www.w3.org/TR/2001/REC-xml-c14n-20010315';
  cAlgExcC14n = 'http://www.w3.org/2001/10/xml-exc-c14n#';
  cAlgEnveloped = 'http://www.w3.org/2000/09/xmldsig#enveloped-signature';
  cAlgRsaSha256 = 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256';
  cAlgSha1 = 'http://www.w3.org/2000/09/xmldsig#sha1';
  cAlgSha256 = 'http://www.w3.org/2001/04/xmlenc#sha256';
  cFacturaePoliticaId =
    'http://www.facturae.es/politica_de_firma_formato_facturae/' +
    'politica_de_firma_formato_facturae_v3_1.pdf';
  cFacturaePoliticaDescripcion =
    'Politica de firma electronica para facturacion electronica con ' +
    'formato Facturae';
  cFacturaePoliticaHashSha1 = 'Ohixl6upD6av8N7pEvDABhEL6hM=';
  cAeatPoliticaId = 'urn:oid:2.16.724.1.3.1.1.2.1.9';
  cAeatPoliticaUrl =
    'https://sede.administracion.gob.es/politica_de_firma_anexo_1.pdf';
  cAeatPoliticaHashSha1 = 'G7roucf600+f03r/o0bAOQ6WAs0=';
  cObjetoXmlOid = 'urn:oid:1.2.840.10003.5.109.10';
  cCertStorePersonal = 'MY';
  X509_ASN_ENCODING = $00000001;
  PKCS_7_ASN_ENCODING = $00010000;
  CERT_NAME_SIMPLE_DISPLAY_TYPE = 4;
  CERT_X500_NAME_STR = 3;
  CERT_NCRYPT_KEY_SPEC = $FFFFFFFF;
  CRYPT_ACQUIRE_COMPARE_KEY_FLAG = $00000004;
  CRYPT_ACQUIRE_SILENT_FLAG = $00000040;
  CRYPT_ACQUIRE_ALLOW_NCRYPT_KEY_FLAG = $00010000;
  CRYPT_ACQUIRE_PREFER_NCRYPT_KEY_FLAG = $00020000;
  CRYPT_VERIFYCONTEXT = $F0000000;
  PROV_RSA_AES = 24;
  HP_HASHVAL = $0002;
  CALG_SHA1 = $00008004;
  CALG_SHA_256 = $0000800C;
  NTE_BAD_ALGID = $80090008;
  NCRYPT_PAD_PKCS1_FLAG = $00000002;
  ERROR_SUCCESS = 0;

type
  TXadesCertNameBlob = record
    cbData: DWORD;
    pbData: PByte;
  end;
  PXadesCertNameBlob = ^TXadesCertNameBlob;

  TXadesCryptBitBlob = record
    cbData: DWORD;
    pbData: PByte;
    cUnusedBits: DWORD;
  end;

  TXadesCryptAlgorithmIdentifier = record
    pszObjId: PAnsiChar;
    Parameters: TXadesCertNameBlob;
  end;

  TXadesCertPublicKeyInfo = record
    Algorithm: TXadesCryptAlgorithmIdentifier;
    PublicKey: TXadesCryptBitBlob;
  end;

  TXadesCertExtension = record
    pszObjId: PAnsiChar;
    fCritical: BOOL;
    Value: TXadesCertNameBlob;
  end;
  PXadesCertExtension = ^TXadesCertExtension;

  TXadesCertInfo = record
    dwVersion: DWORD;
    SerialNumber: TXadesCertNameBlob;
    SignatureAlgorithm: TXadesCryptAlgorithmIdentifier;
    Issuer: TXadesCertNameBlob;
    NotBefore: TFileTime;
    NotAfter: TFileTime;
    Subject: TXadesCertNameBlob;
    SubjectPublicKeyInfo: TXadesCertPublicKeyInfo;
    IssuerUniqueId: TXadesCryptBitBlob;
    SubjectUniqueId: TXadesCryptBitBlob;
    cExtension: DWORD;
    rgExtension: PXadesCertExtension;
  end;
  PXadesCertInfo = ^TXadesCertInfo;

  TXadesCertContext = record
    dwCertEncodingType: DWORD;
    pbCertEncoded: PByte;
    cbCertEncoded: DWORD;
    pCertInfo: PXadesCertInfo;
    hCertStore: THandle;
  end;
  PXadesCertContext = ^TXadesCertContext;

  TBcryptPkcs1PaddingInfo = record
    pszAlgId: PWideChar;
  end;
  PBcryptPkcs1PaddingInfo = ^TBcryptPkcs1PaddingInfo;

function CertOpenSystemStoreW(hProv: ULONG_PTR;
                              szSubsystemProtocol: PWideChar): THandle;
                              stdcall; external cCrypt32;
function CertCloseStore(hCertStore: THandle;
                        dwFlags: DWORD): BOOL;
                        stdcall; external cCrypt32;
function CertEnumCertificatesInStore(hCertStore: THandle;
                                     pPrevCertContext: PXadesCertContext):
                                     PXadesCertContext;
                                     stdcall; external cCrypt32;
function CertDuplicateCertificateContext(pCertContext: PXadesCertContext):
                                         PXadesCertContext;
                                         stdcall; external cCrypt32;
function CertFreeCertificateContext(pCertContext: PXadesCertContext): BOOL;
                                    stdcall; external cCrypt32;
function CertGetNameStringW(pCertContext: PXadesCertContext;
                            dwType, dwFlags: DWORD;
                            pvTypePara: Pointer;
                            pszNameString: PWideChar;
                            cchNameString: DWORD): DWORD;
                            stdcall; external cCrypt32;
function CertNameToStrW(dwCertEncodingType: DWORD;
                        pName: PXadesCertNameBlob;
                        dwStrType: DWORD;
                        psz: PWideChar;
                        csz: DWORD): DWORD;
                        stdcall; external cCrypt32;
function CryptAcquireCertificatePrivateKey(pCert: PXadesCertContext;
  dwFlags: DWORD; pvReserved: Pointer; var phKey: ULONG_PTR;
  var pdwKeySpec: DWORD; var pfCallerFree: BOOL): BOOL;
  stdcall; external cCrypt32;
function CryptAcquireContextW(var phProv: ULONG_PTR; pszContainer: PWideChar;
                              pszProvider: PWideChar; dwProvType: DWORD;
                              dwFlags: DWORD): BOOL;
                              stdcall; external cAdvApi32;
function CryptCreateHash(hProv: ULONG_PTR; Algid: DWORD; hKey: ULONG_PTR;
                         dwFlags: DWORD; var phHash: ULONG_PTR): BOOL;
                         stdcall; external cAdvApi32;
function CryptHashData(hHash: ULONG_PTR; pbData: PByte; dwDataLen: DWORD;
                       dwFlags: DWORD): BOOL;
                       stdcall; external cAdvApi32;
function CryptGetHashParam(hHash: ULONG_PTR; dwParam: DWORD; pbData: PByte;
                           var pdwDataLen: DWORD; dwFlags: DWORD): BOOL;
                           stdcall; external cAdvApi32;
function CryptSignHashW(hHash: ULONG_PTR; dwKeySpec: DWORD;
                        szDescription: PWideChar; dwFlags: DWORD;
                        pbSignature: PByte; var pdwSigLen: DWORD): BOOL;
                        stdcall; external cAdvApi32;
function CryptDestroyHash(hHash: ULONG_PTR): BOOL;
                         stdcall; external cAdvApi32;
function CryptReleaseContext(hProv: ULONG_PTR; dwFlags: DWORD): BOOL;
                             stdcall; external cAdvApi32;
function NCryptSignHash(hKey: ULONG_PTR;
                        pPaddingInfo: PBcryptPkcs1PaddingInfo;
                        pbHashValue: PByte; cbHashValue: DWORD;
                        pbSignature: PByte; cbSignature: DWORD;
                        var pcbResult: DWORD; dwFlags: DWORD): Integer;
                        stdcall; external cNCrypt;
function NCryptFreeObject(hObject: ULONG_PTR): Integer;
                          stdcall; external cNCrypt;

function EscaparXml(const AValor: string): string;
begin
  Result := StringReplace(AValor, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, '''', '&apos;', [rfReplaceAll]);
end;

function NormalizarSerieCertificadoXades(const AValor: string): string;
begin
  Result := UpperCase(Trim(AValor));
  Result := StringReplace(Result, ' ', '', [rfReplaceAll]);
  Result := StringReplace(Result, ':', '', [rfReplaceAll]);
  Result := StringReplace(Result, '-', '', [rfReplaceAll]);
end;

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

function IdSeguro(const AValor, ADefecto: string): string;
var
  cActual: Char;
begin
  Result := '';
  for cActual in Trim(AValor) do
  begin
    if ((cActual >= 'A') and (cActual <= 'Z')) or
       ((cActual >= 'a') and (cActual <= 'z')) or
       ((cActual >= '0') and (cActual <= '9')) or
       (cActual = '_') or (cActual = '-') or (cActual = '.') then
      Result := Result + cActual
    else
      Result := Result + '-';
  end;
  if Result = '' then
    Result := ADefecto;
  if (Result[1] >= '0') and (Result[1] <= '9') then
    Result := 'FZ-' + Result;
end;

function OpcionesXadesBase(const APrefijoId: string): TXadesOpciones;
var
  sPrefijo: string;
begin
  sPrefijo := IdSeguro(APrefijoId, 'FZ-XADES');
  Result.IdFirma := sPrefijo + '-Signature';
  Result.IdObjeto := sPrefijo + '-Object';
  Result.IdKeyInfo := sPrefijo + '-KeyInfo';
  Result.IdSignedProperties := sPrefijo + '-SignedProperties';
  Result.IdReferenciaDocumento := sPrefijo + '-Reference-Documento';
  Result.IdNodoFirmado := sPrefijo + '-Documento';
  Result.UriDocumentoVacia := False;
  Result.IncluirReferenciaKeyInfo := True;
  Result.FirmaSilenciosa := False;
  Result.EspacioNombresXades := cXadesNs122;
  Result.TipoSignedProperties := cXadesSignedProperties122;
  Result.Politica := xtpNinguna;
  Result.PoliticaIdentificador := '';
  Result.PoliticaDescripcion := '';
  Result.PoliticaUrl := '';
  Result.PoliticaHashBase64 := '';
  Result.PoliticaDigestMethod := cAlgSha256;
  Result.AlgoritmoCanonicalizacion := cAlgExcC14n;
  Result.IncluirTransformCanonicoDocumento := True;
  Result.RolFirmante := '';
  Result.NombreNodoInsercionFirma := '';
  Result.ObjetoDescripcion := 'Factura electronica';
  Result.ObjetoIdentificador := '';
  Result.ObjetoEncoding := '';
end;

function OpcionesXadesFacturae(const APrefijoId: string): TXadesOpciones;
begin
  Result := OpcionesXadesBase(APrefijoId);
  Result.UriDocumentoVacia := True;
  Result.IdNodoFirmado := '';
  Result.EspacioNombresXades := cXadesNs132;
  Result.TipoSignedProperties := cXadesSignedPropertiesFacturae;
  Result.Politica := xtpFacturae;
  Result.PoliticaIdentificador := cFacturaePoliticaId;
  Result.PoliticaDescripcion := cFacturaePoliticaDescripcion;
  Result.PoliticaHashBase64 := cFacturaePoliticaHashSha1;
  Result.PoliticaDigestMethod := cAlgSha1;
  Result.RolFirmante := 'emisor';
end;

function OpcionesXadesNoVerifactu(const APrefijoId: string): TXadesOpciones;
begin
  Result := OpcionesXadesBase(APrefijoId);
  Result.UriDocumentoVacia := True;
  Result.IdNodoFirmado := '';
  Result.IncluirReferenciaKeyInfo := False;
  Result.EspacioNombresXades := cXadesNs132;
  Result.TipoSignedProperties := cXadesSignedPropertiesFacturae;
  Result.Politica := xtpExplicita;
  Result.PoliticaIdentificador := cAeatPoliticaId;
  Result.PoliticaDescripcion := '';
  Result.PoliticaUrl := cAeatPoliticaUrl;
  Result.PoliticaHashBase64 := cAeatPoliticaHashSha1;
  Result.PoliticaDigestMethod := cAlgSha1;
  Result.AlgoritmoCanonicalizacion := cAlgC14n;
  Result.IncluirTransformCanonicoDocumento := False;
  Result.ObjetoDescripcion := '';
  Result.ObjetoIdentificador := cObjetoXmlOid;
  Result.ObjetoEncoding := 'UTF-8';
end;

function AsegurarOpciones(const AOpciones: TXadesOpciones):
  TXadesOpciones;
var
  sPrefijo: string;
begin
  Result := AOpciones;
  sPrefijo := 'FZ-XADES';
  if Result.IdFirma = '' then
    Result.IdFirma := sPrefijo + '-Signature';
  if Result.IdObjeto = '' then
    Result.IdObjeto := sPrefijo + '-Object';
  if Result.IdKeyInfo = '' then
    Result.IdKeyInfo := sPrefijo + '-KeyInfo';
  if Result.IdSignedProperties = '' then
    Result.IdSignedProperties := sPrefijo + '-SignedProperties';
  if Result.IdReferenciaDocumento = '' then
    Result.IdReferenciaDocumento := sPrefijo + '-Reference-Documento';
  if (not Result.UriDocumentoVacia) and (Result.IdNodoFirmado = '') then
    Result.IdNodoFirmado := sPrefijo + '-Documento';
  if Result.EspacioNombresXades = '' then
    Result.EspacioNombresXades := cXadesNs122;
  if Result.TipoSignedProperties = '' then
    Result.TipoSignedProperties := cXadesSignedProperties122;
  if Result.PoliticaDigestMethod = '' then
    Result.PoliticaDigestMethod := cAlgSha256;
  if Result.AlgoritmoCanonicalizacion = '' then
    Result.AlgoritmoCanonicalizacion := cAlgExcC14n;
  if (Result.ObjetoDescripcion = '') and
     (Result.ObjetoIdentificador = '') and
     (Result.ObjetoEncoding = '') then
    Result.ObjetoDescripcion := 'Factura electronica';
end;

function BytesUtf8(const AValor: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(AValor);
end;

function Base64Bytes(const ABytes: TBytes): string;
begin
  Result := TNetEncoding.Base64.EncodeBytesToString(ABytes);
  Result := StringReplace(Result, #13, '', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '', [rfReplaceAll]);
end;

function HashBytesCrypto(AAlgId: DWORD; const ABytes: TBytes): TBytes;
var
  hProv: ULONG_PTR;
  hHash: ULONG_PTR;
  dwTam: DWORD;
begin
  hProv := 0;
  hHash := 0;
  if not CryptAcquireContextW(hProv, nil, nil, PROV_RSA_AES,
                              CRYPT_VERIFYCONTEXT) then
    raise EXadesError.Create('No se pudo abrir el proveedor criptografico.');
  try
    if not CryptCreateHash(hProv, AAlgId, 0, 0, hHash) then
      raise EXadesError.Create('No se pudo crear el hash criptografico.');
    try
      if Length(ABytes) > 0 then
        if not CryptHashData(hHash, PByte(@ABytes[0]),
                             DWORD(Length(ABytes)), 0) then
          raise EXadesError.Create('No se pudo calcular el hash.');
      dwTam := 0;
      if not CryptGetHashParam(hHash, HP_HASHVAL, nil, dwTam, 0) then
        raise EXadesError.Create('No se pudo obtener el tamano del hash.');
      SetLength(Result, dwTam);
      if dwTam > 0 then
        if not CryptGetHashParam(hHash, HP_HASHVAL, PByte(@Result[0]),
                                 dwTam, 0) then
          raise EXadesError.Create('No se pudo obtener el valor del hash.');
    finally
      CryptDestroyHash(hHash);
    end;
  finally
    CryptReleaseContext(hProv, 0);
  end;
end;

function Sha1Bytes(const ABytes: TBytes): TBytes;
begin
  Result := HashBytesCrypto(CALG_SHA1, ABytes);
end;

function Sha256Bytes(const ABytes: TBytes): TBytes;
begin
  Result := HashBytesCrypto(CALG_SHA_256, ABytes);
end;

function DigestSha256Base64(const AXmlCanonico: string): string;
begin
  Result := Base64Bytes(Sha256Bytes(BytesUtf8(AXmlCanonico)));
end;

function AtributoXmlNsDs: string;
begin
  Result := 'xmlns:ds="' + cXmlDsigNs + '"';
end;

function NodoDsVacioCanonico(const ANombre, AAtributos: string): string;
begin
  Result := '<ds:' + ANombre;
  if AAtributos <> '' then
    Result := Result + ' ' + AAtributos;
  Result := Result + '></ds:' + ANombre + '>';
end;

function BytesToHexMayus(const ABytes: TBytes): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to Length(ABytes) - 1 do
    Result := Result + IntToHex(ABytes[i], 2);
end;

function PunteroBytes(const ABytes: TBytes): PByte;
begin
  if Length(ABytes) > 0 then
    Result := @ABytes[0]
  else
    Result := nil;
end;

function CodigoErrorHex(ACodigo: DWORD): string;
begin
  Result := '0x' + IntToHex(ACodigo, 8);
end;

function MensajeErrorCripto(const AOperacion: string; ACodigo: DWORD):
  string;
begin
  Result := AOperacion + '. Codigo: ' + CodigoErrorHex(ACodigo) + '. ' +
    SysErrorMessage(ACodigo);
end;

procedure LanzarErrorCripto(const AOperacion: string);
var
  dwError: DWORD;
begin
  dwError := GetLastError;
  raise EXadesError.Create(MensajeErrorCripto(AOperacion, dwError));
end;

procedure LanzarErrorFirmaCapiSha256(const AOperacion: string);
var
  dwError: DWORD;
  sMensaje: string;
begin
  dwError := GetLastError;
  if dwError = NTE_BAD_ALGID then
  begin
    sMensaje :=
      'El proveedor criptografico del certificado no admite SHA-256 para ' +
      'firma RSA. No se puede generar XAdES rsa-sha256 con ese certificado ' +
      'tal como esta instalado. Reinstala o importa el certificado con un ' +
      'proveedor compatible con SHA-256, como Microsoft Enhanced RSA and ' +
      'AES Cryptographic Provider o Microsoft Software Key Storage ' +
      'Provider. ' + MensajeErrorCripto(AOperacion, dwError);
    raise EXadesError.Create(sMensaje);
  end
  else
    raise EXadesError.Create(MensajeErrorCripto(AOperacion, dwError));
end;

procedure InvertirBytes(var ABytes: TBytes);
var
  iIzq: Integer;
  iDer: Integer;
  iTmp: Byte;
begin
  iIzq := 0;
  iDer := Length(ABytes) - 1;
  while iIzq < iDer do
  begin
    iTmp := ABytes[iIzq];
    ABytes[iIzq] := ABytes[iDer];
    ABytes[iDer] := iTmp;
    Inc(iIzq);
    Dec(iDer);
  end;
end;

function CertificadoDerBytes(ACert: PXadesCertContext): TBytes;
begin
  SetLength(Result, ACert^.cbCertEncoded);
  if ACert^.cbCertEncoded > 0 then
    Move(ACert^.pbCertEncoded^, Result[0], ACert^.cbCertEncoded);
end;

function SerieCertificadoHexLE(ACert: PXadesCertContext): string;
var
  i: DWORD;
begin
  Result := '';
  for i := 0 to ACert^.pCertInfo^.SerialNumber.cbData - 1 do
    Result := Result +
      IntToHex(PByte(ACert^.pCertInfo^.SerialNumber.pbData)[i], 2);
end;

procedure MultiplicarDecimal(var AValor: string; AFactor: Integer);
var
  i: Integer;
  iAcarreo: Integer;
  iDigito: Integer;
  iValor: Integer;
  sNuevo: string;
begin
  iAcarreo := 0;
  sNuevo := '';
  for i := Length(AValor) downto 1 do
  begin
    iDigito := Ord(AValor[i]) - Ord('0');
    iValor := (iDigito * AFactor) + iAcarreo;
    sNuevo := Chr(Ord('0') + (iValor mod 10)) + sNuevo;
    iAcarreo := iValor div 10;
  end;
  while iAcarreo > 0 do
  begin
    sNuevo := Chr(Ord('0') + (iAcarreo mod 10)) + sNuevo;
    iAcarreo := iAcarreo div 10;
  end;
  AValor := sNuevo;
end;

procedure SumarDecimal(var AValor: string; AIncremento: Integer);
var
  i: Integer;
  iAcarreo: Integer;
  iDigito: Integer;
  iValor: Integer;
  sNuevo: string;
begin
  i := Length(AValor);
  iAcarreo := AIncremento;
  sNuevo := AValor;
  while (i > 0) and (iAcarreo > 0) do
  begin
    iDigito := Ord(sNuevo[i]) - Ord('0');
    iValor := iDigito + (iAcarreo mod 10);
    sNuevo[i] := Chr(Ord('0') + (iValor mod 10));
    iAcarreo := (iAcarreo div 10) + (iValor div 10);
    Dec(i);
  end;
  while iAcarreo > 0 do
  begin
    sNuevo := Chr(Ord('0') + (iAcarreo mod 10)) + sNuevo;
    iAcarreo := iAcarreo div 10;
  end;
  AValor := sNuevo;
end;

function SerieCertificadoDecimal(ACert: PXadesCertContext): string;
var
  i: Integer;
  iByte: Byte;
begin
  Result := '0';
  i := Integer(ACert^.pCertInfo^.SerialNumber.cbData) - 1;
  while i >= 0 do
  begin
    iByte := PByte(ACert^.pCertInfo^.SerialNumber.pbData)[i];
    MultiplicarDecimal(Result, 256);
    SumarDecimal(Result, iByte);
    Dec(i);
  end;
end;

function NombreSimpleCertificado(ACert: PXadesCertContext): string;
var
  iLen: DWORD;
begin
  Result := '';
  iLen := CertGetNameStringW(ACert, CERT_NAME_SIMPLE_DISPLAY_TYPE, 0,
                             nil, nil, 0);
  if iLen > 1 then
  begin
    SetLength(Result, iLen - 1);
    CertGetNameStringW(ACert, CERT_NAME_SIMPLE_DISPLAY_TYPE, 0, nil,
                       PWideChar(Result), iLen);
  end;
end;

function NombreX500(const ABlob: TXadesCertNameBlob): string;
var
  iLen: DWORD;
begin
  Result := '';
  iLen := CertNameToStrW(X509_ASN_ENCODING or PKCS_7_ASN_ENCODING,
                         @ABlob, CERT_X500_NAME_STR, nil, 0);
  if iLen > 1 then
  begin
    SetLength(Result, iLen - 1);
    CertNameToStrW(X509_ASN_ENCODING or PKCS_7_ASN_ENCODING,
                   @ABlob, CERT_X500_NAME_STR, PWideChar(Result), iLen);
  end;
end;

function CertificadoVigente(ACert: PXadesCertContext): Boolean;
var
  oAhora: TFileTime;
begin
  GetSystemTimeAsFileTime(oAhora);
  Result := (CompareFileTime(oAhora, ACert^.pCertInfo^.NotBefore) >= 0) and
            (CompareFileTime(oAhora, ACert^.pCertInfo^.NotAfter) <= 0);
end;

function FechaCertificadoTexto(const AFecha: TFileTime): string;
var
  oLocal: TFileTime;
  oSistema: TSystemTime;
  dFecha: TDateTime;
begin
  Result := '';
  if FileTimeToLocalFileTime(AFecha, oLocal) then
  begin
    if FileTimeToSystemTime(oLocal, oSistema) then
    begin
      dFecha := SystemTimeToDateTime(oSistema);
      Result := FormatDateTime('dd/mm/yyyy hh:nn:ss', dFecha);
    end;
  end;
end;

function MensajeCertificadoNoVigente(ACert: PXadesCertContext): string;
var
  oAhora: TFileTime;
  sEstado: string;
  sDesde: string;
  sHasta: string;
begin
  GetSystemTimeAsFileTime(oAhora);
  if CompareFileTime(oAhora, ACert^.pCertInfo^.NotBefore) < 0 then
    sEstado := 'todavia no es valido'
  else
    sEstado := 'esta caducado';
  sDesde := FechaCertificadoTexto(ACert^.pCertInfo^.NotBefore);
  sHasta := FechaCertificadoTexto(ACert^.pCertInfo^.NotAfter);
  Result := 'El certificado configurado ' + sEstado + '. Vigencia: ' +
            sDesde + ' - ' + sHasta + '. Seleccione un certificado vigente ' +
            'en la ficha de empresa o desactive la firma con certificado ' +
            'para seguir usando SHA-256.';
end;

function CertificadoCoincide(ACert: PXadesCertContext;
                             const ASerial, ATitular: string): Boolean;
var
  sBuscada: string;
  sSerie: string;
  sTitular: string;
begin
  Result := False;
  sBuscada := NormalizarSerieCertificadoXades(ASerial);
  sSerie := NormalizarSerieCertificadoXades(SerieCertificadoHexLE(ACert));
  if sBuscada <> '' then
    Result := (sSerie = sBuscada) or
              (InvertirBytesHex(sSerie) = sBuscada) or
              (sSerie = InvertirBytesHex(sBuscada));
  if (not Result) and (Trim(ATitular) <> '') then
  begin
    sTitular := NombreSimpleCertificado(ACert);
    Result := ContainsText(sTitular, Trim(ATitular));
  end;
end;

function BuscarCertificado(const ASerial, ATitular: string):
  PXadesCertContext;
var
  hStore: THandle;
  pActual: PXadesCertContext;
  sAlmacen: string;
  sErrorNoVigente: string;
  bSeguir: Boolean;
  bCoincide: Boolean;
begin
  Result := nil;
  sErrorNoVigente := '';
  sAlmacen := cCertStorePersonal;
  hStore := CertOpenSystemStoreW(0, PWideChar(sAlmacen));
  if hStore = 0 then
    RaiseLastOSError;
  pActual := nil;
  try
    bSeguir := True;
    while bSeguir do
    begin
      pActual := CertEnumCertificatesInStore(hStore, pActual);
      if pActual = nil then
        bSeguir := False
      else
      begin
        bCoincide := CertificadoCoincide(pActual, ASerial, ATitular);
        if bCoincide and CertificadoVigente(pActual) then
        begin
          Result := CertDuplicateCertificateContext(pActual);
          bSeguir := False;
        end
        else if bCoincide and (sErrorNoVigente = '') then
          sErrorNoVigente := MensajeCertificadoNoVigente(pActual);
      end;
    end;
    if pActual <> nil then
      CertFreeCertificateContext(pActual);
  finally
    CertCloseStore(hStore, 0);
  end;
  if Result = nil then
  begin
    if sErrorNoVigente <> '' then
      raise EXadesError.Create(sErrorNoVigente)
    else
      raise EXadesError.Create('No se encontro en el almacen personal de ' +
        'Windows un certificado vigente que coincida con el numero de serie ' +
        'o titular configurado.');
  end;
end;

function FirmarCapiSha256(hProv: ULONG_PTR; dwKeySpec: DWORD;
                          const ADatos: TBytes): TBytes;
var
  hHash: ULONG_PTR;
  iTam: DWORD;
begin
  hHash := 0;
  if not CryptCreateHash(hProv, CALG_SHA_256, 0, 0, hHash) then
    LanzarErrorFirmaCapiSha256(
      'No se pudo crear el hash SHA-256 para firmar');
  try
    if not CryptHashData(hHash, PunteroBytes(ADatos),
                         DWORD(Length(ADatos)), 0) then
      LanzarErrorFirmaCapiSha256(
        'No se pudieron cargar los datos a firmar');
    iTam := 0;
    if not CryptSignHashW(hHash, dwKeySpec, nil, 0, nil, iTam) then
      LanzarErrorFirmaCapiSha256(
        'No se pudo calcular el tamano de la firma SHA-256');
    SetLength(Result, iTam);
    if iTam > 0 then
    begin
      if not CryptSignHashW(hHash, dwKeySpec, nil, 0, @Result[0], iTam) then
        LanzarErrorFirmaCapiSha256('No se pudo firmar con SHA-256');
      InvertirBytes(Result);
    end;
  finally
    CryptDestroyHash(hHash);
  end;
end;

function FirmarCngSha256(hKey: ULONG_PTR; const ADatos: TBytes): TBytes;
var
  aHash: TBytes;
  iEstado: Integer;
  iTam: DWORD;
  oPadding: TBcryptPkcs1PaddingInfo;
  sAlgoritmo: string;
begin
  aHash := Sha256Bytes(ADatos);
  sAlgoritmo := 'SHA256';
  oPadding.pszAlgId := PWideChar(sAlgoritmo);
  iTam := 0;
  iEstado := NCryptSignHash(hKey, @oPadding, PunteroBytes(aHash),
                            DWORD(Length(aHash)), nil, 0, iTam,
                            NCRYPT_PAD_PKCS1_FLAG);
  if iEstado <> ERROR_SUCCESS then
    raise EXadesError.CreateFmt('NCryptSignHash fallo al calcular el ' +
      'tamano de la firma. Codigo: %d', [iEstado]);
  SetLength(Result, iTam);
  if iTam > 0 then
  begin
    iEstado := NCryptSignHash(hKey, @oPadding, PunteroBytes(aHash),
                              DWORD(Length(aHash)), @Result[0], iTam,
                              iTam, NCRYPT_PAD_PKCS1_FLAG);
    if iEstado <> ERROR_SUCCESS then
      raise EXadesError.CreateFmt('NCryptSignHash fallo al firmar. ' +
        'Codigo: %d', [iEstado]);
  end;
end;

function FirmarBytesSha256(ACert: PXadesCertContext; const ADatos: TBytes;
                           AFirmaSilenciosa: Boolean): TBytes;
var
  hKey: ULONG_PTR;
  dwFlags: DWORD;
  dwKeySpec: DWORD;
  bLiberar: BOOL;
begin
  hKey := 0;
  dwKeySpec := 0;
  bLiberar := False;
  dwFlags := CRYPT_ACQUIRE_ALLOW_NCRYPT_KEY_FLAG or
             CRYPT_ACQUIRE_PREFER_NCRYPT_KEY_FLAG or
             CRYPT_ACQUIRE_COMPARE_KEY_FLAG;
  if AFirmaSilenciosa then
    dwFlags := dwFlags or CRYPT_ACQUIRE_SILENT_FLAG;
  if not CryptAcquireCertificatePrivateKey(ACert, dwFlags, nil, hKey,
                                            dwKeySpec, bLiberar) then
    LanzarErrorCripto(
      'No se pudo abrir la clave privada del certificado');
  try
    if dwKeySpec = CERT_NCRYPT_KEY_SPEC then
      Result := FirmarCngSha256(hKey, ADatos)
    else
      Result := FirmarCapiSha256(hKey, dwKeySpec, ADatos);
  finally
    if bLiberar then
    begin
      if dwKeySpec = CERT_NCRYPT_KEY_SPEC then
        NCryptFreeObject(hKey)
      else
        CryptReleaseContext(hKey, 0);
    end;
  end;
end;

function FechaHoraXades(ADt: TDateTime): string;
var
  oDesfase: TTimeSpan;
  sSigno: string;
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

function BuscarFinEtiqueta(const AXml: string; APosIni: Integer): Integer;
  forward;

function EscaparRetornosCarroCanonicalXml(const AXml: string): string;
begin
  Result := StringReplace(AXml, #13, '&#xD;', [rfReplaceAll]);
end;

function NombreEtiquetaApertura(const AEtiqueta: string): string;
var
  i: Integer;
begin
  Result := '';
  i := 2;
  while (i <= Length(AEtiqueta)) and
        (not CharInSet(AEtiqueta[i], [' ', #9, #10, #13, '/', '>'])) do
  begin
    Result := Result + AEtiqueta[i];
    Inc(i);
  end;
end;

function EtiquetaEsVacia(const AEtiqueta: string;
                         out AMarcaCierre: Integer): Boolean;
begin
  Result := False;
  AMarcaCierre := Length(AEtiqueta) - 1;
  while (AMarcaCierre > 1) and (AEtiqueta[AMarcaCierre] <= ' ') do
    Dec(AMarcaCierre);
  if (AMarcaCierre > 1) and (AEtiqueta[AMarcaCierre] = '/') and
     (Length(AEtiqueta) > 2) and (AEtiqueta[2] <> '/') and
     (AEtiqueta[2] <> '?') and (not StartsText('<!--', AEtiqueta)) then
    Result := True;
end;

function ExpandirEtiquetasVaciasCanonicalXml(const AXml: string): string;
var
  i: Integer;
  iFin: Integer;
  iMarcaCierre: Integer;
  sEtiqueta: string;
  sApertura: string;
  sNombre: string;
begin
  Result := '';
  i := 1;
  while i <= Length(AXml) do
  begin
    if AXml[i] = '<' then
    begin
      iFin := BuscarFinEtiqueta(AXml, i);
      if iFin = 0 then
        raise EXadesError.Create('XML mal formado al canonicalizar.');
      sEtiqueta := Copy(AXml, i, iFin - i + 1);
      if EtiquetaEsVacia(sEtiqueta, iMarcaCierre) then
      begin
        sNombre := NombreEtiquetaApertura(sEtiqueta);
        sApertura := Copy(sEtiqueta, 1, iMarcaCierre - 1);
        while (sApertura <> '') and
              (sApertura[Length(sApertura)] <= ' ') do
          Delete(sApertura, Length(sApertura), 1);
        Result := Result + sApertura + '></' + sNombre + '>';
      end
      else
        Result := Result + sEtiqueta;
      i := iFin + 1;
    end
    else
    begin
      Result := Result + AXml[i];
      Inc(i);
    end;
  end;
end;

function CanonicalizarXmlLimitado(const AXml: string): string;
var
  iFinDecl: Integer;
begin
  Result := Trim(AXml);
  Result := StringReplace(Result, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
  if (Result <> '') and (Result[1] = #$FEFF) then
    Delete(Result, 1, 1);
  if StartsText('<?xml', Result) then
  begin
    iFinDecl := Pos('?>', Result);
    if iFinDecl > 0 then
      Result := Trim(Copy(Result, iFinDecl + 2, MaxInt));
  end;
  Result := ExpandirEtiquetasVaciasCanonicalXml(Result);
  Result := EscaparRetornosCarroCanonicalXml(Result);
end;

function BuscarFinEtiqueta(const AXml: string; APosIni: Integer): Integer;
var
  i: Integer;
  cComilla: Char;
begin
  Result := 0;
  cComilla := #0;
  i := APosIni;
  while (i <= Length(AXml)) and (Result = 0) do
  begin
    if ((AXml[i] = '"') or (AXml[i] = '''')) and (cComilla = #0) then
      cComilla := AXml[i]
    else if AXml[i] = cComilla then
      cComilla := #0
    else if (AXml[i] = '>') and (cComilla = #0) then
      Result := i;
    Inc(i);
  end;
end;

function PosPrimerElementoRaiz(const AXml: string): Integer;
var
  i: Integer;
  iFin: Integer;
begin
  Result := 0;
  i := 1;
  while (i <= Length(AXml)) and (Result = 0) do
  begin
    if AXml[i] <= ' ' then
      Inc(i)
    else if StartsText('<?xml', Copy(AXml, i, MaxInt)) then
    begin
      iFin := PosEx('?>', AXml, i);
      if iFin > 0 then
        i := iFin + 2
      else
        i := Length(AXml) + 1;
    end
    else if Copy(AXml, i, 4) = '<!--' then
    begin
      iFin := PosEx('-->', AXml, i);
      if iFin > 0 then
        i := iFin + 3
      else
        i := Length(AXml) + 1;
    end
    else if AXml[i] = '<' then
      Result := i
    else
      Inc(i);
  end;
end;

function NombreElementoRaiz(const AXml: string; APosRaiz: Integer): string;
var
  i: Integer;
begin
  Result := '';
  i := APosRaiz + 1;
  while (i <= Length(AXml)) and
        (not CharInSet(AXml[i], [' ', #9, #10, #13, '/', '>'])) do
  begin
    Result := Result + AXml[i];
    Inc(i);
  end;
end;

function EtiquetaAperturaTieneId(const AEtiqueta: string): Boolean;
begin
  Result := ContainsText(AEtiqueta, ' Id=') or
            ContainsText(AEtiqueta, ' Id =') or
            StartsText('<Id=', AEtiqueta) or
            ContainsText(AEtiqueta, ':Id=');
end;

function AsegurarIdRaiz(const AXml, AIdNodo: string;
                        out ANombreRaiz: string): string;
var
  iRaiz: Integer;
  iFin: Integer;
  sEtiqueta: string;
  iInsercion: Integer;
begin
  Result := AXml;
  iRaiz := PosPrimerElementoRaiz(Result);
  if iRaiz = 0 then
    raise EXadesError.Create('No se encontro el elemento raiz del XML.');
  ANombreRaiz := NombreElementoRaiz(Result, iRaiz);
  if ANombreRaiz = '' then
    raise EXadesError.Create('No se pudo determinar el nombre del nodo raiz.');
  iFin := BuscarFinEtiqueta(Result, iRaiz);
  if iFin = 0 then
    raise EXadesError.Create('No se encontro el cierre de la apertura raiz.');
  sEtiqueta := Copy(Result, iRaiz, iFin - iRaiz + 1);
  if (AIdNodo <> '') and (not EtiquetaAperturaTieneId(sEtiqueta)) then
  begin
    iInsercion := iFin;
    if (iFin > iRaiz) and (Result[iFin - 1] = '/') then
      iInsercion := iFin - 1;
    Insert(' Id="' + EscaparXml(AIdNodo) + '"', Result, iInsercion);
  end;
end;

function UltimaPos(const ASubCadena, ACadena: string): Integer;
var
  iPos: Integer;
  iSig: Integer;
begin
  Result := 0;
  iPos := Pos(ASubCadena, ACadena);
  while iPos > 0 do
  begin
    Result := iPos;
    iSig := PosEx(ASubCadena, ACadena, iPos + 1);
    iPos := iSig;
  end;
end;

function InsertarFirmaAntesCierreRaiz(const AXml, ANombreRaiz,
                                      AFirma: string): string;
var
  sCierre: string;
  iCierre: Integer;
begin
  sCierre := '</' + ANombreRaiz + '>';
  iCierre := UltimaPos(sCierre, AXml);
  if iCierre = 0 then
    raise EXadesError.Create('No se encontro el cierre del nodo raiz ' +
      ANombreRaiz + '.');
  Result := Copy(AXml, 1, iCierre - 1) + AFirma +
            Copy(AXml, iCierre, MaxInt);
end;

function InsertarFirmaAntesCierreNodo(const AXml, ANombreNodo,
                                      AFirma: string): string;
var
  sCierre: string;
  iCierre: Integer;
begin
  sCierre := '</' + ANombreNodo + '>';
  iCierre := UltimaPos(sCierre, AXml);
  if iCierre = 0 then
    raise EXadesError.Create('No se encontro el cierre del nodo ' +
      ANombreNodo + '.');
  Result := Copy(AXml, 1, iCierre - 1) + AFirma +
            Copy(AXml, iCierre, MaxInt);
end;

function ConstruirKeyInfo(const AOpciones: TXadesOpciones;
                          const ADatosCert: TXadesDatosCertificado): string;
begin
  Result :=
    '<ds:KeyInfo ' + AtributoXmlNsDs + ' Id="' +
    EscaparXml(AOpciones.IdKeyInfo) + '">' +
    '<ds:X509Data><ds:X509Certificate>' +
    ADatosCert.CertificadoBase64 +
    '</ds:X509Certificate></ds:X509Data></ds:KeyInfo>';
end;

function ConstruirPolitica(const AOpciones: TXadesOpciones): string;
begin
  Result := '';
  if (AOpciones.Politica in [xtpFacturae, xtpExplicita]) and
     (AOpciones.PoliticaIdentificador <> '') and
     (AOpciones.PoliticaHashBase64 <> '') then
  begin
    Result :=
      '<xades:SignaturePolicyIdentifier>' +
      '<xades:SignaturePolicyId>' +
      '<xades:SigPolicyId>' +
      '<xades:Identifier>' +
      EscaparXml(AOpciones.PoliticaIdentificador) +
      '</xades:Identifier>';
    if AOpciones.PoliticaDescripcion <> '' then
      Result := Result + '<xades:Description>' +
        EscaparXml(AOpciones.PoliticaDescripcion) +
        '</xades:Description>';
    Result := Result +
      '</xades:SigPolicyId>' +
      '<xades:SigPolicyHash>' +
      NodoDsVacioCanonico('DigestMethod', AtributoXmlNsDs +
      ' Algorithm="' + EscaparXml(AOpciones.PoliticaDigestMethod) + '"') +
      '<ds:DigestValue ' + AtributoXmlNsDs + '>' +
      AOpciones.PoliticaHashBase64 +
      '</ds:DigestValue>' +
      '</xades:SigPolicyHash>';
    if AOpciones.PoliticaUrl <> '' then
      Result := Result +
        '<xades:SigPolicyQualifiers>' +
        '<xades:SigPolicyQualifier>' +
        '<xades:SPURI>' + EscaparXml(AOpciones.PoliticaUrl) +
        '</xades:SPURI>' +
        '</xades:SigPolicyQualifier>' +
        '</xades:SigPolicyQualifiers>';
    Result := Result +
      '</xades:SignaturePolicyId>' +
      '</xades:SignaturePolicyIdentifier>';
  end;
  if Result = '' then
    Result := '<xades:SignaturePolicyIdentifier>' +
              '<xades:SignaturePolicyImplied/>' +
              '</xades:SignaturePolicyIdentifier>';
end;

function ConstruirRolFirmante(const AOpciones: TXadesOpciones): string;
begin
  Result := '';
  if Trim(AOpciones.RolFirmante) <> '' then
    Result := '<xades:SignerRole><xades:ClaimedRoles>' +
      '<xades:ClaimedRole>' + EscaparXml(Trim(AOpciones.RolFirmante)) +
      '</xades:ClaimedRole></xades:ClaimedRoles></xades:SignerRole>';
end;

function ConstruirDataObjectProperties(const AOpciones: TXadesOpciones):
  string;
begin
  Result := '';
  if Trim(AOpciones.IdReferenciaDocumento) <> '' then
  begin
    Result := '<xades:SignedDataObjectProperties>' +
      '<xades:DataObjectFormat ObjectReference="#' +
      EscaparXml(AOpciones.IdReferenciaDocumento) + '">';
    if AOpciones.ObjetoDescripcion <> '' then
      Result := Result + '<xades:Description>' +
        EscaparXml(AOpciones.ObjetoDescripcion) + '</xades:Description>';
    if AOpciones.ObjetoIdentificador <> '' then
      Result := Result +
        '<xades:ObjectIdentifier><xades:Identifier>' +
        EscaparXml(AOpciones.ObjetoIdentificador) +
        '</xades:Identifier><xades:Description/></xades:ObjectIdentifier>';
    Result := Result +
      '<xades:MimeType>text/xml</xades:MimeType>';
    if AOpciones.ObjetoEncoding <> '' then
      Result := Result + '<xades:Encoding>' +
        EscaparXml(AOpciones.ObjetoEncoding) + '</xades:Encoding>';
    Result := Result +
      '</xades:DataObjectFormat>' +
      '</xades:SignedDataObjectProperties>';
  end;
end;

function ConstruirSignedProperties(const AOpciones: TXadesOpciones;
                                   ACert: PXadesCertContext;
                                   const ACertDer: TBytes): string;
var
  sDigestCert: string;
  sIssuer: string;
  sSerieDecimal: string;
begin
  sDigestCert := Base64Bytes(Sha1Bytes(ACertDer));
  sIssuer := NombreX500(ACert^.pCertInfo^.Issuer);
  sSerieDecimal := SerieCertificadoDecimal(ACert);
  Result :=
    '<xades:SignedProperties xmlns:xades="' +
    EscaparXml(AOpciones.EspacioNombresXades) + '" Id="' +
    EscaparXml(AOpciones.IdSignedProperties) + '">' +
    '<xades:SignedSignatureProperties>' +
    '<xades:SigningTime>' + FechaHoraXades(Now) +
    '</xades:SigningTime>' +
    '<xades:SigningCertificate>' +
    '<xades:Cert>' +
    '<xades:CertDigest>' +
    NodoDsVacioCanonico('DigestMethod', AtributoXmlNsDs +
    ' Algorithm="' + cAlgSha1 + '"') +
    '<ds:DigestValue ' + AtributoXmlNsDs + '>' + sDigestCert +
    '</ds:DigestValue>' +
    '</xades:CertDigest>' +
    '<xades:IssuerSerial>' +
    '<ds:X509IssuerName ' + AtributoXmlNsDs + '>' + EscaparXml(sIssuer) +
    '</ds:X509IssuerName>' +
    '<ds:X509SerialNumber ' + AtributoXmlNsDs + '>' + sSerieDecimal +
    '</ds:X509SerialNumber>' +
    '</xades:IssuerSerial>' +
    '</xades:Cert>' +
    '</xades:SigningCertificate>' +
    ConstruirPolitica(AOpciones) +
    ConstruirRolFirmante(AOpciones) +
    '</xades:SignedSignatureProperties>' +
    ConstruirDataObjectProperties(AOpciones) +
    '</xades:SignedProperties>';
end;

function ConstruirReferenciaDocumento(const AOpciones: TXadesOpciones;
                                      const ADigestDocumento: string):
                                      string;
var
  sUri: string;
begin
  if AOpciones.UriDocumentoVacia then
    sUri := ''
  else
    sUri := '#' + AOpciones.IdNodoFirmado;
  Result :=
    '<ds:Reference Id="' + EscaparXml(AOpciones.IdReferenciaDocumento) +
    '" URI="' + EscaparXml(sUri) + '">' +
    '<ds:Transforms>' +
    NodoDsVacioCanonico('Transform', 'Algorithm="' + cAlgEnveloped + '"');
  if AOpciones.IncluirTransformCanonicoDocumento then
    Result := Result + NodoDsVacioCanonico('Transform',
      'Algorithm="' + AOpciones.AlgoritmoCanonicalizacion + '"');
  Result := Result +
    '</ds:Transforms>' +
    NodoDsVacioCanonico('DigestMethod', 'Algorithm="' + cAlgSha256 + '"') +
    '<ds:DigestValue>' + ADigestDocumento + '</ds:DigestValue>' +
    '</ds:Reference>';
end;

function ConstruirSignedInfo(const AOpciones: TXadesOpciones;
                             const ADigestDocumento,
                             ADigestSignedProperties,
                             ADigestKeyInfo: string): string;
begin
  Result :=
    '<ds:SignedInfo ' + AtributoXmlNsDs + '>' +
    NodoDsVacioCanonico('CanonicalizationMethod',
      'Algorithm="' + AOpciones.AlgoritmoCanonicalizacion + '"') +
    NodoDsVacioCanonico('SignatureMethod',
      'Algorithm="' + cAlgRsaSha256 + '"') +
    ConstruirReferenciaDocumento(AOpciones, ADigestDocumento) +
    '<ds:Reference Type="' + EscaparXml(AOpciones.TipoSignedProperties) +
    '" URI="#' + EscaparXml(AOpciones.IdSignedProperties) + '">' +
    '<ds:Transforms>' +
    NodoDsVacioCanonico('Transform',
      'Algorithm="' + AOpciones.AlgoritmoCanonicalizacion + '"') +
    '</ds:Transforms>' +
    NodoDsVacioCanonico('DigestMethod', 'Algorithm="' + cAlgSha256 + '"') +
    '<ds:DigestValue>' + ADigestSignedProperties + '</ds:DigestValue>' +
    '</ds:Reference>';
  if AOpciones.IncluirReferenciaKeyInfo then
    Result := Result +
      '<ds:Reference URI="#' + EscaparXml(AOpciones.IdKeyInfo) + '">' +
      '<ds:Transforms>' +
      NodoDsVacioCanonico('Transform',
        'Algorithm="' + AOpciones.AlgoritmoCanonicalizacion + '"') +
      '</ds:Transforms>' +
      NodoDsVacioCanonico('DigestMethod', 'Algorithm="' + cAlgSha256 + '"') +
      '<ds:DigestValue>' + ADigestKeyInfo + '</ds:DigestValue>' +
      '</ds:Reference>';
  Result := Result + '</ds:SignedInfo>';
end;

function ConstruirSignature(const AOpciones: TXadesOpciones;
                            const ASignedInfo, ASignatureValue,
                            AKeyInfo, ASignedProperties: string): string;
begin
  Result :=
    '<ds:Signature ' + AtributoXmlNsDs + ' xmlns:xades="' +
    EscaparXml(AOpciones.EspacioNombresXades) + '" Id="' +
    EscaparXml(AOpciones.IdFirma) + '">' +
    ASignedInfo +
    '<ds:SignatureValue>' + ASignatureValue + '</ds:SignatureValue>' +
    AKeyInfo +
    '<ds:Object Id="' + EscaparXml(AOpciones.IdObjeto) + '">' +
    '<xades:QualifyingProperties Id="' +
    EscaparXml(AOpciones.IdObjeto) + '-QualifyingProperties" Target="#' +
    EscaparXml(AOpciones.IdFirma) + '">' +
    ASignedProperties +
    '<xades:UnsignedProperties/>' +
    '</xades:QualifyingProperties>' +
    '</ds:Object>' +
    '</ds:Signature>';
end;

function FirmarXmlXadesEnveloped(const AXml: string;
                                  const ASerialCert, ATitularCert: string;
                                  const AOpciones: TXadesOpciones;
                                  out ADatosCert: TXadesDatosCertificado):
                                  string;
var
  oOpciones: TXadesOpciones;
  pCert: PXadesCertContext;
  aCertDer: TBytes;
  aFirma: TBytes;
  sXmlBase: string;
  sRaiz: string;
  sCanonDocumento: string;
  sKeyInfo: string;
  sSignedProperties: string;
  sSignedInfo: string;
  sCanonSignedInfo: string;
  sDigestDocumento: string;
  sDigestSignedProperties: string;
  sDigestKeyInfo: string;
  sSignatureValue: string;
  sSignature: string;
begin
  ADatosCert.NumeroSerie := '';
  ADatosCert.Titular := '';
  ADatosCert.HuellaSha1 := '';
  ADatosCert.CertificadoBase64 := '';
  oOpciones := AsegurarOpciones(AOpciones);
  pCert := BuscarCertificado(ASerialCert, ATitularCert);
  try
    aCertDer := CertificadoDerBytes(pCert);
    ADatosCert.NumeroSerie := SerieCertificadoHexLE(pCert);
    ADatosCert.Titular := NombreSimpleCertificado(pCert);
    ADatosCert.HuellaSha1 := BytesToHexMayus(Sha1Bytes(aCertDer));
    ADatosCert.CertificadoBase64 := Base64Bytes(aCertDer);
    sXmlBase := AsegurarIdRaiz(AXml, oOpciones.IdNodoFirmado, sRaiz);
    sCanonDocumento := CanonicalizarXmlLimitado(sXmlBase);
    sKeyInfo := ConstruirKeyInfo(oOpciones, ADatosCert);
    sSignedProperties := ConstruirSignedProperties(oOpciones, pCert,
                                                   aCertDer);
    sDigestDocumento := DigestSha256Base64(sCanonDocumento);
    sDigestSignedProperties := DigestSha256Base64(
      CanonicalizarXmlLimitado(sSignedProperties));
    sDigestKeyInfo := DigestSha256Base64(CanonicalizarXmlLimitado(sKeyInfo));
    sSignedInfo := ConstruirSignedInfo(oOpciones, sDigestDocumento,
                                       sDigestSignedProperties,
                                       sDigestKeyInfo);
    sCanonSignedInfo := CanonicalizarXmlLimitado(sSignedInfo);
    aFirma := FirmarBytesSha256(pCert, BytesUtf8(sCanonSignedInfo),
                                oOpciones.FirmaSilenciosa);
    sSignatureValue := Base64Bytes(aFirma);
    sSignature := ConstruirSignature(oOpciones, sSignedInfo,
                                     sSignatureValue, sKeyInfo,
                                     sSignedProperties);
    if Trim(oOpciones.NombreNodoInsercionFirma) <> '' then
      Result := InsertarFirmaAntesCierreNodo(sXmlBase,
        oOpciones.NombreNodoInsercionFirma, sSignature)
    else
      Result := InsertarFirmaAntesCierreRaiz(sXmlBase, sRaiz, sSignature);
  finally
    CertFreeCertificateContext(pCert);
  end;
end;

end.
