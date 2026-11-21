# Integración con agent-bridge

El bridge debe arrancar el widget una vez por sesión gráfica del usuario, al finalizar con éxito `agent up` o la toma del rol con `admin`. El comando de arranque es idempotente. El widget consulta todo el dashboard y administra su propio intervalo de refresco.

## Instalador de skills

Instala el contenido de este repositorio en una ubicación estable por usuario. En los ejemplos, `widget_dir` es la ruta absoluta elegida para el checkout. Conserva los permisos de ejecución de `bin/agent-bridge-widget`.

Desde esa ruta, con Node.js 22.12 o posterior:

```sh
npm ci --include=dev
npm exec -- electron --version
```

La segunda línea prepara el binario de Electron para que el primer arranque desde el bridge pueda ser inmediato. Usa los mismos comandos en PowerShell si instalas el widget en Windows.

## Llamada desde `agent up` y `admin`

En Linux y macOS, llama al lanzador desde el proceso interactivo que recibe la orden, con el entorno de la sesión gráfica y el mismo usuario que ejecuta el bridge:

```bash
if [[ -x "$widget_dir/bin/agent-bridge-widget" ]]; then
  if [[ "$(uname -s)" == Darwin || -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    if ! BRIDGE_WIDGET_CMD="${BRIDGE_WIDGET_CMD:-$HOME/.claude-bridge/bin/agent}" \
      "$widget_dir/bin/agent-bridge-widget" start; then
      printf '%s\n' 'El widget de agent-bridge no pudo arrancar.' >&2
    fi
  fi
fi
```

Ejecuta la llamada después de completar la acción principal. Si falla, conserva el resultado de `agent up` o `admin` y reporta el fallo del widget por separado. El lanzador desacopla Electron del proceso que lo llama. En macOS, invócalo solo desde la sesión de escritorio del usuario. En un host Linux sin sesión gráfica, la condición omite el arranque.

En Windows, usa el lanzador equivalente en la sesión gráfica. El valor de `BRIDGE_WIDGET_CMD` debe apuntar a un equivalente de `agent dashboard --json` instalado en Windows:

```powershell
$env:BRIDGE_WIDGET_CMD = 'C:\Bridge\agent.exe'
& (Join-Path $widgetDir 'bin\agent-bridge-widget.cmd') start
```

Consulta el estado con `status` y cierra con `stop`, usando el mismo lanzador, usuario y sesión gráfica. Los códigos de `status` son 0 (activo), 1 (detenido) y 2 (error operativo). Si la integración cambia la ruta de la fuente, reinicia el widget usando esos comandos.

## Contrato de la fuente

El widget llama a la fuente con `dashboard --json` y lee un objeto JSON por stdout. Usa stderr para diagnósticos y un código distinto de cero para fallos. `time` y los `resets_at` se emiten como segundos Unix, con `null` cuando falta un reinicio. Emite los porcentajes numéricos entre 0 y 100, o `null`, y la antigüedad `data_age_s` en segundos. [Esquema que valida el widget](src/dashboard.cjs).
