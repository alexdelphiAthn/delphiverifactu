# Modo NO VERI\*FACTU explicado sin liarse

> **Lee esto primero si te confunde el nombre.** "NO VERI\*FACTU" **no** quiere
> decir "sin sistema fiscal" ni "me salto la ley". Es un modo de facturación
> **igual de legal** que Veri\*Factu; la única diferencia es que **no envía cada
> factura a la AEAT en el momento**. A cambio, guarda registros locales
> **encadenados y firmados** que la Agencia Tributaria puede inspeccionar
> después.

El Real Decreto 1007/2023 permite a un sistema de facturación (SIF) funcionar de
dos formas:

- **Veri\*Factu**: cada registro de factura se **remite a la AEAT** según se
  emite.
- **NO VERI\*FACTU**: el registro **no se remite**, pero el sistema debe
  conservarlo de forma **inalterable, encadenada y firmada electrónicamente**, y
  debe poder **exportarlo** cuando se lo pidan.

Este repositorio incluye ejemplos didácticos de las dos vías. Esta guía cubre la
segunda.

---

## Los tres modos de un vistazo

| Modo | ¿Envía a la AEAT? | ¿Crea registro fiscal? | ¿Firma XAdES? | ¿Control de reloj? |
|------|:-----------------:|:----------------------:|:-------------:|:------------------:|
| `SIN` | No | No (solo demo/transitorio) | No | No |
| `VERIFACTU` | **Sí**, cada registro | Sí, con respuesta de la AEAT | Opcional* | Recomendado |
| `NO_VERIFACTU` | **No** | Sí, **local encadenado** | **Sí, obligatoria** | **Sí, obligatorio** |

\* En Veri\*Factu la integridad la garantiza la propia AEAT al recibir el envío.
En NO VERI\*FACTU **no hay envío**, así que la integridad la garantizan **la
huella encadenada + la firma electrónica** del propio sistema. Por eso en
NO VERI\*FACTU la firma es **imprescindible**.

> Regla mental rápida: **Veri\*Factu confía en la AEAT; NO VERI\*FACTU confía en
> tu firma.**

---

## Qué tiene que hacer un sistema NO VERI\*FACTU

Cuando se emite (o se anula) una factura en modo `NO_VERIFACTU`:

1. **Comprobar el reloj** del sistema contra una hora fiable. Si la diferencia
   supera **un minuto**, se **deniega** la emisión (ver
   [`reloj_fiscal.md`](./reloj_fiscal.md)).
2. **Construir el registro de facturación** (`RegistroAlta` o
   `RegistroAnulacion`): es el **mismo XML** que en Veri\*Factu.
3. **Calcular su huella SHA-256** y **encadenarla** con la huella del registro
   anterior del mismo emisor.
4. **Firmar el XML con XAdES** (política AGE) usando el certificado de la
   empresa.
5. **Guardar** el registro firmado en local (en estos ejemplos, en memoria; en
   una app real, en tu almacenamiento inalterable).
6. **Registrar un evento** en el libro de eventos.

Y en paralelo, durante toda la vida del programa, se lleva un **libro de
eventos** del sistema (arranque, cierre, cambios de configuración,
exportaciones, incidencias), también **encadenado y firmado**.

Cuando alguien lo pide, se **exportan dos ficheros XML**:

- `*_facturacion.xml` → todos los registros de factura firmados.
- `*_eventos.xml` → todos los eventos firmados.

---

## Los dos libros que genera

### 1. Registro de facturación

Cada factura produce un `RegistroAlta` (o `RegistroAnulacion`) idéntico al de
Veri\*Factu, pero **firmado y guardado en local en vez de enviado**. La firma
**envuelve el propio `RegistroAlta`**.

### 2. Registro de eventos (libro de eventos)

El sistema deja constancia de lo que le pasa. El catálogo que usan los ejemplos
sigue los códigos de evento de la AEAT (`EventosSIF`):

| Constante (`Fiscal.NoVerifactu`) | Código AEAT | Ejemplo de uso |
|----------------------------------|:-----------:|----------------|
| `cEventoInicio` | `01` | "abrir programa" (arranque) |
| `cEventoFin` | `02` | "cerrar programa" (cierre) |
| `cEventoCambioConfig` | `03` | "cambio de parámetros" |
| `cEventoExportFact` | `08` | exportación del registro de facturación |
| `cEventoExportEventos` | `09` | exportación del registro de eventos |
| `cEventoOtros` | `90` | evento voluntario ("factura creada"), incidencias |

Cada evento encadena con el anterior por huella: `HashAnterior → HashPropio`. El
primero arranca con 64 ceros.

---

## La firma es obligatoria (y se hace con `Fiscal.Xades`)

En NO VERI\*FACTU **no se hace** un cálculo casero de firma: se reutiliza el
motor XAdES del repositorio. Perfil exigido (según
`EspecTecGenerFirmaElectRfact.pdf` de la AEAT):

- **XAdES Enveloped**, clase **EPES**.
- Se firma el nodo `RegistroAlta`, `RegistroAnulacion` o `RegistroEvento/Evento`
  — **nunca** los nodos de transporte ni el contenedor de exportación.
