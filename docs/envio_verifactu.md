# Envío de Veri\*factu a la AEAT — explicación del ejemplo

Este documento explica, paso a paso, el ejemplo de envío de un registro de
facturación **Veri\*factu** a la Agencia Tributaria (AEAT) que encontrarás en
esta carpeta. Es una versión **didáctica y autocontenida** (solo depende de la
RTL de Delphi) destilada del subsistema real de Factuzam.

---

## 1. Qué es Veri\*factu

Veri\*factu es el sistema de la AEAT que obliga a los programas de facturación a
generar, por cada factura, un **registro de facturación** firmado por huella y
**encadenado** con el de la factura anterior, de forma que la secuencia sea
inalterable. El marco normativo:

- **Real Decreto 1007/2023** — Reglamento de los sistemas informáticos de
  facturación (requisitos de integridad, conservación, trazabilidad e
  inalterabilidad).
- **Orden HAC/1177/2024** — especificaciones técnicas: estructura de los
  registros, huella SHA-256, y formato del **QR tributario**.

Hay dos modalidades:

| Modalidad        | Qué hace                                                        |
|------------------|----------------------------------------------------------------|
| **Veri\*factu**  | Remite cada registro a la AEAT en el momento (lo que cubre este ejemplo). |
| **No Veri\*factu** | Guarda los registros firmados en local; la AEAT los inspecciona a posteriori. |

Este ejemplo implementa la modalidad **Veri\*factu** para el **registro de alta**
(emisión de una factura). La anulación (`RegistroAnulacion`) sigue el mismo
patrón y está en el código real.

---

## 2. Qué hace este ejemplo

A partir de una factura estilo Factuzam, la librería:

1. Compone el XML del `RegistroAlta` (esquemas `SuministroLR` /
   `SuministroInformacion`).
2. Calcula la **huella SHA-256 encadenada** (cada factura enlaza con la huella
   de la anterior del mismo emisor).
3. Construye la **URL de cotejo del QR tributario**.
4. Envuelve el registro en un sobre **SOAP** y lo remite por **HTTPS** con el
   **certificado** de la empresa emisora.

---

## 3. Estructura de ficheros

```
examples/04-envio-verifactu/
├── EnviarDatosVerifactu.dpr   ← programa de consola de la demostración
├── EnviarDatosVerifactu.ini   ← datos variables (NIF, factura, cadena, entorno)
├── facturas.sql               ← tabla fza_facturas + fza_verifactu_cadena (demo)
└── envio_verifactu.md         ← este documento

src/
└── Fiscal.EnvioVerifactu.pas  ← la librería (unit Fiscal.EnvioVerifactu)
```

---

## 4. El flujo paso a paso

Todo el flujo lo orquesta `PrepararRegistroAlta`, que internamente encadena las
funciones siguientes.

### 4.1 Identificar el sistema informático (SIF)

`ConstruirSistemaInformatico(...)` genera el bloque `<SistemaInformatico>` con
los datos del **productor del software**: nombre/razón, NIF, nombre del sistema,
identificador, versión y número de instalación. La AEAT rechaza el envío (error
genérico 1100) si el NIF del productor va vacío o mal formado.

### 4.2 Cargar la factura

La factura se representa con el record `TFacturaVerifactu`, cuyos campos calcan
las columnas de `fza_facturas`. En producción se cargan por UniDAC desde la BBDD;
en el ejemplo se leen del `.ini` para que compile sin base de datos.

### 4.3 El encadenamiento (cadena de huellas)

Cada emisor (NIF) tiene **una** cadena de huellas en `fza_verifactu_cadena`. El
último eslabón se representa con `TEslabonCadena` (serie, número, fecha y huella
de la última factura aceptada).

- Si la huella anterior está **vacía**, el registro es el **primero**:
  `<Encadenamiento><PrimerRegistro>S</PrimerRegistro></Encadenamiento>`.
- Si no, se incluye `<RegistroAnterior>` con los datos del eslabón previo.

> ⚠️ En producción la fila de la cadena se bloquea con `SELECT … FOR UPDATE`
> dentro de la transacción del envío, para serializar el encadenamiento entre
> varios puestos. En el ejemplo se simplifica leyéndolo del `.ini`.

### 4.4 Calcular la huella SHA-256

`CalcularHuellaAlta(...)` concatena los campos **en este orden exacto** (no se
puede alterar), separados por `&`, y aplica SHA-256 en hexadecimal mayúscula:

