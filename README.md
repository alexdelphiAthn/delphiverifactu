# Delphi Verifactu

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

**Librerías nativas en Delphi para la generación, firma electrónica (XAdES), comunicación y validación de registros de facturación** adaptados a las normativas fiscales españolas (Real Decreto 1007/2023: Veri*Factu, Sistemas Informáticos de Facturación No Veri*Factu, Facturae y TicketBAI).

Este proyecto proporciona una base sólida para integrar normativas fiscales complejas en aplicaciones Delphi. Su filosofía central es mantener una arquitectura limpia: la API pública trabaja con *records* y XML puro, estando completamente desacoplada de la base de datos o de componentes específicos de acceso a datos.

---

## 🚀 Características Principales

* **Ciclo de Vida Completo Veri*Factu:** Generación de la estructura XML de alta, cálculo de la huella SHA-256 encadenada, composición de la URL de cotejo del código QR y envoltura en un sobre SOAP para su envío[cite: 3].
* **Generación del Código QR Tributario:** Renderizado de la imagen del QR (nivel de corrección **M** y zona de silencio según la AEAT) a partir de la URL de cotejo, mediante un *port* nativo de ZXing. **No requiere** librerías de imagen externas.
* **Firma XAdES Enveloped Nativa:** Utiliza la API nativa de Windows y el almacén de certificados del sistema operativo. **No requiere** la distribución de DLLs adicionales (como OpenSSL), ni la ejecución de procesos externos.
* **Comunicaciones Directas con la AEAT:** Envío HTTPS nativo a los endpoints oficiales de la Agencia Tributaria extrayendo y utilizando los certificados directamente desde el almacén de Windows[cite: 3].
* **Validación Estricta:** Verificación local y rigurosa de los formatos y dígitos de control de NIF, NIE y CIF españoles.

## ⚙️ Requisitos del Sistema

Para compilar y utilizar estas librerías necesitas:

* **Entorno:** Delphi moderno (con soporte para *namespaces* de unidad).
* **Sistema Operativo:** Windows (necesario para el uso de las librerías criptográficas de bajo nivel y la gestión de certificados TLS).
* **Certificados:** Un certificado digital válido instalado en el *almacén personal de certificados de Windows* para firmar o autenticar las peticiones SOAP.

## 📂 Estructura y Módulos Disponibles

El código de producción está separado de los ejemplos. Entre los módulos base destacan:

* `Fiscal.Xades.pas`: Motor de firma digital XAdES Enveloped.
* `Fiscal.DocumentoFiscal.pas`: Utilidades de validación de identificadores fiscales.
* `Fiscal.EnvioVerifactu.pas`: Motor integral para construir el registro XML de alta de Veri*Factu, calcular hashes, montar la URL del QR y ejecutar la petición SOAP[cite: 3].
* `Fiscal.NoVerifactu.pas`: Registros del modo **NO VERI\*FACTU**: libro de eventos del sistema (EventosSIF, encadenado por huella) y registro de facturación local firmado, con exportación a XML. Reutiliza `Fiscal.Xades` para la firma obligatoria.
* `Fiscal.RelojFiscal.pas`: Control del reloj fiscal (margen legal de un minuto) que exige la Orden HAC/1177/2024 antes de fechar registros NO VERI\*FACTU.
* `Fiscal.VerificarNoVerifactu.pas`: Verificación **local** de los ficheros NO VERI\*FACTU exportados — estructura, cadena de huellas, coherencia de huella/firma y perfil XAdES (política AGE). Sin red ni procesos externos.
* `DelphiZXIngQRCode.pas`: *Port* a Delphi de ZXing QRCode (Apache 2.0), adaptado para Veri*Factu (nivel de corrección **M** y zona de silencio por defecto). Convierte la URL de cotejo en la matriz del código QR.

## 💡 Ejemplos de Uso

En el directorio [`examples/`](./examples) encontrarás proyectos de consola listos para compilar que ilustran el uso de la API:

* **`01-xades`**: Demuestra cómo aplicar una firma a un XML cumpliendo con la política estricta de Facturae.
* **`02-documento-fiscal`**: Utilidad para validar el formato de NIF/NIE/CIF desde la línea de comandos.
* **`03-noverifactu-firma`**: Carga un XML en formato *NO VERI\*FACTU* y le aplica la firma XAdES requerida por la normativa.
* **`04-envio-verifactu`**: Ejemplo didáctico de integración completa. Lee datos desde un archivo `.ini` (NIF del productor, factura, eslabón anterior de la cadena, entorno PRE/PRO)[cite: 1, 2], construye el registro de ALTA Veri*factu, calcula su huella SHA-256[cite: 1, 3] y remite de manera opcional el registro SOAP a la AEAT[cite: 1].
* **`05-generar-qr`**: Toma la URL de cotejo de una factura y genera la imagen del **código QR tributario** (nivel de corrección M, zona de silencio), volcándola a un *bitmap* listo para incrustar en el informe de la factura.
* **`06-reloj-fiscal`**: Comprueba el reloj del sistema y **deniega** si se desfasa más de un minuto. El desfase se puede simular desde un `.ini` para probarlo sin conexión.
* **`07-noverifactu-eventos`**: Registra el **libro de eventos** NO VERI\*FACTU (`abrir programa`, `factura creada`, `cambio de parámetros`, `cerrar programa`), encadenado por huella y firmado con XAdES, y lo exporta a XML.
* **`08-noverifactu-facturas`**: Ejemplo integral. **Lee facturas desde un XML** (sin base de datos), comprueba el reloj, construye y firma cada `RegistroAlta`, encadena las huellas y escribe los dos ficheros legales (`_facturacion.xml` y `_eventos.xml`).
* **`09-verificar-noverifactu`**: **Verifica** los ficheros que generan `07`/`08` — estructura, cadena de huellas, coherencia de huella/firma y perfil XAdES — y escribe un informe. Es el complemento del generador: genera con `07`/`08`, verifica con `09`.

