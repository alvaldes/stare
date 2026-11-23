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
| T2b-a | Area drag: base congelada al arrancar, con liberación en captura, clic perdido, Esc y deactivate | S11, S21 | worker | bccea8d |
| T2b-b | Area drag: lupa sobre el frame congelado y rectángulo recordado con Return | S11, S21 | worker | cfc2dcc, c39de43 |
| T3 | Historial de capturas en memoria, reabrir en el editor | S12, S21 | worker | 8e5d205 |
| T4 | Pin de la imagen capturada desde la card, con atajo propio y lock | S6, S4, S21 | worker | pendiente de hash |
| T5 | OCR y QR on-device con atajo global ⌥⇧O | S7, S9, S22 | parent | — |
| T6 | Auditoría de blur como redacción, y pixelate junto a blur | S23, S13 | peer | — |
| T7 | Downscale al guardar, apagado por defecto | S14, S21 | parent | — |
| T8 | Profundidad de anotación: relleno, puntas, estilo de texto, spotlight | S15, S21 | parent | — |
| T9 | Zoom y pan en el editor | S16, S21 | peer | — |
| T10 | Plantillas de nombre por tokens | S17, S21 | peer | — |
| T11 | Backdrop barato: padding, esquinas, sombra | S18, S22 | peer | — |
| T12 | Canvas componible: sumar captura o imagen pegada | S19, S21 | parent | — |

## Checks manuales

T2b-a necesita ojo humano: el congelado es píxeles y orientación, nada de eso se prueba con bitmaps sintéticos.

1. `⇧S` sobre una app con tooltip o estado de hover: la pantalla se congela al arrancar el arrastre y el tooltip se queda quieto mientras elegís.
2. Una marca de blur dibujada antes de `⇧S` difumina el contenido congelado, no uno que se mueve a mitad del arrastre.
3. `Esc` a mitad del arrastre: vuelve la pantalla viva exactamente, marcas intactas, nada capturado.
4. Terminar el arrastre: la imagen de la card coincide con el frame congelado, y el overlay vivo vuelve enseguida.
5. `⇧S` en el whiteboard igual que antes (sin congelado), y desactivar a mitad de arrastre no deja frame viejo al reentrar.
6. Sin permiso de Screen Recording el arrastre sigue funcionando en vivo, como hoy.

## Checks manuales de T4

1. Captura y `⌥⇧I`: la última captura flota sobre otras apps, centrada en el display donde estás, y Stare sigue funcionando abajo.
2. Arrastrarla por la superficie: se mueve, y durante el arrastre ningún click cae en la app de abajo.
3. Scroll sobre ella: crece o decrece manteniendo el aspecto, nunca se va de pantalla; `⌥`+scroll la desvanece.
4. Hover: aparecen ✕ y 🔒 arriba a la derecha. 🔒 (o `⌥⇧L` con el puntero encima) hace que clicks y arrastres pasen a la app de abajo; `⌥⇧L` otra vez la desbloquea.
5. El botón de pin de la card flota esa captura; un click en cualquier otro lado sigue abriendo el editor y el arrastre sigue arrastrando la card.
6. Dos pines coexisten y cada uno cierra con su ✕; `⌥⇧A`, dibujar y `Esc` no los tocan; cerrar Stare limpia pines e historial sin escribir nada a disco.
7. Barra de menú: "Pin Image ⌥⇧I" (deshabilitado antes de la primera captura) y "Toggle Image Lock ⌥⇧L".
8. `⌥⇧P` sigue pineando **las marcas**, exactamente como antes.

## Checks manuales de T3

1. Dos capturas (`S` y `⇧S`), abrir Settings → Capture → History: las dos miniaturas con fecha y dimensiones, la más nueva primero.
2. Open en la primera: el editor abre sobre esa captura con sus marcas tal como se capturaron, herramientas y tintas iguales, y dibujar/recortar sigue funcionando.
3. Capturar otra: el historial crece; Clear lo vacía; la siguiente captura lo repuebla.
4. Cerrar Stare y reabrir: History vacío, y nada apareció en disco.
5. Abrir desde Settings con una sesión de dibujo armada: el overlay se cierra primero, no queda una capa comiéndose los clicks del editor.

## Checks manuales de T2b-b

1. `⇧S` sobre un tooltip: la lupa muestra píxeles congelados a 4× con la cruz en el borde exacto, y cerca del borde del display salta al otro lado en vez de tapar lo que enmarcás.
2. Segundo `⇧S`: el área anterior aparece ya enmarcada; `Return` la captura al instante; un arrastre la reemplaza.
3. `Esc` a mitad de arrastre o con el rect precargado: vuelve el overlay vivo con las marcas intactas.
4. `⇧S` en el whiteboard: sin lupa y sin rectángulo recordado, captura como antes.
5. Sin Screen Recording: el arrastre funciona en vivo y no aparece lupa.

