# Avisos

Este proyecto publica codigo Delphi propio bajo licencia MIT.

La unidad `Fiscal.Xades.pas` usa la API criptografica de Windows
(`crypt32.dll`, `advapi32.dll` y `ncrypt.dll`) y no invoca procesos externos.

## Componentes de terceros

La unidad `src/DelphiZXIngQRCode.pas` es un port a Delphi de ZXing QRCode
realizado por Debenu Pty Ltd (www.debenu.com), basado en el proyecto ZXing
("Zebra Crossing", https://github.com/zxing/zxing).

    Copyright 2008 ZXing authors

Distribuido bajo la licencia Apache, version 2.0. Puedes obtener una copia de la
licencia en http://www.apache.org/licenses/LICENSE-2.0. El fichero conserva en su
cabecera el aviso de copyright y de licencia original. La copia incluida en este
repositorio esta adaptada para Veri*factu (nivel de correccion M y zona de
silencio activados por defecto).

## Datos sensibles

Los ejemplos usan datos ficticios. No subas certificados, XML firmados reales,
NIF reales de clientes, informes de validacion ni ficheros con datos privados.