```
IDEmisorFactura=<NIF emisor>
&NumSerieFactura=<serie+numero>
&FechaExpedicionFactura=<dd-mm-aaaa>
&TipoFactura=<F1/F2/R1...>
&CuotaTotal=<importe 2 decimales>
&ImporteTotal=<importe 2 decimales>
&Huella=<huella del registro anterior>
&FechaHoraHusoGenRegistro=<yyyy-mm-ddThh:mm:ss+hh:mm>
```

Esa huella es la que enlaza esta factura con la siguiente: pasa a ser el
`&Huella=` de la próxima.

### 4.5 Construir el RegistroAlta (XML)

`ConstruirRegistroAlta(...)` ensambla el `<RegistroAlta>` completo:
identificación de la factura, emisor, tipo, descripción, **destinatario** (solo
en facturas completas F1 y rectificativas R1; las simplificadas F2 no lo
llevan), **desglose** de IVA por bandas, totales, encadenamiento, SIF, instante
de generación y huella.

El **desglose** (`ConstruirDesglose`) emite un `<DetalleDesglose>` por banda de
IVA con impuesto `01` (IVA), clave de régimen `01` (general), calificación `S1`
(sujeta y no exenta), tipo impositivo, base imponible y cuota repercutida.

### 4.6 Envolver en SOAP y enviar

`EnvolverSoap(...)` mete el registro dentro de `RegFactuSistemaFacturacion` con
la cabecera del **obligado de emisión**. `EnviarSoapAeat(...)` hace el `POST`
HTTPS al endpoint correspondiente (PRE o PRO) usando un `THTTPClient` con
selección de **certificado de cliente** (`TSelectorCertificado`, que lo busca en
el almacén de Windows por número de serie o por titular).

| Entorno | Endpoint de envío SOAP                                                    |
|---------|--------------------------------------------------------------------------|
| PRE     | `https://prewww1.aeat.es/wlpl/TIKE-CONT/ws/SistemaFacturacion/VerifactuSOAP` |
| PRO     | `https://www1.agenciatributaria.gob.es/wlpl/TIKE-CONT/ws/SistemaFacturacion/VerifactuSOAP` |

### 4.7 Interpretar la respuesta y avanzar la cadena

`ExtraerEtiqueta(...)` lee de la respuesta `EstadoEnvio` / `EstadoRegistro`. Si
es `Correcto` (o `AceptadoConErrores`, o duplicado), el envío se da por bueno:
en producción se persiste el resultado y se **avanza la cadena** (la huella
recién calculada pasa a ser el nuevo último eslabón, y el contador `+1`).

---

## 5. El QR tributario

`ConstruirUrlQR(...)` arma la URL de cotejo que se imprime como QR en la factura,
con el formato fijado por la Orden HAC/1177/2024 (parámetros *percent-encoded*):

```
<base>?nif=<NIF>&numserie=<serie+numero>&fecha=<dd-mm-aaaa>&importe=<total 2 dec>
```

| Entorno | Base del QR                                                |
|---------|------------------------------------------------------------|
| PRE     | `https://prewww2.aeat.es/wlpl/TIKE-CONT/ValidarQR`         |
| PRO     | `https://www2.agenciatributaria.gob.es/wlpl/TIKE-CONT/ValidarQR` |

El **mismo NIF e identificador** (serie+número) deben viajar en el QR y en el
registro: por eso se normalizan con `NormalizarNif` y `ComponerNumSerieFactura`
en ambos sitios. (La generación del PNG del QR queda fuera del ejemplo; en
producción la hace `DelphiZXIngQRCode`.)

---

## 6. Mapeo con la base de datos

El record `TFacturaVerifactu` ↔ tabla `fza_facturas`:

| Campo del record         | Columna `fza_facturas`         |
|--------------------------|--------------------------------|
| `Serie`                  | `SERIE_FAC`                    |
| `Numero`                 | `NUMERO_FAC`                   |
| `Fecha`                  | `FECHA_FAC`                    |
| `Tipo`                   | `TIPO_FAC`                     |
| `NifEmisor`              | `NIF_EMPRESA_FAC`             |
| `NombreEmisor`           | `RAZON_SOCIAL_EMPRESA_FAC`    |
| `NifCliente`             | `NIF_CLIENTE_FAC`            |
| `NombreCliente`          | `RAZON_SOCIAL_CLIENTE_FAC`   |
| `Bandas[].Porcentaje`    | `PORCENTAJE_IVAN_FAC`, …      |
| `Bandas[].Base`          | `TOTAL_BASEI_IVAN_FAC`, …     |
| `Bandas[].Cuota`         | `TOTAL_IVAN_FAC`, …           |

