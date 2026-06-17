# Delphi Verifactu

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

**Librerías nativas en Delphi para la generación, firma electrónica (XAdES), comunicación y validación de registros de facturación** adaptados a las normativas fiscales españolas (Real Decreto 1007/2023: Veri*Factu, Sistemas Informáticos de Facturación No Veri*Factu, Facturae y TicketBAI).

Este proyecto proporciona una base sólida para integrar normativas fiscales complejas en aplicaciones Delphi. Su filosofía central es mantener una arquitectura limpia: la API pública trabaja con *records* y XML puro, estando completamente desacoplada de la base de datos o de componentes específicos de acceso a datos.

---

## 🚀 Características Principales

* **Ciclo de Vida Completo Veri*Factu:** Generación de la estructura XML de alta, cálculo de la huella SHA-256 encadenada, composición de la URL de cotejo del código QR y envoltura en un sobre SOAP para su envío[cite: 3].
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

## 💡 Ejemplos de Uso

En el directorio [`examples/`](./examples) encontrarás proyectos de consola listos para compilar que ilustran el uso de la API:

* **`01-xades`**: Demuestra cómo aplicar una firma a un XML cumpliendo con la política estricta de Facturae.
* **`02-documento-fiscal`**: Utilidad para validar el formato de NIF/NIE/CIF desde la línea de comandos.
* **`03-noverifactu-firma`**: Carga un XML en formato *NO VERI\*FACTU* y le aplica la firma XAdES requerida por la normativa.
* **`04-envio-verifactu`**: Ejemplo didáctico de integración completa. Lee datos desde un archivo `.ini` (NIF del productor, factura, eslabón anterior de la cadena, entorno PRE/PRO)[cite: 1, 2], construye el registro de ALTA Veri*factu, calcula su huella SHA-256[cite: 1, 3] y remite de manera opcional el registro SOAP a la AEAT[cite: 1].

## 🗺️ Hoja de Ruta (Roadmap)

- [x] Firma XAdES nativa desde Windows.
- [x] Validación algorítmica de NIF/NIE/CIF.
- [x] Generación de estructuras XML (Registros de Alta) para sistemas Veri*Factu[cite: 3].
- [x] Generación de URL de cotejo para Códigos QR[cite: 3].
- [x] Cálculo de huella encadenada (SHA-256) según especificaciones[cite: 3].
- [x] Integración de envíos SOAP TLS a los servicios web de la AEAT[cite: 3].
- [ ] Generación de estructuras XML para registros No Veri*Factu.
- [ ] Representación gráfica estandarizada de Códigos QR en informes impresos.

## ⚠️ Estado del Proyecto y Aviso Legal

Este repositorio se encuentra en evolución continua. Las unidades aquí publicadas son funcionales, pero el cumplimiento fiscal integral de un software de facturación depende de cómo se implementen en la aplicación final (incluyendo la persistencia inmutable, el control del reloj, las validaciones de negocio previas y las rutinas de exportación).

> **Aviso Legal:** El código proporcionado tiene fines de desarrollo y **no sustituye** el asesoramiento fiscal profesional ni constituye una homologación oficial por parte de la Agencia Tributaria (AEAT), Facturae, FACe o cualquier otra administración pública. Es responsabilidad exclusiva del desarrollador garantizar que el software final cumple con todas las especificaciones de la normativa vigente.
