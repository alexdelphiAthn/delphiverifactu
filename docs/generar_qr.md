# Generación del QR tributario Veri\*factu — explicación del ejemplo

> **Autor:** Alejandro Laorden Hidalgo · alejandro.laorden@protonmail.com


Este documento explica el ejemplo de **generación del código QR tributario** que
encontrarás en [`examples/05-generar-qr/`](../examples/05-generar-qr). El ejemplo
toma la **URL de cotejo** de una factura (la que produce
`Fiscal.EnvioVerifactu`) y la convierte en una imagen QR lista para imprimir,
usando la librería `DelphiZXIngQRCode`.

---

## 1. Qué es el QR tributario

La normativa Veri\*factu obliga a imprimir en **cada factura** un código QR que
permite a cualquier receptor **cotejar** la factura contra la sede electrónica de
la AEAT. El marco normativo:

- **Real Decreto 1007/2023** — Reglamento de los sistemas informáticos de
  facturación.
- **Orden HAC/1177/2024** — especificaciones técnicas: estructura de los
  registros, huella SHA-256 y **formato y características del QR tributario**.

El QR **no** contiene la factura: contiene únicamente una **URL de cotejo** con
cuatro datos (NIF del emisor, identificador de la factura, fecha e importe
total). Al leerlo, el cliente llega al servicio de validación de la AEAT, que
confirma si esa factura fue remitida (Veri\*factu) o, en el caso de un sistema No
Veri\*factu, si los datos del QR son coherentes con la factura.

---

## 2. Qué hace este ejemplo

A partir de una URL de cotejo ya construida, el programa de consola:

1. Configura un objeto `TDelphiZXingQRCode` con la URL, la codificación, la zona
   de silencio y el **nivel de corrección de errores M** que exige la AEAT.
2. Vuelca la matriz de módulos del QR sobre un `TBitmap` (VCL), aplicando una
   escala en píxeles por módulo.
3. Guarda la imagen en disco (`.bmp`) lista para incrustarla en el informe de la
   factura.

> El ejemplo **no** envía nada a la AEAT ni calcula huellas: parte de una URL ya
> compuesta. La construcción de esa URL se explica en
> [`envio_verifactu.md`](./envio_verifactu.md) (apartado 5).

---

## 3. Estructura de ficheros

```
examples/05-generar-qr/
└── GenerarQRVerifactu.dpr   ← programa de consola de la demostración

src/
└── DelphiZXIngQRCode.pas    ← port a Delphi de ZXing QRCode (Apache 2.0)

docs/
└── generar_qr.md            ← este documento
```

---

## 4. De la URL de cotejo al QR

El contenido que se codifica en el QR es **exactamente** la URL que devuelve
`ConstruirUrlQR(...)` en `Fiscal.EnvioVerifactu`, accesible también como el campo
`UrlQR` del record `TRegistroVerifactu` que retorna `PrepararRegistroAlta(...)`.
Su formato lo fija la Orden HAC/1177/2024 (parámetros *percent-encoded*):

```
<base>?nif=<NIF>&numserie=<serie+numero>&fecha=<dd-mm-aaaa>&importe=<total 2 dec>
```

| Entorno | Base del QR                                                      |
|---------|-----------------------------------------------------------------|
| PRE     | `https://prewww2.aeat.es/wlpl/TIKE-CONT/ValidarQR`              |
| PRO     | `https://www2.agenciatributaria.gob.es/wlpl/TIKE-CONT/ValidarQR` |

Ejemplo (entorno PRE) usado por el programa:

```
https://prewww2.aeat.es/wlpl/TIKE-CONT/ValidarQR?nif=12345678Z&numserie=2026.A1000154&fecha=17-06-2026&importe=121.00
```

> ⚠️ El **mismo NIF e identificador** (serie+número) que viajan en el registro de
> alta deben viajar en el QR. Por eso, en producción, la URL se obtiene de
> `Fiscal.EnvioVerifactu` y **no** se vuelve a teclear a mano.

---

## 5. La librería `DelphiZXIngQRCode`

`src/DelphiZXIngQRCode.pas` es un port a Delphi de **ZXing QRCode** (por Debenu
Pty Ltd, sobre el proyecto original ZXing de Google, licencia **Apache 2.0**).
La copia incluida en este repositorio está **adaptada para Veri\*factu**: el
constructor fija como valores por defecto el nivel de corrección **M** y una zona
de silencio de **4 módulos**, en lugar de los del port original.

La clase `TDelphiZXingQRCode` expone una API muy sencilla:

| Miembro                  | Tipo / valores                                            | Papel    |
|--------------------------|-----------------------------------------------------------|----------|
| `Data`                   | `WideString`                                              | entrada  |
| `Encoding`               | `qrAuto`, `qrNumeric`, `qrAlphanumeric`, `qrISO88591`, `qrUTF8NoBOM`, `qrUTF8BOM` | entrada |
| `ErrorCorrectionLevel`   | `qreL` (7%), `qreM` (15%), `qreQ` (25%), `qreH` (30%)      | entrada  |
| `QuietZone`              | `Integer` (módulos de margen)                             | entrada  |
| `Rows`, `Columns`        | `Integer`                                                | salida   |
| `IsBlack[Row, Column]`   | `Boolean`                                                | salida   |

Al asignar `Data` (o cambiar cualquier propiedad de entrada) la librería
**recalcula** la matriz. Después basta con recorrer `Rows` × `Columns` y consultar
`IsBlack[Fila, Columna]` para saber qué módulos pintar de negro.

> **`Rows` y `Columns` ya incluyen la zona de silencio** (`QuietZone` módulos a
> cada lado). En ese margen `IsBlack` devuelve siempre `False` (blanco), de modo
> que al recorrer toda la matriz se obtiene el símbolo **con su margen**, sin
> tener que añadirlo aparte.

---

## 6. El flujo del ejemplo paso a paso

Todo el trabajo lo hace el procedimiento `GenerarBitmapQR(ATextoUrl,
ARutaDestino)`.

### 6.1 Configurar el QR

```pascal
oQRCode.Data := ATextoUrl;          // la URL de cotejo de la AEAT
oQRCode.Encoding := qrUTF8NoBOM;    // UTF-8 sin BOM
oQRCode.QuietZone := 4;             // margen de 4 módulos (obligatorio)
oQRCode.ErrorCorrectionLevel := qreM; // nivel M (15%), exigido por Veri*factu
```

La URL de cotejo es ASCII (va *percent-encoded*), así que `qrUTF8NoBOM` produce
los mismos bytes que ASCII y evita contaminar el contenido con una marca BOM.

### 6.2 Preparar el `TBitmap`

```pascal
Escala := 4;                        // 4 píxeles por módulo del QR
oBitmap.PixelFormat := pf24bit;
oBitmap.Width  := oQRCode.Columns * Escala;
oBitmap.Height := oQRCode.Rows * Escala;

oBitmap.Canvas.Brush.Color := clWhite;
oBitmap.Canvas.FillRect(Rect(0, 0, oBitmap.Width, oBitmap.Height));
```

Se pinta primero todo de blanco (fondo + zona de silencio).

### 6.3 Dibujar los módulos negros

```pascal
oBitmap.Canvas.Brush.Color := clBlack;
for Fila := 0 to oQRCode.Rows - 1 do
  for Columna := 0 to oQRCode.Columns - 1 do
    if oQRCode.IsBlack[Fila, Columna] then
      oBitmap.Canvas.FillRect(Rect(
        Columna * Escala, Fila * Escala,
        (Columna + 1) * Escala, (Fila + 1) * Escala));
```

Cada módulo se dibuja como un cuadrado de `Escala`×`Escala` píxeles.

### 6.4 Guardar la imagen

```pascal
oBitmap.SaveToFile(ARutaDestino);   // p. ej. QR_Verifactu_NivelM.bmp
```

---

## 7. Características del QR según la AEAT

| Parámetro                  | Valor exigido / recomendado                | En el ejemplo                 |
|----------------------------|--------------------------------------------|-------------------------------|
| Nivel de corrección        | **M** (15%)                                | `ErrorCorrectionLevel := qreM` |
| Zona de silencio (margen)  | ≥ 4 módulos en blanco                      | `QuietZone := 4`              |
| Contenido                  | URL de cotejo (apartado 4)                 | `Data := <URL>`               |
| Tamaño impreso             | entre **30×30 mm y 40×40 mm**              | depende de `Escala` y el DPI  |

Además, la factura debe llevar **junto al QR** una leyenda identificativa. Si el
registro se ha remitido a la AEAT, el texto es **«VERI\*FACTU»** (o «Factura
verificable en la sede electrónica de la AEAT. VERI\*FACTU»); si es un sistema No
Veri\*factu, la leyenda es **«Factura verificable en la sede electrónica de la
AEAT»** sin la marca *VERI\*FACTU*. El ejemplo genera **solo el QR**: la leyenda
la añade la plantilla del informe.

> Comprueba siempre los valores exactos contra el texto vigente de la Orden
> HAC/1177/2024; las dimensiones y leyendas pueden afinarse en sucesivas
> resoluciones.

---

