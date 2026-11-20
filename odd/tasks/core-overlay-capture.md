# Stare — v0.1: overlay, herramientas, captura con marcas

App nativa de barra de menú para dibujar sobre la pantalla, capturar con las marcas y copiar. macOS 26, Swift.

## Specs

S1. El producto se llama **Stare**; bundle `dev.alvaldes.stare`; repo `stare/`.
S2. Referencia de comportamiento: `https://www.trylasso.online/` — se replica comportamiento, no código.
S3. "App de barra de menú": sin ícono en el Dock, sin ventanas al abrir, `LSUIElement`.
S4. Atajo global ⌥⇧A: entra al modo dibujo sobre cualquier app, en todos los displays, incluidas apps a pantalla completa y cualquier Space.
S5. Entrar al modo dibujo no activa Stare ni roba el foco a la app de abajo: se puede dibujar sobre Safari y seguir trabajando en Safari.
S6. Herramientas y teclas: Pen P, Highlighter H, Arrow A, Line L, Rectangle R, Ellipse O, Numbered steps C.
S7. Ocho tintas en teclas 1–8: rojo, naranja, amarillo, verde, azul, violeta, blanco, negro. Highlighter translúcido, el texto de abajo sigue legible.
S8. ⌘Z deshace el último trazo; los pasos numerados no dejan huecos. Esc limpia todas las marcas y sale del modo dibujo.
S9. Alcance v0.1 (decisión del usuario: "Solo núcleo: dibujar + capturar + copiar"): overlay + herramientas + captura con marcas + cards + editor. Fuera de v0.1: texto, páginas, whiteboard, láser, blur, pin, voice briefs, MCP, share links, telemetría, updater.
S10. "macOS 26" mínimo.
S11. "Local primero, distribuición después": sin Developer ID ni notarización en v0.1; `Scripts/bundle.sh` produce `build/Stare.app` con firma ad-hoc.
S12. S = captura del display completo, ⇧S = captura de área. La imagen incluye las marcas y excluye la toolbar, porque se recompone desde el modelo vectorial en vez de capturar la ventana.
S13. Cards de captura abajo a la derecha, 5 s, el hover extiende, Copy/Save/drag-out; el editor permite crop y re-anotar.
S14. Dibujar no pide permisos de macOS. Cada feature que lee píxeles los pide por separado.

## Tasks

| ID | Tarea | Specs | Ruta | Commit |
| --- | --- | --- | --- | --- |
| T1 | Modelo vectorial, geometría y sesión de dibujo (`StareCore`) con tests | S6–S8, S14 | parent | 8a2bead |
| T2 | Shell de barra de menú, atajo global y overlay multi-display | S3–S5 | parent | 541388e, cdb52a9 |
| T3 | Toolbar flotante con herramientas e tintas | S6–S7 | parent | 541388e, cdb52a9 |
| T4 | Captura de display y de área con marcas compuestas + permiso de Screen Recording | S12, S14 | parent | _pending_ |
| T5 | Cards de captura, clipboard y editor con crop y re-anotación | S13 | parent | _pending_ |

## Log

L1. "quiero implementar una app para mac como esta: https://www.trylasso.online/
primero analicemos y hagamos ingenieria inversa a esta app para partir de aqui y puntualizar que vamos a contruir"

L2. Decisiones de alcance: "1. Solo núcleo: dibujar + capturar + copiar  2. macOS 26  3. Local primero, distribuición después".

L3. "aun no podemos hacer eso porque no me gusta el nombre (trazo) necesito otro nombre y podemos comenzar".

L4. Nombre elegido por el usuario: "Stare". Verificado: sin app de anotación de pantalla con ese nombre; existen "Stare Network" (otra categoría) y "StarePatrol" (salud visual).

L5. Reporte de la primera prueba manual: "mira la prueba dio varias cosas:
1. no pinta nada en ninguna pantalla sobre ninguna app
2. no se puede mover la posicion del dock
3. si el foco esta en un monitor ahi es donde debe estar el dock no en el principal siempre
4. hoy si cambio de space no importa porque el dock se mantiene pero no deberia de moverse del space en el que se invoco si ya se empezo a pintar.
5. una pregunta que hiciste es que si aparecia el overlay y creo que no lo veo"

L6. Corrección (cdb52a9): los cinco síntomas comparten una causa — la app accesoria estaba inactiva y macOS consumía el click para activarla, así que nunca llegaba a `mouseDown`; sin Esc tampoco había salida, y el overlay invisible quedó tapando el Dock real. Se activa la app al entrar y se devuelve el foco a la app anterior al salir, el overlay toma key status y first responder, se agrega un hint visible de 2 s, la palette se arrastra con `performDrag` y se ancla al display del puntero, y deja de seguir Spaces. S5 se reescribe: entrar al modo dibujo sí activa Stare de forma invisible; al salir, el foco vuelve a la app que estaba adelante.