El record `TEslabonCadena` ↔ tabla `fza_verifactu_cadena`:

| Campo del record | Columna `fza_verifactu_cadena` |
|------------------|--------------------------------|
| `Serie`          | `SERIE_FAC_VFCAD`             |
| `Numero`         | `NUMERO_FAC_VFCAD`            |
| `Fecha`          | `FECHA_FAC_VFCAD`            |
| `Huella`         | `HUELLA_VFCAD`              |

El script `facturas.sql` crea ambas tablas (idempotente) con datos de demo.

---

## 7. Cómo compilar y ejecutar

1. Abre `EnviarDatosVerifactu.dpr` en RAD Studio (Delphi) y compílalo, o desde
   línea de comandos:
   ```
   dcc32 EnviarDatosVerifactu.dpr
   ```
2. Copia `EnviarDatosVerifactu.ini` **junto al ejecutable** (o pásale su ruta
   como primer parámetro):
   ```
   EnviarDatosVerifactu.exe              (busca el .ini junto al .exe)
   EnviarDatosVerifactu.exe C:\ruta\mi.ini
   ```
3. Edita el `.ini` con tus datos. Con `[Envio] EnviarReal=0` (por defecto) el
   programa **solo construye e imprime** el registro; con `EnviarReal=1` lo
   remite de verdad a la AEAT (requiere certificado).

> La construcción del XML/huella/QR es multiplataforma; la parte de **envío** usa
> el almacén de certificados de **Windows**.

---

## 8. Demostración (salida real)

Con los datos del `.ini` de ejemplo y, **para que la huella sea reproducible**,
fijando `FechaHoraHusoGenRegistro = 2026-06-17T10:30:00+02:00`, el programa
imprime:

```
====================================================
 Veri*factu - Registro de ALTA  [PRE]
====================================================
NumSerieFactura : 2026.A1000154
Tipo factura    : F1
Cuota total     : 21.00
Importe total   : 121.00
Generado        : 2026-06-17T10:30:00+02:00
Huella SHA-256  : A2B3B84CA982E5AD37B0202311066436259E57C0B6CC01FC21CE355A148D8C80

--- URL de cotejo del QR ---
https://prewww2.aeat.es/wlpl/TIKE-CONT/ValidarQR?nif=45684134Q&numserie=2026.A1000154&fecha=17-06-2026&importe=121.00
```

La huella es el SHA-256 (hex mayúscula) de esta cadena exacta:

```
IDEmisorFactura=45684134Q&NumSerieFactura=2026.A1000154&FechaExpedicionFactura=17-06-2026&TipoFactura=F1&CuotaTotal=21.00&ImporteTotal=121.00&Huella=C6F200EC8EFEFE40F7E45994CC2AB320C145781F19F9614228D2525C60417D03&FechaHoraHusoGenRegistro=2026-06-17T10:30:00+02:00
```

Y el `RegistroAlta` generado (el código lo emite en una sola línea; aquí va
indentado para leerlo):

