# Detección de cryptojacking en Windows 11 con Wazuh

Laboratorio de detección por comportamiento: un script de PowerShell envía cada 60 segundos la telemetría de rendimiento de un Windows 11 a Wazuh, y un conjunto de reglas propias distingue un pico normal de trabajo de un consumo sostenido compatible con un minero de criptomonedas (MITRE ATT&CK [T1496 – Resource Hijacking](https://attack.mitre.org/techniques/T1496/)).

![Alerta 100110 en el dashboard de Wazuh](docs/capturas/08-alerta-100110-mitre.png)

> Proyecto personal de aprendizaje, hecho en un laboratorio propio y aislado. Las pruebas usan carga sintética generada por scripts, no malware real. El objetivo es exclusivamente defensivo.

## Qué hace

- **Telemetría independiente del idioma.** Lee CPU, memoria, disco, red y el proceso que más CPU consume usando clases CIM (`Win32_PerfFormattedData_*`), que se llaman igual en un Windows en español o en inglés.
- **Umbrales como expresiones regulares.** Wazuh compara texto, no números, así que cada umbral está escrito como una regex anclada.
- **Correlación por proceso.** La regla 100110 solo salta cuando **el mismo proceso** mantiene la CPU por encima del 80 % en 5 muestras dentro de 10 minutos. Eso es lo que diferencia a un minero de una compilación, un juego o una actualización.

| ID | Nivel | Condición |
|---|---|---|
| 100100 | 0 | Cualquier muestra de `perf_monitor` (solo clasifica) |
| 100101 | 5 | CPU entre 80 y 94 % (grupo `cpu_high`) |
| 100102 | 8 | CPU entre 95 y 100 % (grupo `cpu_high`) |
| 100103 | 5 | Memoria libre por debajo de 1000 MB |
| 100104 | 5 | Actividad de disco ≥ 90 % |
| 100105 | 5 | Tráfico de red ≥ 10 000 KB/s |
| 100110 | 12 | 5 coincidencias de `cpu_high` del mismo proceso en 600 s (T1496) |

## Arquitectura

![Topología del laboratorio](docs/capturas/01-topologia.png)

| Máquina | Rol | Software |
|---|---|---|
| Parrot OS | Manager de Wazuh y máquina atacante | Wazuh 4.14 todo-en-uno |
| Windows 11 | Endpoint monitorizado (víctima) | Agente Wazuh 4.14.7 + `perf-monitor.ps1` |

```
perf-monitor.ps1 -> perf-monitor.log -> agente (localfile)
                 -> manager: decoder JSON -> reglas 100100-100110
                 -> alerts.log + dashboard
```

Puertos: `1514/tcp` (agente → manager) y `1515/tcp` (enrolamiento) solo en el segmento interno; `443/tcp` (dashboard) solo en la interfaz de gestión.

## Estructura del repositorio

```
siem-win11-lab/
├── README.md
├── manager/
│   ├── instalar-wazuh-manager.sh      instalación del stack en Parrot + reglas
│   └── local_rules.xml                reglas 100100-100110
├── agente/
│   ├── instalar-agente.ps1            instalación del agente y del wodle en Windows
│   ├── perf-monitor.ps1               telemetría CIM cada 60 s
│   └── ossec-conf-perf-monitor.xml    bloque wodle + localfile para ossec.conf
├── pruebas/
│   ├── logtest-muestras.txt           una muestra JSON por regla
│   ├── stress-cpu-100102-100110.ps1   CPU sostenida (correlación)
│   ├── stress-cpu-100101.ps1          CPU 80-94 % corta
│   ├── stress-memoria-100103.ps1      memoria libre < 1000 MB
│   ├── stress-disco-100104.ps1        disco > 90 %
│   └── stress-red-100105.ps1          red > 10 MB/s
└── docs/
    ├── documentacion-wazuh.docx       documentación técnica completa
    ├── documentacion-wazuh.pdf        la misma en PDF
    └── capturas/                      capturas de las pruebas
```

## Cómo reproducirlo

### 1. Manager (Parrot OS)

```bash
git clone <url-del-repositorio> && cd siem-win11-lab
sudo bash manager/instalar-wazuh-manager.sh eth1   # eth1 = interfaz del segmento interno (opcional)
```

El script instala Wazuh 4.14, abre los puertos si `ufw` está activo, copia `local_rules.xml`, reinicia el manager y muestra las credenciales del dashboard y la contraseña de enrolamiento.

> La contraseña de enrolamiento cambia cada vez que se reinicia `wazuh-manager`. Cópiala justo antes de instalar el agente.

### 2. Agente (Windows 11, PowerShell como administrador)

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\agente\instalar-agente.ps1 -ManagerIP <IP-interna-de-Parrot> -Password "<contraseña-de-enrolamiento>"
```

Instala el agente 4.14.7, copia `perf-monitor.ps1`, añade el wodle y el localfile a `ossec.conf` y reinicia el servicio. Al final muestra la última muestra de telemetría.

![Agente activo en el dashboard](docs/capturas/02-agente-activo.png)

### 3. Validar las reglas sin generar carga

```bash
sudo /var/ossec/bin/wazuh-logtest
```

Pega las líneas de `pruebas/logtest-muestras.txt` y comprueba que cada una cae en su regla.

![wazuh-logtest](docs/capturas/03-logtest-100102.png)

### 4. Prueba de extremo a extremo

En Windows 11 (consola normal de PowerShell, mejor que ISE):

```powershell
.\pruebas\stress-cpu-100102-100110.ps1 -DurationMinutes 8
Get-Content "C:\Program Files (x86)\ossec-agent\perf-monitor.log" -Tail 1 -Wait
```

En Parrot:

```bash
sudo tail -f /var/ossec/logs/alerts/alerts.log | grep --line-buffered -E "10010|10011"
```

Primero aparecen alertas 100101/100102 y, a los ~5 minutos, la 100110 de nivel 12.

![Telemetría en directo](docs/capturas/06-perf-monitor-log.png)
![Alerta en alerts.log](docs/capturas/07-alerts-log-100101.png)

## Problemas que me encontré

Resumen de los más importantes; el detalle (síntoma, causa y solución) está en la [documentación](docs/documentacion-wazuh.pdf).

| Problema | Causa | Solución |
|---|---|---|
| La 100110 no saltaba | En la VM la CPU no pasaba del 91 % y la regla solo contaba la 100102 | Correlacionar el grupo `cpu_high` |
| El log no se actualizaba y no había errores | El agente tiene el fichero abierto; `Add-Content` fallaba y `SilentlyContinue` lo ocultaba | `File.Open` con `FileShare.ReadWrite` |
| El manager no parseaba el JSON | PowerShell 5.1 añade BOM con UTF-8 | Escribir el log en ASCII |
| El script no devolvía datos en Windows en español | Los nombres de `Get-Counter` están traducidos | Clases CIM |
| Las reglas no se disparaban | Wazuh compara texto, no números | Umbrales como regex ancladas |
| La correlación no acumulaba coincidencias | Varios `powershell.exe` se numeran (`#1`, `#2`…) y `top_proc` cambiaba | Un único proceso multihilo |

## Limitaciones y siguientes pasos

- Umbrales sin calibrar con uso normal (sobre todo ahora que la correlación empieza en el 80 %).
- `top_proc_cpu` suma todos los núcleos y puede superar el 100 %; falta normalizarlo.
- El proceso se identifica por nombre: falta añadir PID y ruta del ejecutable.
- Sin correlación con conexiones de red persistentes (pool de minería) ni contadores de GPU.
- Enrolamiento sin endurecer (`use_password` con contraseña fija) y probado con un solo endpoint.

## Tecnologías

Wazuh 4.14 · Windows 11 · PowerShell 5.1 · CIM/WMI · Parrot OS · MITRE ATT&CK

## Autor

Diego Sanz Rodríguez · [GitHub / LinkedIn]
