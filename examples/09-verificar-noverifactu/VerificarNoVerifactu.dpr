{******************************************************************************}
{  VerificarNoVerifactu - Ejemplo de uso de Fiscal.VerificarNoVerifactu        }
{                                                                              }
{  Verifica los ficheros NO VERI*FACTU generados por los ejemplos 07 y 08:     }
{    - estructura (raices y que haya registros),                               }
{    - cadena de eventos (HashAnterior enlaza con el HashPropio anterior),     }
{    - coherencia de huella y de firma,                                        }
{    - perfil XAdES (algoritmos y politica AGE).                               }
{                                                                              }
{  Le pasas UNO de los dos ficheros y el ejemplo deduce su pareja:             }
{    VerificarNoVerifactu.exe noverifactu_facturacion.xml                      }
{  tambien vale el de eventos suelto:                                          }
{    VerificarNoVerifactu.exe eventos_noverifactu.xml                          }
{                                                                              }
{  Uso:  VerificarNoVerifactu.exe <fichero.xml> [informe.txt]                  }
{                                                                              }
{  Nota: NO valida criptograficamente la firma RSA. Para la validacion legal   }
{  completa de la firma, lleva un registro individual firmado a VALIDe.        }
{                                                                              }
{  Autor:  Alejandro Laorden Hidalgo                                           }
{  Email:  alejandro.laorden@protonmail.com                                    }
{******************************************************************************}
program VerificarNoVerifactu;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.StrUtils,
  System.IOUtils,
  Fiscal.Xades in '..\..\src\Fiscal.Xades.pas',
  Fiscal.EnvioVerifactu in '..\..\src\Fiscal.EnvioVerifactu.pas',
  Fiscal.NoVerifactu in '..\..\src\Fiscal.NoVerifactu.pas',
  Fiscal.VerificarNoVerifactu in '..\..\src\Fiscal.VerificarNoVerifactu.pas';

// True si el fichero existe y contiene la etiqueta de raiz indicada.
function ContieneRaiz(const APath, ARaiz: string): Boolean;
begin
  Result := TFile.Exists(APath) and
            (Pos(ARaiz, TFile.ReadAllText(APath, TEncoding.UTF8)) > 0);
end;

procedure Ejecutar(const ASeleccionado, AInforme: string);
var
  sEvInfer:     string;
  sFaInfer:     string;
  sEventos:     string;
  sFacturacion: string;
  oRes:         TResultadoVerificacion;
  sSalida:      string;
  sInforme:     string;
begin
  if not TFile.Exists(ASeleccionado) then
    raise Exception.Create('No se encuentra el fichero: ' + ASeleccionado);

  // A partir del fichero elegido, deducimos la pareja <base>_eventos.xml /
  // <base>_facturacion.xml y verificamos los que existan.
  InferirFicheros(ASeleccionado, sEvInfer, sFaInfer);
  sEventos     := '';
  sFacturacion := '';
  if TFile.Exists(sEvInfer) then
    sEventos := sEvInfer;
  if TFile.Exists(sFaInfer) then
    sFacturacion := sFaInfer;

  // Fichero suelto que no sigue el patron _eventos/_facturacion (p.ej. el
  // que genera el ejemplo 07): lo clasificamos por su etiqueta de raiz.
  if (sEventos = '') and (sFacturacion = '') then
  begin
    if ContieneRaiz(ASeleccionado, 'RegistroEventosNoVerifactu') then
      sEventos := ASeleccionado
    else if ContieneRaiz(ASeleccionado, 'RegistroFacturacionNoVerifactu') then
      sFacturacion := ASeleccionado
    else
      sEventos := ASeleccionado;  // que el verificador informe de la raiz
  end;

  Writeln('====================================================');
  Writeln(' Verificacion de registros NO VERI*FACTU');
  Writeln('====================================================');
  if sEventos <> '' then
    Writeln('Eventos     : ', sEventos);
  if sFacturacion <> '' then
    Writeln('Facturacion : ', sFacturacion);
  Writeln('');

  oRes := VerificarFicheros(sEventos, sFacturacion);

  Writeln(oRes.Resumen);
  Writeln('');
  Writeln('Detalle:');
  Writeln(oRes.Detalle);
  Writeln('');
  if oRes.Correcto then
    Writeln('=> RESULTADO: CORRECTO',
      IfThen(oRes.Avisos > 0, ' (con avisos)', ''))
  else
    Writeln('=> RESULTADO: CON ERRORES');

  // Informe en disco junto al fichero verificado.
  sSalida := AInforme;
  if sSalida = '' then
    sSalida := TPath.Combine(TPath.GetDirectoryName(ASeleccionado),
      'verificacion_' +
      TPath.GetFileNameWithoutExtension(ASeleccionado) + '.txt');
  sInforme := oRes.Resumen + sLineBreak + sLineBreak +
    'Detalle:' + sLineBreak + oRes.Detalle + sLineBreak;
  TFile.WriteAllText(sSalida, sInforme, TEncoding.UTF8);
  Writeln('Informe     : ', sSalida);

  // Codigo de salida: 4 si hay errores (util para automatizar).
  if not oRes.Correcto then
    Halt(4);
end;

var
  sSeleccionado: string;
begin
  try
    sSeleccionado := ParamStr(1);
    if sSeleccionado = '' then
      sSeleccionado := 'noverifactu_facturacion.xml';
    Ejecutar(sSeleccionado, ParamStr(2));
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
