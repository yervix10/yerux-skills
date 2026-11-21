# Agent Bridge Widget

Widget de escritorio para Linux, macOS y Windows que muestra los estados, el contexto y las cuotas de todos los agentes del bridge. Consulta el dashboard cada 3 s por defecto y recalcula las cuentas atrás cada segundo.

![Ventana de Agent Bridge con seis agentes en una sesión de Linux](docs/screenshot.png)

## Instalación y uso

Con Node.js 22.12 o posterior y una sesión gráfica, ejecuta desde el directorio del widget:

```sh
npm install
npm start
```

Electron se instala con npm y prepara su binario automáticamente en el primer arranque. El widget utiliza las bibliotecas gráficas que ya trae el escritorio. La descarga inicial requiere internet. Durante el uso, el widget lee archivos locales y la salida del comando configurado.

Arrastra la ventana por el tirador del encabezado. Haz doble clic sobre el encabezado o pulsa la flecha para contraerla o expandirla. Cuando la lista supera el área de trabajo, puedes desplazarte dentro de la ventana. La bandeja permite mostrarla, ocultarla, alternar **Siempre visible**, cambiar el intervalo entre 3, 5, 10 y 30 s, y salir. La aplicación comparte una instancia por perfil de usuario y guarda las dimensiones, la posición y las preferencias en `widget.json` dentro del directorio de datos de Electron.

| Acción | Linux y macOS | Windows |
| --- | --- | --- |
| Arrancar en segundo plano | `./bin/agent-bridge-widget start` | `.\bin\agent-bridge-widget.cmd start` |
| Consultar estado | `./bin/agent-bridge-widget status` | `.\bin\agent-bridge-widget.cmd status` |
| Cerrar | `./bin/agent-bridge-widget stop` | `.\bin\agent-bridge-widget.cmd stop` |

`start` puede omitirse y es idempotente. `npm start` trae al frente la ventana si ya existe. `status` devuelve 0 si está activo y 1 si está detenido. Los fallos operativos de los lanzadores devuelven 2. `stop` espera a que la instancia cierre y se puede repetir.

## Fuente de datos

En Linux y macOS el widget ejecuta `~/.claude-bridge/bin/agent dashboard --json`. Para usar otra fuente, asigna a `BRIDGE_WIDGET_CMD` la ruta de un ejecutable o de un script de Node.js (`.js`, `.cjs` o `.mjs`). El widget agrega los dos argumentos `dashboard` y `--json` e invoca la fuente directamente con `execFile`. Los scripts de Node se ejecutan con el binario de Electron en modo Node. Configura la variable antes de arrancar la instancia.

```sh
BRIDGE_WIDGET_CMD="/ruta/al/agent" npm start
```

En Windows configura la ruta de un ejecutable equivalente o de un script de Node que acepte esos argumentos y emita el mismo JSON por stdout. Ejemplo en PowerShell:

```powershell
$env:BRIDGE_WIDGET_CMD = 'C:\Bridge\agent.exe'
.\bin\agent-bridge-widget.cmd start
```

Para un adaptador de Node en Windows puedes usar una ruta como `C:\Bridge\agent-dashboard.cjs`. Si cambias la fuente, ejecuta `stop` y luego `start` para que la nueva instancia reciba el entorno actualizado. Si la fuente falla, supera los 10 s o devuelve datos inválidos, el widget conserva la última lectura, muestra **Sin conexión con el bridge** y reintenta.

## Límites por sistema

- **Linux.** El widget inicia con `--ozone-platform-hint=auto`. En Wayland, el compositor decide si respeta la opción Siempre visible y puede limitar el ajuste de tamaño o el reposicionamiento. Si tu entorno ofrece XWayland, detén el widget y vuelve a iniciarlo con `BRIDGE_WIDGET_X11=1`. También puedes usar las opciones de ventana de tu compositor cuando estén disponibles. Algunos escritorios requieren habilitar la bandeja, en cuyo caso puedes volver a mostrar el widget con `npm start`. [Ventanas en Wayland según Electron](https://www.electronjs.org/docs/latest/api/browser-window/#platform-notices).
- **macOS.** Los controles viven en la barra de menús. El alcance de Siempre visible depende del Space activo y de las ventanas a pantalla completa.
- **Windows.** La fuente debe configurarse con `BRIDGE_WIDGET_CMD`. Si el icono se oculta, búscalo en el menú de iconos ocultos del área de notificación.

## Verificación

```sh
npm test
./bin/agent-bridge-widget stop
npm start -- --capture
```

Con el widget expandido y una fuente real disponible, el comando espera los datos, captura la ventana con `webContents.capturePage()`, guarda `docs/screenshot.png` y cierra la instancia. La integración con el bridge se describe en [INTEGRATION.md](INTEGRATION.md).