## 8. Tamaño de impresión (cómo elegir la escala)

El lado del bitmap, en píxeles, es:

```
lado_px = (módulos del símbolo + 2 × QuietZone) × Escala
        = Columns × Escala            (Columns ya incluye la zona de silencio)
```

Para imprimir el QR a un tamaño físico `S` (mm) a una resolución de `D` puntos por
pulgada (DPI), el lado en píxeles debe ser `lado_px = S / 25.4 × D`. Despejando la
escala:

```
Escala ≈ (S / 25.4 × D) / Columns
```

**Ejemplo:** un QR de versión baja con `Columns = 33` (25 módulos de datos + 2×4
de margen), impreso a `S = 35 mm` y `D = 300 DPI`:

```
lado_px = 35 / 25.4 × 300 ≈ 413 px
Escala  ≈ 413 / 33 ≈ 12 px/módulo
```

El `Escala := 4` del ejemplo está pensado para **vista en pantalla**; para
impresión a 300 DPI conviene subirlo (de ~10 a ~14 px/módulo) y dejar que el motor
de informes escale la imagen al recuadro de 30–40 mm reservado en la plantilla.

> Genera el bitmap con **margen de píxeles suficiente** (la zona de silencio ya va
> incluida) y **no** lo recortes: sin margen blanco, muchos lectores no enfocan el
> QR.

---

## 9. Cómo compilar y ejecutar

1. Abre `GenerarQRVerifactu.dpr` en RAD Studio (Delphi) y compílalo, o desde línea
   de comandos:
   ```
   dcc32 GenerarQRVerifactu.dpr
   ```
2. Ejecútalo. Generará el fichero `QR_Verifactu_NivelM.bmp` en el directorio de
   trabajo y mostrará la URL codificada:
   ```
   Generando bitmap del QR Nivel M para la URL:
   https://prewww2.aeat.es/wlpl/TIKE-CONT/ValidarQR?nif=12345678Z&numserie=2026.A1000154&fecha=17-06-2026&importe=121.00
   Codigo QR guardado con exito en: QR_Verifactu_NivelM.bmp
   ```

> Este ejemplo usa `Vcl.Graphics` (`TBitmap`), por lo que requiere **Windows**.
> La *construcción* del QR (`TDelphiZXingQRCode`) es independiente de la VCL; solo
> el **renderizado** a bitmap depende de ella. Para servidores o multiplataforma,
> sustituye el volcado a `TBitmap` por tu propio renderizador (FMX, PNG, SVG…)
> recorriendo igualmente `IsBlack[Fila, Columna]`.

---

## 10. Integración de extremo a extremo

En una aplicación real, los ejemplos 04 y 05 se encadenan:

```pascal
// 1) Construir el registro de alta (huella + XML + SOAP + URL del QR)
oRegistro := PrepararRegistroAlta(oFactura, oAnterior, sSistemaInformatico,
                                  {AEntornoPro=} False);

// 2) Pintar el QR a partir de la URL de cotejo del registro
GenerarBitmapQR(oRegistro.UrlQR, 'QR_' + oFactura.Numero + '.bmp');
```

Así, el **mismo** NIF, identificador, fecha e importe que se han firmado por
huella y remitido a la AEAT son los que se imprimen en el QR.

---

## 11. Alcance y limitaciones

El ejemplo se centra en lo esencial; **no** incluye, a propósito:

- **Formato PNG/SVG**: guarda en `.bmp`. Para incrustar en PDF/HTML conviene PNG;
  reemplaza `SaveToFile` por tu codificador o un `TWICImage`/librería de imagen.
- **La leyenda de texto** («VERI\*FACTU» / «Factura verificable…»): la añade la
  plantilla del informe, no la librería.
- **Cálculo automático de la escala** para un tamaño físico: aquí es un valor fijo
  (apartado 8 explica cómo calcularlo).
- **Construcción de la URL**: se parte de una URL ya formada; obténla de
  `Fiscal.EnvioVerifactu` para garantizar que coincide con el registro.

---

## 12. Referencias

- Real Decreto 1007/2023 (Reglamento de sistemas informáticos de facturación).
- Orden HAC/1177/2024 (especificaciones técnicas y QR tributario).
- Portal de la AEAT: *Sistemas Informáticos de Facturación y Veri\*factu*.
- Proyecto ZXing (`https://github.com/zxing/zxing`) y port a Delphi de Debenu
  (licencia Apache 2.0) — ver [`NOTICE.md`](../NOTICE.md).
- Documento relacionado: [`envio_verifactu.md`](./envio_verifactu.md) (construcción
  de la URL de cotejo y del registro de alta).
