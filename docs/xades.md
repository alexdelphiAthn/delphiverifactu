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

## Certificado

`FirmarXmlXadesEnveloped` busca el certificado en el almacen personal de
Windows (`MY`) por numero de serie o por titular. El numero de serie se
normaliza quitando espacios, guiones y dos puntos, y se acepta tanto en el orden
que muestra el visor de certificados como en el orden inverso que exponen
algunas APIs de Windows.

Si se solicita firma y el certificado no existe, esta caducado, no tiene clave
privada o el usuario cancela el acceso a la clave, la funcion lanza excepcion.
No hay fallback silencioso a huella SHA-256.

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
