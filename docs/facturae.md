# Facturae (factura electronica)

`Fiscal.Facturae.pas` construye el XML **Facturae 3.2.x** a partir de *records*
y lo firma con XAdES reutilizando `Fiscal.Xades`. El nucleo **no depende de base
de datos** ni de componentes de acceso a datos: la aplicacion (por ejemplo, el
adaptador de Factuzam) rellena el record y decide donde persistir el resultado.

## Idea general

1. Rellenas un `TFacturaeFactura` (emisor, receptor, lineas, forma de pago...).
2. `ConstruirXmlFacturae` devuelve el XML 3.2.2 **sin firmar** (multiplataforma).
3. `EmitirFacturaeFirmada` **valida + construye + firma** en un paso y devuelve
   el `.xsig` (requiere certificado en el almacen personal de Windows).

La base, las cuotas de IVA, el recargo de equivalencia, la retencion y los
totales los calcula la libreria a partir de las lineas: solo aportas cantidad,
precio unitario sin IVA y tipos.

## Tipos publicos

```pascal
TFacturaeParte = record
  Nif, RazonSocial, Direccion, CodigoPostal, Poblacion, Provincia: string;
  CodigoPais, NombrePais, TipoResidencia: string;
  OficinaContable, OrganoGestor, UnidadTramitadora: string;  // DIR3 (FACe)
end;

TFacturaeLinea = record
  Descripcion: string;
  Cantidad, PrecioUnitario, TipoIva, TipoRecargo: Double;
  // Base, CuotaIva y CuotaRecargo se calculan.
end;

TFacturaeFactura = record
  Version, Serie, Numero, FormaPagoFacturae, Moneda, Idioma: string;
  FechaExpedicion, FechaVencimiento: TDateTime;
  TipoRetencion: Double;
  Emisor, Receptor: TFacturaeParte;
  Lineas: TArray<TFacturaeLinea>;
  procedure AnadirLinea(const ADescripcion: string;
                        ACantidad, APrecioUnitario, ATipoIva: Double;
                        ATipoRecargo: Double = 0);
  // BaseImponibleTotal, CuotaIvaTotal, ImporteRetencion, TotalFactura...
end;
```

## Funciones publicas

- `ConstruirXmlFacturae(AFactura): string` — XML Facturae sin firmar.
- `EmitirFacturaeFirmada(AFactura, ASerial, ATitular, ADatosCert): string` —
  XML firmado (.xsig).
- `ValidarFacturae(AFactura)` — lanza `EFacturaeError` con la lista de fallos.
- `NombreArchivoFacturae`, `IdFacturaeSeguro`, `NormalizarFormaPagoFacturae`,
  `CodigoPaisFacturae`, `NamespaceFacturae` — utilidades.

## Ejemplo minimo

```pascal
uses
  Fiscal.Facturae, Fiscal.Xades;

procedure EmitirFactura;
var
  oFactura:   TFacturaeFactura;
  oDatosCert: TXadesDatosCertificado;
  sXsig:      string;
begin
  oFactura := Default(TFacturaeFactura);
  oFactura.Serie  := '2026.A1';
  oFactura.Numero := '000005';
  oFactura.FechaExpedicion   := EncodeDate(2026, 6, 17);
  oFactura.FormaPagoFacturae := '04';

  oFactura.Emisor.Nif         := 'A39000005';
  oFactura.Emisor.RazonSocial := 'Suministros del Norte SL';
  oFactura.Emisor.Direccion   := 'Calle Mayor 1';
  oFactura.Emisor.CodigoPostal := '39001';
  oFactura.Emisor.Poblacion   := 'Santander';
  oFactura.Emisor.Provincia   := 'Cantabria';

  oFactura.Receptor.Nif         := 'P3900000E';
  oFactura.Receptor.RazonSocial := 'Ayuntamiento de Demostracion';
  oFactura.Receptor.Direccion   := 'Plaza del Consistorio 1';
  oFactura.Receptor.CodigoPostal := '39002';
  oFactura.Receptor.Poblacion   := 'Santander';
  oFactura.Receptor.Provincia   := 'Cantabria';
  // Receptor publico (FACe): tres centros DIR3.
  oFactura.Receptor.OficinaContable   := 'L01390000';
  oFactura.Receptor.OrganoGestor      := 'L01390000';
  oFactura.Receptor.UnidadTramitadora := 'L01390000';

  oFactura.AnadirLinea('Servicio de consultoria', 10, 50.00, 21);
  oFactura.AnadirLinea('Material de oficina', 5, 12.00, 21);

  // Sin firmar (multiplataforma):
  //   sXml := ConstruirXmlFacturae(oFactura);
  // Firmado (.xsig, certificado del almacen de Windows):
  sXsig := EmitirFacturaeFirmada(oFactura,
    'SERIE_CERTIFICADO_WINDOWS', 'TITULAR O CN DEL CERTIFICADO', oDatosCert);
end;
```

