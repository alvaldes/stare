# Stare — paridad de captura con CleanShot X y Shottr

Tanda completa (Tier 1 + 2 + 3) del análisis de apps de captura, en un worktree
aislado de `main`. Fuente de cada ítem: `docs/capture-apps-feature-analysis.md`
en la rama `analysis/capture-features`, matriz §3 y tiers §4.

## Specs

S1. Fuente del alcance: `docs/capture-apps-feature-analysis.md` (§3 matriz de features, §4 secuencia, §6 decisiones, §7 parkeados), rama `analysis/capture-features`. Ningún ítem entra acá si no está en ese documento.

S2. Alcance: Tier 1, Tier 2 y Tier 3 completos. Quedan **parkeados para un análisis posterior, no implementados**: scrolling capture, self-timer, regla de medición y checker de contraste OKLCH/APCA (§7 del análisis). Textual del usuario: "de lo que no si quiero hacer mas adelante asi que no lo elimines del todo. deja esto para un analisis despues: - Scrolling capture: porque quiero que stare tambien permita tomar capturas y despues editar/anotar asi que esto puede entrar - Regla / contraste OKLCH"

S3. Proceso: el trabajo vive en un worktree separado de `main`. Textual: "el alcance es completo en un worktree separado de main para no interferir en algunas correcciones y pequenos fixes que estoy haciendo ahi"

S4. Settings: toda superficie nueva de preferencias va en archivos nuevos; los archivos compartidos (`SettingsView.swift`, `SettingsComponents.swift`) reciben sólo la edición mínima de registro. Textual: "Panes nuevos en archivos nuevos, edits mínimos"

S5. Pin de marcas intacto: `⌥⇧P` sigue haciendo exactamente lo que hace hoy —overlay click-through, toolbar oculta, dibujo intacto al despinear—. Textual (opción elegida): "C · Dos entradas: ⌥⇧P marcas, pin en la card"

S6. Pin de imagen: la capture card gana su propia acción con su propio atajo, distinta de S5, que flota la imagen **capturada** como ventana borderless always-on-top: arrastrable, tamaño y opacidad ajustables, y un lock que la vuelve click-through para interactuar con lo de abajo. S5 y S6 nunca comparten atajo.

S7. OCR y QR: atajo global propio (propuesto ⌥⇧O) y on-device con Vision; se elige un área y el texto reconocido queda en el portapapeles. Textual: "Atajo global propio (p. ej. ⌥⇧O)"

S8. Invariante de privacidad: nada sale de la máquina. No se agrega red nueva; el único tráfico sigue siendo el chequeo de update existente.

S9. Invariante de permisos: dibujar no pide permisos nuevos. Sólo las features que leen píxeles piden Screen Recording, cada una por separado, y OCR/QR corre local.

S10. Captura de ventana: se puede capturar la ventana del frente en vez del display, con las marcas compuestas adentro. Reusa la identificación de ventana que hoy ya existe.

S11. Captura de área determinística: el area drag congela el frame al empezar, muestra una lupa para precisión, y recuerda el último rectángulo para repetirlo con una tecla. Shift fuerza cuadrado.

S12. Historial de capturas: las últimas N capturas de la sesión quedan reabribles en el editor, con sus marcas todavía editables. En memoria; nada se persiste a disco.

S13. Pixelate junto a blur: cuando se oculta contenido sensible se puede elegir pixelado aleatorizado además del blur actual. Antes de exponerlo, el blur se audita como herramienta de redacción (S23).

S14. Downscale al guardar: opción de bajar capturas Retina a 1× o a un ancho máximo. Apagada por defecto: sin activarla, cada captura existente se guarda como hoy.

S15. Profundidad de anotación: formas con relleno o contorno, estilos de punta de flecha, estilo de texto recordado como default del próximo texto, y spotlight persistente como marca.

S16. Editor: zoom y pan, para anotar con precisión sobre una captura. No cambia las teclas de las herramientas.

S17. Plantillas de nombre de archivo por tokens (fecha, hora, app, display) sobre el destino carpeta que ya existe. El prefijo actual sigue funcionando.

S18. Backdrop barato al guardar: padding, esquinas redondeadas y sombra, opcionales. Sin presets, sin ratios, sin fondos importados.

S19. Canvas componible: el editor puede sumar otra captura o una imagen pegada y posicionarla.

S20. Ningún ítem de la lista negra del análisis §5: sin grabación, sin GIF, sin cloud, sin S3, sin formato de documento propio, sin modos nuevos que dupliquen el modelo mental.

