# Verificador de registros NO VERI\*FACTU

`Fiscal.VerificarNoVerifactu.pas` comprueba **en local**, sin red ni procesos
externos, los ficheros que genera `Fiscal.NoVerifactu` (los del ejemplo
[`08-noverifactu-facturas`](../examples/08-noverifactu-facturas) y
[`07-noverifactu-eventos`](../examples/07-noverifactu-eventos)).

Es el complemento natural del generador: **genera con `07`/`08` → verifica con
`09`**.

## Qué comprueba

1. **Estructura** — que cada fichero tenga su raíz (`RegistroEventosNoVerifactu`
   / `RegistroFacturacionNoVerifactu`) y al menos un registro.
2. **Cadena de eventos** — que el `HashAnterior` de cada evento sea el
   `HashPropio` del evento anterior (el primero arranca con 64 ceros). Una
   cadena rota = manipulación.
3. **Coherencia de huella** — que la huella del contenedor coincida con la del
   registro/evento firmado embebido (`HuellaEvento` / `Huella`).
4. **Coherencia de firma** — que el `SignatureValue` del XML firmado coincida
   con la firma guardada y, en eventos, que `FirmaDigital = SHA-256(FirmaXades)`.
5. **Perfil XAdES** — algoritmos (RSA-SHA256, SHA-256 en las referencias, C14N)
   y **política AGE** (`urn:oid:2.16.724.1.3.1.1.2.1.9`, hash SHA-1, URL de
   sede) exigidos por la AEAT.
6. **Firma RSA (solo Windows)** — recomputa el digest del documento (transform
   *enveloped*) y verifica el `SignatureValue` con la **clave pública** del
   certificado del `KeyInfo`, comprueba su **vigencia** y que sea el
   certificado **referenciado** en `SigningCertificate`. Reutiliza la
   criptografía de `Fiscal.Xades` (CryptoAPI de Windows).

## Errores vs avisos

El verificador lee el atributo `ModoVerifactu` del XML:

- **`NO_VERIFACTU`** (exportación firmada): la falta de firma o un perfil XAdES
  incorrecto es **ERROR**.
- **`SIN`** (exportación demo, sin certificado): esos mismos puntos son solo
  **AVISO**, porque el fichero no pretende ser un cierre legal.

En la verificación criptográfica (punto 6): una **firma RSA inválida** o un
certificado del `KeyInfo` que **no coincide** con el de `SigningCertificate` son
**ERROR**. En cambio, que el **digest del documento** no cuadre, que el
certificado esté **fuera de vigencia a la fecha actual** (normal en facturas
antiguas) o que la criptografía **no se pueda ejecutar** (otra plataforma, sin
proveedor) son **AVISO**, para no invalidar por causas ajenas a una
manipulación.

`Errores = 0` ⇒ verificación **correcta** (los avisos no la invalidan).

## Qué NO hace (importante)

En Windows **sí** verifica la firma RSA y el digest del documento (punto 6),
pero con dos límites:

- **No comprueba la cadena de confianza** del certificado (que la CA raíz sea
  de confianza, revocación/OCSP). Solo valida la firma y la vigencia.
- La verificación de firma asume la **canonicalización limitada** de esta
  librería; está pensada para los ficheros que ella genera, no para cualquier
  XAdES de terceros con otro formato.

Para la validación legal completa de la firma, extrae un **registro individual
firmado** (`RegistroXmlFirmado`) y llévalo a **VALIDe**.

## API pública

- `InferirFicheros` — de un fichero deduce la pareja `_eventos.xml` /
  `_facturacion.xml`.
- `VerificarFicheros` — verifica los dos ficheros (cualquiera puede ir `''`
  para omitirlo).
- `VerificarContenido` — igual, pero recibiendo el XML en memoria (útil para
  verificar lo recién generado o para tests).
- `TResultadoVerificacion.Correcto` / `.Resumen` — resultado y resumen.
- `TResultadoVerificacion.Operaciones` — una línea por operación (evento /
  factura) con su estado `OK` / `AVISO (n)` / `ERROR (n)`, incluyendo las
  correctas (resumen línea a línea).
- `Fiscal.Xades.VerificarFirmaXadesEnveloped` — verificación criptográfica de
  una firma XAdES Enveloped; la usa el verificador internamente en Windows.

## Uso típico

```pascal
var
  oRes: TResultadoVerificacion;
begin
  oRes := VerificarFicheros('noverifactu_eventos.xml',
                            'noverifactu_facturacion.xml');
  Writeln(oRes.Resumen);
  if not oRes.Correcto then
    Writeln(oRes.Detalle);   // lineas 'ERROR: ...' / 'AVISO: ...'
end;
```

## El ejemplo

[`09-verificar-noverifactu`](../examples/09-verificar-noverifactu) deduce la
pareja, verifica (en Windows también la firma RSA) y muestra un **resumen por
operación** (`OK` / `AVISO` / `ERROR` por cada evento y factura) además del
detalle, escribiendo un informe `verificacion_<nombre>.txt`:

```text
:: 1) genera (demo, sin certificado):
RegistrarFacturasNoVerifactu.exe facturas.xml noverifactu

:: 2) verifica:
VerificarNoVerifactu.exe noverifactu_facturacion.xml
```

En modo demo, el resumen dará **CORRECTO (con avisos)** —la cadena y las huellas
cuadran, pero falta la firma legal—. Si generas con certificado
(`... noverifactu <serial> <titular>`), las firmas se verifican contra el perfil
AEAT y el resultado es **CORRECTO** sin avisos de firma.

> Prueba a editar a mano un `HashPropio` o un `Huella` del XML y vuelve a
> verificar: verás cómo la cadena se marca como **ERROR**. Eso es justo lo que
> detecta una manipulación.
