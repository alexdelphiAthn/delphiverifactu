# Delphi Verifactu

Librerias Delphi para firma XAdES, Facturae y registros Verifactu /
NO VERI*FACTU.

El repositorio empieza por las piezas que ya son reutilizables sin depender de
una base de datos concreta:

- `Fiscal.Xades.pas`: firma XAdES Enveloped con certificado del almacen
  personal de Windows.
- `Fiscal.DocumentoFiscal.pas`: validacion local de NIF, NIE y CIF espanoles.

Las partes de Facturae, Verifactu, NO VERI*FACTU, exportacion y verificacion se
irán subiendo en unidades separadas, desacopladas de la aplicacion original. La
API publica debe trabajar con records y XML, no con tablas privadas ni
componentes de acceso a datos.

## Requisitos

- Delphi moderno con soporte para namespaces de unidad.
- Windows, para `Fiscal.Xades.pas`.
- Un certificado instalado en el almacen personal de Windows con clave privada
  disponible para firmar.

No se usa OpenSSL, PowerShell ni procesos externos para firmar XML.

## Ejemplos

Los ejemplos estan en `examples/`:

- `01-xades`: firma un XML con politica Facturae.
- `02-documento-fiscal`: valida NIF/NIE/CIF desde consola.
- `03-noverifactu-firma`: firma un XML de registro NO VERI*FACTU ya construido.

## Estado

Este repositorio esta en fase inicial. Las unidades publicadas son utiles, pero
el cumplimiento fiscal completo depende de la integracion de cada aplicacion:
persistencia, encadenamiento, reloj, certificado, validaciones previas y envio
o exportacion segun el modo fiscal.

Este codigo no sustituye asesoramiento fiscal ni validacion oficial de la AEAT,
Facturae, FACe o cualquier otra administracion.