S21. Cada cambio de comportamiento con resultado determinístico arranca en RED con un test que falla, y termina en GREEN. Lo que dependa de píxeles reales de pantalla se documenta como check manual en la fila del commit, y se verifica a mano antes de cerrar la tarea.

S22. Tests y docs van con el código en la misma unidad de trabajo. Toda preferencia nueva o tecla nueva se refleja en README (`## Every tool is one key away`, `## Settings`) y en CHANGELOG (`## Unreleased`).

S23. Auditoría de blur, previa a S13: un área cubierta por blur no debe dejar reconstruible el contenido original. Si no se sostiene, el pixelado aleatorizado pasa a ser la primitiva de redacción y el README se corrige.

## Tasks

| ID | Tarea | Specs | Ruta | Commit |
| --- | --- | --- | --- | --- |
| T0 | Convención de panes de Settings nuevos y registro mínimo compartido | S4, S22 | parent | — |
| T1 | Captura de ventana del frente con marcas compuestas | S10, S21 | parent | 1ee6393, ff41287, 989b795 |
| T2a | Area drag: geometría pura, ⇧ cuadrado, clamp al display | S11, S21 | worker | 3437beb |
| T2b | Area drag determinística: freeze, lupa, rect recordado | S11, S21 | parent | — |
| T3 | Historial de capturas en memoria, reabrir en el editor | S12, S21 | parent | — |
| T4 | Pin de la imagen capturada desde la card, con atajo propio y lock | S6, S4, S21 | parent | — |
| T5 | OCR y QR on-device con atajo global ⌥⇧O | S7, S9, S22 | parent | — |
| T6 | Auditoría de blur como redacción, y pixelate junto a blur | S23, S13 | parent | — |
| T7 | Downscale al guardar, apagado por defecto | S14, S21 | parent | — |
| T8 | Profundidad de anotación: relleno, puntas, estilo de texto, spotlight | S15, S21 | parent | — |
| T9 | Zoom y pan en el editor | S16, S21 | parent | — |
| T10 | Plantillas de nombre por tokens | S17, S21 | parent | — |
| T11 | Backdrop barato: padding, esquinas, sombra | S18, S22 | parent | — |
| T12 | Canvas componible: sumar captura o imagen pegada | S19, S21 | parent | — |

## Checks manuales

T1 necesita ojo humano: ningún test unitario puede probar píxeles reales de una ventana. **Los cinco puntos pasaron**: el usuario los probó y funcionando.

Quedan como referencia los que cubren el borde del feature:

1. Abrir Stare con Screen Recording concedido, abrir una app (Safari, Terminal) y un par de ventanas de otras apps.
2. `⌥⇧A`, dibujar una flecha que cruce el borde de la ventana del frente y un recuadro adentro.
3. `⌥S`: la imagen tiene que ser sólo esa ventana, con la flecha cortada justo en el borde y el recuadro en su lugar.
4. Repetir con la ventana del frente en un segundo display: la captura tiene que usar el display correcto.
5. Arrastrar la ventana medio fuera de pantalla y `⌥S`: la captura se recorta, no falla.
6. Con el whiteboard abierto, `⌥S` sigue capturando el board como antes (no hay ventanas que capturar ahí).
7. `S`, `⇧S` y `⌥⇧S` siguen comportándose exactamente como antes.

## Log

L1. "en un worktree independiente analicemos los features de las apps de captura https://cleanshot.com/ https://shottr.cc/ para ver que aplicar a stare"

L2. "de lo que no si quiero hacer mas adelante asi que no lo elimines del todo. deja esto para un analisis despues:
- Scrolling capture: porque quiero que stare tambien permita tomar capturas y despues editar/anotar asi que esto puede entrar
- Regla / contraste OKLCH

Explicame lo del self-timer aun no me decido si lo quiero implementar

las preguntas:
1. ⌥⇧P no se que pinea explicame que es cada cosa para decidir mejor
2. el alcance es completo en un worktree separado de main para no interferir en algunas correcciones y pequenos fixes que estoy haciendo ahi

Si queda algo mas por mi de decidir o algo mas que debebamos discutir ahora es el momento antes de que empecemos a escribir codigo."