## Checks manuales de T1

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

L12. T2 cerrada: T2a (`3437beb`), T2b-a (`bccea8d`, base congelada) y T2b-b (`cfc2dcc`, lupa 4× + rectángulo recordado con `Return`). La lupa lee el frame congelado a propósito: sobre píxeles vivos mentiría sobre el borde que estás eligiendo; sin permiso de Screen Recording no hay lupa y el arrastre sigue en vivo. `Return` sólo se toma cuando hay un rectángulo precargado, y el whiteboard no recibe ninguna de las dos cosas.

L13. Trampa de verificación encontrada dos veces: `swift test --filter <Clase>` puede imprimir `Executed 0 tests` y aun así correr los casos en esa misma invocación. La lectura fiable es contar `Test Case '...' passed` y restar las cinco líneas de `Test Suite '...' passed` por corrida. `Executed 0 tests` no prueba ni que el filtro no matcheó ni que la corrida pasó. Con la suite completa prohibida por L11, el filtro por clase es la única verificación disponible, así que este conteo importa.

L14. Verificación independiente de T2b (`bccea8d`, `cfc2dcc`) encontró un **bloqueante real**: la lupa cropeaba su rect fuente con convención bottom-left mientras `CGImage.cropping(to:)` cuenta filas desde arriba, así que magnificaba una banda espejada verticalmente para cualquier puntero fuera del centro exacto del display. Los tests existentes no podían verlo porque todos usaban `y = 350` en un display de 700 (el único caso donde el espejo es invisible). Corregido en `c39de43` con dos tests de bandas que leen el píxel bajo el puntero, más tokens en `AreaCaptureFrameState` para que un frame del arrastre anterior no pueda ser la base del siguiente tras `Esc` + re-armar. Re-verificado: los siete conteos coinciden (13/11/9/8/6/7/2, cero fallas) y el veredicto fue seguro para el pase manual. Lección para la tanda: un test que sólo usa el caso identidad (centro, cero modulado) no prueba orientación.

L15. Follow-up anotado, no hecho: el verificador dejó cinco probes para el estado de serialización de los asks (captura que devuelve nil, `clear()` a mitad de vuelo, arm/release repetido, re-armar tras fallo, camino del board). Hoy están cubiertos de forma parcial por los tests de congelado; si el estado de asks crece, adoptarlos primero.

L16. Consolidación con la rama hermana: `main` avanzó a `2b9c66c` (bar, organiser, cursor, tests de render) y `feat/capture-parity` se rebaseó encima sin un solo conflicto. `GeneralPreferences` no cambió de forma del otro lado, así que mi default de tres líneas quedó intacto. Los dos helpers de confinamiento de ventanas de test se unificaron en `PrimaryScreenTestWindow.frame(for:)`: `NSWindow.confineToPrimaryScreen()` ahora delega ahí, y los dos tests de render del otro lado siguen verdes (4 + 7 casos). Un solo invariante, una sola implementación.

L17. Reparto con la sesión hermana (a pedido del usuario: "coordina con el otro agente para que haga trabajo tuyo tambien y terminemos antes"). Criterio: propiedad por archivo, para que dos escritores nunca editen el mismo archivo a la vez.
- **Sesión hermana** (rama desde `main`): T6 auditoría de blur + pixelate, T9 zoom del editor, T10 plantillas de nombre, T11 backdrop. Archivos suyos: `CaptureEditor.swift`, `BlurEffect.swift`, `MarkRenderer.swift`, `CapturePreference.swift`, `CaptureFile.swift`, archivos nuevos y sus tests.
- **Esta rama**: T3 historial, T4 pin de imagen, T5 OCR, T7 downscale, T8 profundidad de anotación, T12 canvas componible. Archivos míos: `OverlayController`, `OverlayView`, `FrontWindowLocator`, `WindowCaptureTarget`, `CaptureCard` y los módulos de área/ventana de `StareCore`.
- Compartidos: `SettingsView.swift` (5 líneas de registro, el pane va en archivo nuevo — S4) y `GeneralPreferences.swift` (mis tres líneas del default; quien agregue una preferencia la suma al final). Quien aterrice segundo re-aplica sus cinco líneas.
- Reglas que se le pasaron: nada de suite completa, filtros de una clase, conteo real de casos (L11/L13), ventanas de test confinadas al primario, RED observado, docs con el código, sin push ni merge sin el humano.
