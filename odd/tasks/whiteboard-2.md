# Whiteboard 2: blur de contenido, borde, pantallas, tema, zoom y puntos

Objetivo: la pizarra deja de comportarse como un vidrio sobre la pantalla y pasa a ser una superficie de trabajo propia — el blur difumina lo dibujado, el borde se elige, el alcance por pantalla se elige, el color por defecto sigue al tema, y se puede hacer zoom y ver una grilla de puntos.
Rama: `main` en el worktree principal. Runner: `swift test` + `Scripts/bundle.sh` + `--selftest`.
Entrega: `ask-on-risk`.

## Specs

S1. "en whiteboard todo funciona. Pero algo que cambiar es que B no debe mostrar el fondo de panatalla blur sino un blur sobre lo que esta escrito en el board." El blur en la pizarra difumina el contenido de la pizarra (las marcas ya pintadas sobre el color de la página), nunca el escritorio de atrás. Consecuencia: la pizarra no pide frames ni Screen Recording para el blur; se revierte lo que T12 había agregado para mostrar píxeles reales ahí.
S2. "se debe de poder decidir si se quiere o no el border independiete de el modo dibujo." El borde de la pizarra es una preferencia propia, no algo atado al modo dibujo.
S3. "Y tambien si en todos los monitores o solo el activo." Preferencia de alcance: la pizarra se abre en todas las pantallas o sólo en la del puntero/activa.
S4. "por defecto muestre el color del canva en dependencia del tema del sistema, aunque se pueda cambiar a white/black tambien en settings." Por defecto el color de página sigue la apariencia del sistema (claro → blanca, oscuro → negra), es configurable en Settings (seguir el sistema / blanco / negro) y `⌘B` sigue cambiando el fondo de la página actual.
S5. "en whitebnoard es que se pueda hacer zoom tambien junto con el paneo eso da mucha libertad." La pizarra tiene zoom además de paneo: gesto de pinch del trackpad, `⌘+`/`⌘−`, y `⌘0` vuelve a restablecer pan y zoom juntos.
S6. "Y si le agregamos los puntos como en la app de freeform seria aun mejor." Grilla de puntos sobre el fondo de la página, al estilo Freeform.
S7. Nada de lo existente se rompe: el cursor de edición de T11 (incluido rotar y redimensionar sobre la pizarra), borrar/reordenar páginas, `‹ ›` y `⌘←`/`⌘→`, la captura de la página, y las secciones del selftest (`board`, `board pages`, `select`, `blur`, `pin`, `redo`, `pointer pulse`) siguen igual.

## Tasks

| ID | Tarea | Specs | Ruta | Estado | Commit |
| --- | --- | --- | --- | --- | --- |
| T1 | Blur del contenido: `B` difumina las marcas y la página, sin frames ni permiso; revertir los frames del tablero de T12 | S1 | worker | pendiente | |
| T2 | Borde de la pizarra como preferencia independiente del modo dibujo | S2 | worker | pendiente | |
| T3 | Alcance de la pizarra: todas las pantallas o sólo la activa, como preferencia | S3 | worker | pendiente | |
| T4 | Color de página por defecto según el tema del sistema, configurable en Settings (sistema/blanco/negro) | S4 | worker | pendiente | |
| T5 | Zoom con paneo en la pizarra: pinch, `⌘+`/`⌘−`, `⌘0` restablece los dos | S5 | worker | pendiente | |
| T6 | Grilla de puntos estilo Freeform | S6 | worker | pendiente | |
| T7 | Selftest: zoom, puntos, borde, alcance y blur de contenido verificados sobre las vistas reales | S7 | worker | pendiente | |

Orden: T1 es corrección de lo entregado y va primero, sola. Después T4 y T3 (preferencias, chicas), luego T2 y T6 (dibujo), y T5 al final porque el zoom toca el espacio de página y hay que revalidar el cursor, la captura y el paneo. T7 acompaña cada tanda, no queda para el final.

## Log

L1 (2026-11-21, pedido): "en whiteboard todo funciona. Pero algo que cambiar es que B no debe mostrar el fondo de panatalla blur sino un blur sobre lo que esta escrito en el board. Un detalle en el whiteboard es que se debe de poder decidir si se quiere o no el border independiete de el modo dibujo. Y tambien si en todos los monitores o solo el activo. Y por defecto muestre el color del canva en dependencia del tema del sistema, aunque se pueda cambiar a white/black tambien en settings. Un punto importante en whitebnoard es que se pueda hacer zoom tambien junto con el paneo eso da mucha libertad. Y si le agregamos los puntos como en la app de freeform seria aun mejor"