L3. Respuestas del usuario a las cuatro decisiones de §6: pin = "C · Dos entradas: ⌥⇧P marcas, pin en la card"; alcance = "Tier 1 + 2 + 3 en este mismo worktree"; settings = "Panes nuevos en archivos nuevos, edits mínimos"; OCR = "Atajo global propio (p. ej. ⌥⇧O)".

L4. Base de la rama: `feat/capture-parity` desde `main` en `f38bd93`. El trabajo en vuelo del usuario vive en `fix/bar-preview-and-cursors` (`2fcc81a`), no en `main`; el merge de esa rama contra esta se resuelve cuando aterrice, con la superficie de Settings ya separada por S4.

L5. T0 plegado en T3: ninguna tarea de T1 necesitaba un pane de Settings nuevo, y la primera que sí lo necesita es el historial. La convención de S4 se aplica cuando aparezca ese pane, no como tarea ceremonial.

L6. Corte de T1: núcleo puro (`1ee6393`) + integración en el overlay (`ff41287`), 538 líneas en 11 archivos. Es el mismo corte a/b que ya usa `core-overlay-capture.md` (T4a/T4b). El conteo de líneas que reporta el harness contra `origin/main` incluye commits del usuario sin pushear: el diff real de esta tanda es `git diff f38bd93..HEAD`.

L7. Corte de T2: T2a (`3437beb`, delegada al worker por backstop de contexto) + T2b pendiente. Regla aceptada: primero ⇧ cuadrado y después clamp, así que un cuadrado arrastrado fuera del display queda no-cuadrado contra el borde — el gesto dice "hasta acá", y el clamp no inventa área que no existe. Si no gusta, la alternativa es clampear el punto final antes de cuadrar; decidirlo en T2b junto con el freeze.

L8. Verificación independiente de T1 (`gentle-ai-verify`, item 3 por el refactor del camino compartido) encontró dos regresiones reales, ya corregidas en `989b795`: en el whiteboard `⌥S` caía en un handler no cableado y quedaba tragado (antes capturaba el board), y `⌥⇧S` cambiaba de área a ventana. El fix hace que `⌥S` intercepte sólo cuando el display puede atenderlo y excluye `⇧`. La misma verificación dejó 16 probes durables en `WindowCaptureBoundaryTests.swift` (bordes de geometría, origen negativo de un display arriba, marca real que sobrevive al crop en su offset). Suite: 569 tests, 0 fallas.

L9. **Prioridad 1 (restricción de displays).** Textual: "los 5 checks los pruebo despues ahora es prioritario que las pruebas que estes haciendo donde muestras el whiteboard y demas solo lo muestres en el primary monitor porque estoy viendo algo en los otros monitores y no quiero que se interrumpa / esto es prioridad 1 para todo hasata que esto quede resuleto y despues reanuda". Causa encontrada: cuatro archivos de test abren ventanas reales (`orderFront` / `orderFrontRegardless`), y en este toolchain los filtros no restringen de forma confiable, así que una corrida común podía mostrarlas en cualquier display. Corregido en `c34b4d5`: todo pasa por `PrimaryScreenTestWindow.frame(for:)`, con dos tests de contrato que fijan el invariante; los boards se confinan antes del primer turno del runloop y la barra se re-pina después de cada mutación de estado. Sin assertions debilitadas y sin tests salteados. Riesgo residual declarado: `openBoard()` ordena un board por display y activa la app antes de que el test pueda moverlo, así que no puede probarse desde el código que no se componga un frame suelto en un monitor secundario.

L10. Los cinco puntos manuales de T1 pasaron (usuario: "los 5 puntos probados y funcionando"). T1 cerrada por verificación humana sobre `989b795`.

L11. Límite del enfoque "pinear ventanas": la preferencia de alcance del board resuelve `"active"` al display **donde está el puntero**, no al primario (`OverlayController.buildBoardCanvases`, `state.boardScope`), y `openBoard()` activa la app y ordena un board por display antes de que cualquier test pueda moverlo. Conclusión: sin un cambio de producto no se puede garantizar desde los tests que esos dos archivos no compongan un frame suelto en un monitor secundario. Regla operativa que rige la tanda mientras el usuario esté mirando los otros monitores: **nunca correr la suite completa ni `WhiteboardClearRoutingTests` ni `ToolbarPanelLiveResizeTests`**; la verificación se hace con filtros de una clase por invocación (la forma con `|` no matcheó nada una vez y no se usa), prefiriendo las clases que no abren ventanas. Todo lo que corra `swift test` completo —incluido cualquier worker— tiene que respetar esta regla.
