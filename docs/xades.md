# Firma XAdES

`Fiscal.Xades.pas` firma XML en modo XAdES Enveloped usando certificados del
almacen personal de Windows.

Funciones publicas principales:

- `OpcionesXadesBase`
- `OpcionesXadesFacturae`
- `OpcionesXadesNoVerifactu`
- `FirmarXmlXadesEnveloped`
- `NormalizarSerieCertificadoXades`

La clave privada no se exporta. La firma se hace mediante CAPI/CNG.

## Facturae

Para Facturae usa:

```pascal
oOpciones := OpcionesXadesFacturae('EDOC-2026-A1-000005');
oOpciones.RolFirmante := 'emisor';
```

## NO VERI*FACTU

Para registros NO VERI*FACTU usa:

```pascal
oOpciones := OpcionesXadesNoVerifactu('FZ-FACTURA-' + sHuella);
```

En eventos NO VERI*FACTU la firma debe insertarse dentro del nodo `sf:Evento`:

```pascal
oOpciones.NombreNodoInsercionFirma := 'sf:Evento';
```