> **Compilación de los ejemplos:** son proyectos de consola autocontenidos. Ábrelos en RAD Studio o compílalos con `dcc32 <Programa>.dpr`. Los ejemplos `01`, `03` (firma), `04` (envío real) y la firma de `07`/`08` usan el almacén de certificados de **Windows**; los ejemplos `08` y `09` leen XML con `Xml.XMLDoc` (MSXML en Windows); el `05` usa `Vcl.Graphics`. La construcción de XML, huellas, URLs y el control de reloj (`06`) es multiplataforma; los ejemplos `07` y `08` funcionan también en modo demo (huella SHA-256, sin firma) si no indicas certificado.

## 📚 Documentación

Cada bloque funcional cuenta con una guía detallada en [`docs/`](./docs):

* [`docs/noverifactu.md`](./docs/noverifactu.md): **guía del modo NO VERI\*FACTU** explicado sin liarse — qué es, en qué se diferencia de Veri\*Factu, los dos libros (eventos y facturación), la firma obligatoria y los errores típicos.
* [`docs/reloj_fiscal.md`](./docs/reloj_fiscal.md): control del reloj fiscal (margen de un minuto) antes de fechar registros NO VERI\*FACTU.
* [`docs/verificar_noverifactu.md`](./docs/verificar_noverifactu.md): verificador local de los ficheros NO VERI\*FACTU — qué comprueba (cadena, huellas, perfil XAdES) y qué no (la firma RSA va a VALIDe).
* [`docs/envio_verifactu.md`](./docs/envio_verifactu.md): explicación paso a paso del registro de ALTA Veri*Factu — huella encadenada, URL del QR, sobre SOAP y envío a la AEAT.
* [`docs/generar_qr.md`](./docs/generar_qr.md): generación del código QR tributario a partir de la URL de cotejo (API de `DelphiZXIngQRCode`, nivel M, tamaño de impresión).
* [`docs/xades.md`](./docs/xades.md): firma XAdES Enveloped para Facturae y NO VERI*FACTU.
* [`docs/plan_extraccion.md`](./docs/plan_extraccion.md): hoja de extracción y orden de publicación de los módulos.

## 🗺️ Hoja de Ruta (Roadmap)

- [x] Firma XAdES nativa desde Windows.
- [x] Validación algorítmica de NIF/NIE/CIF.
- [x] Generación de estructuras XML (Registros de Alta) para sistemas Veri*Factu[cite: 3].
- [x] Generación de URL de cotejo para Códigos QR[cite: 3].
- [x] Cálculo de huella encadenada (SHA-256) según especificaciones[cite: 3].
- [x] Integración de envíos SOAP TLS a los servicios web de la AEAT[cite: 3].
- [x] Renderizado de la imagen del Código QR a partir de la URL de cotejo (ejemplo `05-generar-qr`).
- [x] Generación de estructuras XML para registros No Veri*Factu (libro de eventos y registro de facturación firmados, ejemplos `07` y `08`).
- [x] Control del reloj fiscal con margen legal de un minuto (ejemplo `06-reloj-fiscal`).
- [x] Verificación local de los ficheros NO VERI*Factu exportados — estructura, cadena de huellas y perfil de firma (ejemplo `09-verificar-noverifactu`).
- [ ] Representación gráfica estandarizada de Códigos QR en informes impresos (leyenda y tamaño normalizados).

## 📄 Licencia y Componentes de Terceros

El código propio de este repositorio se publica bajo licencia **MIT** (ver [`LICENSE`](./LICENSE)).

Se incluye además `DelphiZXIngQRCode.pas`, un *port* a Delphi de **ZXing QRCode** (Debenu Pty Ltd, sobre el proyecto ZXing de Google), distribuido bajo licencia **Apache 2.0**. Consulta [`NOTICE.md`](./NOTICE.md) para los avisos de atribución y las advertencias sobre datos sensibles.

## ⚠️ Estado del Proyecto y Aviso Legal

Este repositorio se encuentra en evolución continua. Las unidades aquí publicadas son funcionales, pero el cumplimiento fiscal integral de un software de facturación depende de cómo se implementen en la aplicación final (incluyendo la persistencia inmutable, el control del reloj, las validaciones de negocio previas y las rutinas de exportación).

> **Aviso Legal:** El código proporcionado tiene fines de desarrollo y **no sustituye** el asesoramiento fiscal profesional ni constituye una homologación oficial por parte de la Agencia Tributaria (AEAT), Facturae, FACe o cualquier otra administración pública. Es responsabilidad exclusiva del desarrollador garantizar que el software final cumple con todas las especificaciones de la normativa vigente.