- `SignatureMethod`: **RSA-SHA256**.
- Digest del registro y de `SignedProperties`: **SHA-256**.
- Política de firma **AGE**: `urn:oid:2.16.724.1.3.1.1.2.1.9`.
- Hash de la política: **SHA-1**, `G7roucf600+f03r/o0bAOQ6WAs0=`.
- URL de política:
  `https://sede.administracion.gob.es/politica_de_firma_anexo_1.pdf`.
- **No** se exige sello de tiempo TSA.

Todo eso ya lo configura `OpcionesXadesNoVerifactu` en `Fiscal.Xades`. Para
eventos, además, la firma se inserta dentro del nodo `sf:Evento`:

```pascal
oOpciones := OpcionesXadesNoVerifactu('FZ-EVENTO-' + sHuella);
oOpciones.NombreNodoInsercionFirma := 'sf:Evento';
```

> **El contenedor de exportación NO se firma.** La garantía legal está en cada
> `RegistroAlta`, `RegistroAnulacion` y `RegistroEvento` individual. Firmar
> también el contenedor `*_facturacion.xml` / `*_eventos.xml` duplicaría una
> garantía que la AEAT no pide.

### Modo demo (sin certificado)

Si **no** pasas certificado, las funciones generan el XML con la **huella
SHA-256** como rastro técnico, **sin** bloque `<ds:Signature>`. Sirve para
aprender y para inspeccionar la estructura **offline**, pero **no** equivale a
firma electrónica avanzada y **no** es un cierre fiscal válido. En una app real
esto correspondería a `appVerifactuFirmaCertificado = False`, que **solo** se
admite en modo `SIN`.

Si la firma se solicita pero el certificado falta, está caducado o el usuario la
cancela, **no se hace fallback a SHA-256**: la operación falla y no queda registro
firmado. Eso es intencionado: un registro NO VERI\*FACTU sin firma no es válido.

---

## Los ejemplos

Todos son proyectos de consola autocontenidos, **sin base de datos**: leen de
XML o `.ini` y escriben XML. La firma XAdES usa el almacén de certificados de
**Windows**; el resto es portable.

### `06-reloj-fiscal` — Comprobar el reloj

Comprueba el reloj y **deniega** si se desfasa más de un minuto. Se prueba sin
conexión simulando el desfase desde el `.ini`:

```ini
[Reloj]
MargenSegundos          = 60
DesfaseSimuladoSegundos = 90   ; pon 0 para PERMITIR, 90 para DENEGAR
ComprobarRed            = 0
```

```text
ComprobarRelojFiscal.exe
```

### `07-noverifactu-eventos` — Libro de eventos

Registra cuatro eventos encadenados ("abrir programa", "factura creada",
"cambio de parámetros", "cerrar programa") y los vuelca a XML.

```text
:: Modo demo (sin firma):
RegistrarEventosNoVerifactu.exe eventos.xml

:: Modo legal (firma XAdES con certificado de Windows):
RegistrarEventosNoVerifactu.exe eventos.xml 1a2b3c... "NOMBRE APELLIDOS"
```

### `08-noverifactu-facturas` — Facturas + eventos (integral)

Lee facturas de `facturas.xml`, comprueba el reloj, construye y firma cada
`RegistroAlta`, encadena las huellas, lleva el libro de eventos y escribe los
dos ficheros legales.

```text
RegistrarFacturasNoVerifactu.exe facturas.xml noverifactu

:: genera:
::   noverifactu_facturacion.xml
::   noverifactu_eventos.xml
```

Para verlo **denegar** por reloj, edita en `facturas.xml`:

```xml
<FacturasNoVerifactu comprobarReloj="1" desfaseSimuladoSegundos="90">
```

---

## Mapa de unidades

| Unidad | Para qué |
|--------|----------|
| `Fiscal.RelojFiscal` | Control de hora (margen de un minuto). |
| `Fiscal.NoVerifactu` | Libro de eventos y registro de facturación NO VERI\*FACTU. |
| `Fiscal.EnvioVerifactu` | Construcción del `RegistroAlta` y la huella (compartido con Veri\*Factu). |
| `Fiscal.Xades` | Firma XAdES Enveloped (política AGE). |

---

## Errores típicos (y cómo no caer en ellos)

- **"NO VERI\*FACTU es no tener nada".** Falso: es **más** exigente en local que
  Veri\*Factu (firma + cadena + reloj obligatorios).
- **"Firmo el fichero de exportación entero".** No: se firma **cada registro**,
  no el contenedor.
- **"Si no hay certificado, sigo con SHA-256".** No en modo legal: sin firma, la
  operación se **deniega**.
- **"El reloj da igual".** No: más de un minuto de desfase **bloquea** la
  emisión.
- **"Valido el `*_eventos.xml` en VALIDe".** No: a un validador externo se le da
  un **registro individual firmado** extraído de `RegistroXmlFirmado`, no el
  contenedor.

---

## Aviso legal

Código con fines **didácticos**. No sustituye al asesoramiento fiscal ni
constituye homologación oficial de la AEAT. El cumplimiento real depende de cómo
la aplicación final implemente la **persistencia inalterable**, el control del
reloj, las validaciones de negocio y las rutinas de exportación. Valida siempre
los XML contra los XSD oficiales vigentes.