El proyecto [`examples/10-facturae`](../examples/10-facturae) hace lo mismo
leyendo la factura desde un XML sencillo (sin base de datos): en modo demo
escribe el XML sin firmar y, con serial + titular, escribe el `.xsig`.

## Firma XAdES

La firma usa la **politica de firma Facturae** y el rol `emisor`, que aporta
`Fiscal.Xades.OpcionesXadesFacturae` (ver [`docs/xades.md`](./xades.md)). La
firma es *enveloped* sobre todo el documento (`URI=""`) e inserta el
`ds:Signature` como hijo de `Facturae`.

El `SignedInfo` incluye tres referencias: el documento firmado, las
`SignedProperties` XAdES y el `KeyInfo`. Por eso el verificador local configura
`signxml` con `expect_references=3`; si se usa el valor por defecto de
`XMLVerifier` (1 referencia), un `.xsig` correcto se rechazara por la herramienta
de prueba.

El `.xsig` resultante se puede comprobar localmente con el script opcional
[`examples/10-facturae/verificar_facturae_xsig.py`](../examples/10-facturae/verificar_facturae_xsig.py)
(`signxml`: `XMLVerifier` / `XAdESVerifier`). No sustituye la validacion oficial
(VALIDe / FACe).

## Detalles del formato

- Facturae usa `elementFormDefault="unqualified"`: la raiz va con prefijo
  (`fe:Facturae xmlns:fe="..."`) y los elementos hijos **sin prefijo**. La
  libreria genera exactamente esa forma.
- El espacio de nombres depende de la version (`NamespaceFacturae`): por
  defecto, 3.2.2.
- Los `AdministrativeCentres` (DIR3) se emiten como **hijo directo de la parte**
  (tras `TaxIdentification` y antes de `Individual`/`LegalEntity`), como exige el
  esquema, y solo cuando estan los tres codigos.

## Limitaciones

- No hay validacion XSD completa contra los esquemas oficiales: `ValidarFacturae`
  es una prevalidacion de negocio y estructura minima antes de firmar.
- Las personas fisicas separan la razon social de forma simple (primer token =
  nombre, resto = primer apellido). Si necesitas Facturae estricto para
  autonomos, guarda nombre y apellidos desglosados.
- Para receptores extranjeros, fija `TipoResidencia` ('E' UE / 'U' no UE) y un
  `CodigoPais` ISO-3166 alfa-3; por defecto se asume residente en Espana.
- El vencimiento se emite con `FechaVencimiento` (o la de expedicion si es 0) y
  un unico `Installment`. No cubre vencimientos multiples ni domiciliacion.

> **Aviso:** el `.xsig` generado es un XML Facturae firmado, pero el cumplimiento
> B2B/B2G completo (intercambio por plataforma, estados, acuse/aceptacion/rechazo)
> depende del circuito que implante la aplicacion final. Este codigo no sustituye
> asesoramiento fiscal ni homologacion oficial.
