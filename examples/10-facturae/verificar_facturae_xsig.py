# Verificacion local opcional de un Facturae firmado (.xsig).
#
# Comprueba la firma XMLDSig y el perfil XAdES del fichero que genera
# EmitirFacturae en modo firmado. Es solo un apoyo de desarrollo: NO sustituye
# la validacion oficial (VALIDe / FACe).
# Las firmas XAdES generadas por este ejemplo tienen 3 referencias XMLDSig:
# documento, SignedProperties y KeyInfo.
#
# Requiere Python con:  pip install lxml signxml
# Uso:                  python verificar_facturae_xsig.py eDoc_2026_A1_000005.xsig

from pathlib import Path
import sys

from lxml import etree
from signxml import SignatureConfiguration, XMLVerifier
from signxml.xades import XAdESVerifier


def certificado_pem(raiz):
    nodos = raiz.xpath('//*[local-name()="X509Certificate"]')
    if not nodos:
        raise RuntimeError("No se encontro ds:X509Certificate.")
    base64_cert = "".join((nodos[0].text or "").split())
    return (
        "-----BEGIN CERTIFICATE-----\n"
        + base64_cert
        + "\n-----END CERTIFICATE-----\n"
    )


def verificar(ruta):
    raiz = etree.parse(str(ruta)).getroot()
    cert = certificado_pem(raiz)
    XMLVerifier().verify(
        raiz,
        x509_cert=cert,
        require_x509=False,
        expect_config=SignatureConfiguration(expect_references=3),
    )
    XAdESVerifier().verify(raiz, x509_cert=cert, require_x509=False)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Uso: python verificar_facturae_xsig.py fichero.xsig")
        sys.exit(2)
    fichero = Path(sys.argv[1])
    try:
        verificar(fichero)
    except Exception as exc:
        print("ERROR:", type(exc).__name__, str(exc))
        sys.exit(1)
    print("OK: firma XMLDSig/XAdES verificable localmente")
