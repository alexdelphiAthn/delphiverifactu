# Control del reloj fiscal

> **Autor:** Alejandro Laorden Hidalgo · alejandro.laorden@protonmail.com


`Fiscal.RelojFiscal.pas` comprueba que la hora con la que se fechan los
registros NO VERI\*FACTU es exacta. La Orden HAC/1177/2024 exige un margen
máximo de **un minuto** y que la fecha incluya huso horario.

Regla aplicada:

- Diferencia entre el reloj del sistema y la hora oficial **≤ 60 s** → se
  **permite** emitir.
- Diferencia **> 60 s**, o **no se puede** comprobar la hora → se **deniega** y
  no se emite el registro.

El margen legal no se puede ampliar: `MargenLegalSegundos` recorta cualquier
valor por encima de 60.

## API pública

- `HoraSistemaUtc` — reloj del sistema en UTC.
- `MargenLegalSegundos` — recorta el margen al máximo legal (60 s).
- `DesfaseEnSegundos` — diferencia con signo, en segundos.
- `EvaluarReloj` — evalúa dos horas UTC (sin red); ideal para pruebas.
- `ExigirReloj` — aplica la regla; lanza `ERelojFiscalDesfasado` si no procede.
- `ObtenerHoraRedHttp` — hora de referencia leyendo la cabecera HTTP `Date`.
- `ComprobarRelojRed` — atajo: obtiene la hora de red y evalúa.

## Uso típico

```pascal
var
  oResultado: TResultadoReloj;
begin
  // Hora de referencia por red (o usa EvaluarReloj con una hora conocida).
  oResultado := ComprobarRelojRed(cServidorHoraDefecto, 2000,
                                  cMargenRelojSegundos);
  // Lanza ERelojFiscalDesfasado si está desfasado o no se pudo comprobar.
  ExigirReloj(oResultado, 'Registro de facturación NO VERI*FACTU');
  // ... aquí ya es seguro fechar y emitir el registro ...
end;
```

## Probar sin conexión

`EvaluarReloj` es aritmética pura: puedes simular cualquier desfase sin red.

```pascal
var
  dSistema, dOficial: TDateTime;
  oRes: TResultadoReloj;
begin
  dOficial := HoraSistemaUtc;
  dSistema := dOficial + 90 / 86400; // +90 s -> fuera de margen
  oRes := EvaluarReloj(dSistema, dOficial, 60, 'SIMULADO');
  Writeln(oRes.Resumen);             // DENEGADO ...
end;
```

El ejemplo [`06-reloj-fiscal`](../examples/06-reloj-fiscal) hace exactamente
esto desde un `.ini`: cambia `DesfaseSimuladoSegundos` para ver `PERMITIDO` o
`DENEGADO`.

## NTP en producción

Este ejemplo obtiene la hora oficial de la cabecera HTTP `Date` (solo RTL, sin
dependencias) para que sea fácil de compilar y probar. En producción
la hora se obtiene por **NTP** con Indy `TIdSNTP`, consultando varios servidores
(`time.google.com`, `time.windows.com`, `pool.ntp.org`) con un timeout por
servidor. El **criterio de aceptación es el mismo**: diferencia ≤ 60 s. La
comprobación **no ajusta** el reloj de Windows; solo verifica y bloquea.