```xml
<sum1:RegistroAlta>
  <sum1:IDVersion>1.0</sum1:IDVersion>
  <sum1:IDFactura>
    <sum1:IDEmisorFactura>45684134Q</sum1:IDEmisorFactura>
    <sum1:NumSerieFactura>2026.A1000154</sum1:NumSerieFactura>
    <sum1:FechaExpedicionFactura>17-06-2026</sum1:FechaExpedicionFactura>
  </sum1:IDFactura>
  <sum1:NombreRazonEmisor>Alejandro Laorden Hidalgo</sum1:NombreRazonEmisor>
  <sum1:TipoFactura>F1</sum1:TipoFactura>
  <sum1:DescripcionOperacion>Venta de mercancia</sum1:DescripcionOperacion>
  <sum1:Destinatarios>
    <sum1:IDDestinatario>
      <sum1:NombreRazon>Cliente de Ejemplo, S.A.</sum1:NombreRazon>
      <sum1:NIF>12345678Z</sum1:NIF>
    </sum1:IDDestinatario>
  </sum1:Destinatarios>
  <sum1:Desglose>
    <sum1:DetalleDesglose>
      <sum1:Impuesto>01</sum1:Impuesto>
      <sum1:ClaveRegimen>01</sum1:ClaveRegimen>
      <sum1:CalificacionOperacion>S1</sum1:CalificacionOperacion>
      <sum1:TipoImpositivo>21.00</sum1:TipoImpositivo>
      <sum1:BaseImponibleOimporteNoSujeto>100.00</sum1:BaseImponibleOimporteNoSujeto>
      <sum1:CuotaRepercutida>21.00</sum1:CuotaRepercutida>
    </sum1:DetalleDesglose>
  </sum1:Desglose>
  <sum1:CuotaTotal>21.00</sum1:CuotaTotal>
  <sum1:ImporteTotal>121.00</sum1:ImporteTotal>
  <sum1:Encadenamiento>
    <sum1:RegistroAnterior>
      <sum1:IDEmisorFactura>45684134Q</sum1:IDEmisorFactura>
      <sum1:NumSerieFactura>2026.A1000153</sum1:NumSerieFactura>
      <sum1:FechaExpedicionFactura>13-06-2026</sum1:FechaExpedicionFactura>
      <sum1:Huella>C6F200EC8EFEFE40F7E45994CC2AB320C145781F19F9614228D2525C60417D03</sum1:Huella>
    </sum1:RegistroAnterior>
  </sum1:Encadenamiento>
  <sum1:SistemaInformatico>
    <sum1:NombreRazon>Alejandro Laorden Hidalgo</sum1:NombreRazon>
    <sum1:NIF>45684134Q</sum1:NIF>
    <sum1:NombreSistemaInformatico>Factuzam</sum1:NombreSistemaInformatico>
    <sum1:IdSistemaInformatico>FZ</sum1:IdSistemaInformatico>
    <sum1:Version>1.0.0</sum1:Version>
    <sum1:NumeroInstalacion>1</sum1:NumeroInstalacion>
    <sum1:TipoUsoPosibleSoloVerifactu>N</sum1:TipoUsoPosibleSoloVerifactu>
    <sum1:TipoUsoPosibleMultiOT>S</sum1:TipoUsoPosibleMultiOT>
    <sum1:IndicadorMultiplesOT>N</sum1:IndicadorMultiplesOT>
  </sum1:SistemaInformatico>
  <sum1:FechaHoraHusoGenRegistro>2026-06-17T10:30:00+02:00</sum1:FechaHoraHusoGenRegistro>
  <sum1:TipoHuella>01</sum1:TipoHuella>
  <sum1:Huella>A2B3B84CA982E5AD37B0202311066436259E57C0B6CC01FC21CE355A148D8C80</sum1:Huella>
</sum1:RegistroAlta>
```

---

## 9. Alcance y limitaciones

El ejemplo cubre el caso **común**: alta de factura completa (F1), simplificada
(F2) o rectificativa por sustitución (R1) con IVA repercutido. **No** incluye, a
propósito, para mantenerlo legible:

- Operaciones **exentas** o no sujetas (E1…E6, N1/N2).
- **Recargo de equivalencia**.
- Clientes **extranjeros** (identificación por `IDOtro` en vez de NIF).
- Distinción fina **R1/R5** según el tipo de la factura original.
- **Firma XAdES** del registro (obligatoria en la modalidad No Veri\*factu).
- Registro de **anulación**.

Todo eso está resuelto en el subsistema real `inLibVerifactuEnvio.pas` /
`inLibVerifactu.pas`.

---

## 10. Avisos / entorno de pruebas

- Prueba **siempre primero en PRE** (`[Envio] Entorno=PRE`).
- El envío real (`EnviarReal=1`) exige un **certificado válido** instalado en el
  almacén de Windows y un **NIF dado de alta** en el entorno de pruebas de la
  AEAT.
- Los datos del `.ini` (NIF `45684134Q`, cliente `12345678Z`, huella anterior…)
  son de **ejemplo**: sustitúyelos por los tuyos.

---

## 11. Referencias

- Real Decreto 1007/2023 (Reglamento de sistemas informáticos de facturación).
- Orden HAC/1177/2024 (especificaciones técnicas y QR tributario).
- Portal de la AEAT: *Sistemas Informáticos de Facturación y Veri\*factu*.
- Código de producción: `src/verifactu/inLibVerifactuEnvio.pas`,
  `src/verifactu/inLibVerifactu.pas`.
