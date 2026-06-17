# Plan de extraccion

## Publicado en la primera rama

- Firma XAdES generica.
- Validador NIF/NIE/CIF.
- Ejemplos minimos de consola.

## Siguiente bloque

- `Fiscal.Facturae.Types.pas`
- `Fiscal.Facturae.pas`
- Ejemplo de Facturae 3.2.2 firmado con datos ficticios.

La API publica debe recibir records de emisor, receptor, factura y lineas. No
debe recibir conexiones de base de datos.

## Despues

- `Fiscal.Verifactu.Types.pas`
- `Fiscal.Verifactu.Registros.pas`
- `Fiscal.Verifactu.QR.pas`
- `Fiscal.NoVerifactu.Eventos.pas`
- `Fiscal.NoVerifactu.Export.pas`
- `Fiscal.NoVerifactu.Verify.pas`

El contenedor de exportacion NO VERI*FACTU no debe firmarse como garantia
adicional. Lo relevante legalmente es que cada registro y cada evento se firmen
cuando se crean.
