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
| T1 | Captura de ventana del frente con marcas compuestas | S10, S21 | parent | — |
| T2 | Area drag determinística: freeze, lupa, rect recordado, shift cuadrado | S11, S21 | parent | — |
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
