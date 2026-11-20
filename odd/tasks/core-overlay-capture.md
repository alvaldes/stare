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
| T7 | Herramientas faltantes del dock: eraser, text, laser y marco del cursor | S21–S24 | parent | _pending_ |
| T6 | Ventana de configuración: ubicación de la palette y alcance del overlay | S15, S16 | parent | _pending_ |

## Log

L1. "quiero implementar una app para mac como esta: https://www.trylasso.online/
primero analicemos y hagamos ingenieria inversa a esta app para partir de aqui y puntualizar que vamos a contruir"

L2. Decisiones de alcance: "1. Solo núcleo: dibujar + capturar + copiar  2. macOS 26  3. Local primero, distribuición después".

L3. "aun no podemos hacer eso porque no me gusta el nombre (trazo) necesito otro nombre y podemos comenzar".

L4. Nombre elegido por el usuario: "Stare". Verificado: sin app de anotación de pantalla con ese nombre; existen "Stare Network" (otra categoría) y "StarePatrol" (salud visual).

L7. Segunda prueba: "1. no se pone el cursor en cruz 2. no pinta 3. si cambia [las teclas] 4. no lo pude probar por lo que paso en 2. 5. si funciona 6. si funciona / un detalle, sigo sin ver el overlay y nada se pinta."

L8. Medición con `--selftest`: la ventana está en pantalla (WindowServer layer=1000, 1920x1080 en 0,0, alpha 1, unoccluded), el contentView es el OverlayView con frame correcto, y un click inyectado en la vista deja marca (`syntheticClickStrokes=1`); el render vectorial produce el PNG esperado. La app nunca se activa (`appActive=false`). Cambio aplicado: el overlay deja de usar `.canJoinAllSpaces` y `.nonactivatingPanel` —la única diferencia con la palette, que sí recibe clicks—, se reordena al cambiar de Space por `NSWorkspace.activeSpaceDidChangeNotification`, y el cursor de cruz se fuerza con un tracking area `.activeAlways` en vez de cursor rects.

L5. Reporte de la primera prueba manual: "mira la prueba dio varias cosas:
1. no pinta nada en ninguna pantalla sobre ninguna app
2. no se puede mover la posicion del dock
3. si el foco esta en un monitor ahi es donde debe estar el dock no en el principal siempre
4. hoy si cambio de space no importa porque el dock se mantiene pero no deberia de moverse del space en el que se invoco si ya se empezo a pintar.
5. una pregunta que hiciste es que si aparecia el overlay y creo que no lo veo"

L6. Corrección (cdb52a9): los cinco síntomas comparten una causa — la app accesoria estaba inactiva y macOS consumía el click para activarla, así que nunca llegaba a `mouseDown`; sin Esc tampoco había salida, y el overlay invisible quedó tapando el Dock real. Se activa la app al entrar y se devuelve el foco a la app anterior al salir, el overlay toma key status y first responder, se agrega un hint visible de 2 s, la palette se arrastra con `performDrag` y se ancla al display del puntero, y deja de seguir Spaces. S5 se reescribe: entrar al modo dibujo sí activa Stare de forma invisible; al salir, el foco vuelve a la app que estaba adelante.

S15. "ahora el dock aparece donde esta el cursor pero el usuario puede querer esto o puede qurere que aparezca donde esta el foco en la ventana donde se invoco o en monitor donde esta el foco" — la ubicación de la palette es una preferencia con al menos tres modos: display bajo el cursor (por defecto), display de la ventana con foco, y display principal fijo.

L9. Verificación end-to-end con clicks reales inyectados (el proceso de la sesión tiene Accessibility): tras `⌥⇧A` las ventanas de Stare quedan en `layer=1000` por encima de la app de adelante (`Ghostty layer=0`), `cursorUpdate` dispara, `mouseDown 960,540` llega, `commit strokes=1` registra el trazo y `Esc` desactiva. Segunda ronda: dibujo, `Ctrl→` a otro Space, las tres ventanas siguen en `layer=1000`, el punto de prueba sigue teniendo a Stare arriba y un click vuelve a pintar. La app queda `active=false` y aun así recibe clicks y teclas: la activación no era el problema, lo era `.canJoinAllSpaces` sobre un `NSPanel`.
L10. Falta confirmación humana de pantalla completa (spec S4) y de la estética del marco de armado.
L11. Deuda declarada: `Diag` escribe `/tmp/stare.log` siempre; hay que apagarlo antes de distribuir.

S16. "en settings se puede configurar si quieres que sea en todos o en active" — el overlay dibuja en todos los displays o sólo en el display activo, según preferencia. Por defecto: todos.
S17. "si se presiona shift mientras se usa pen o highlight haga una linea recta como en los editores como photoshop" — con Shift apretado, pen y highlighter colapsan el trazo a una recta desde el punto inicial hasta el actual; al soltarlo se retoma el trazo libre.
S18. "cmd+Z funciona pero solo en las modificaciones del monitor activo no quiera las del resto de monitores" — el historial de deshacer es global entre displays: ⌘Z deshace la última marca en el orden real en que se dibujó, sin importar en qué monitor esté el puntero.

L12. Segunda verificación con eventos inyectados: la palette queda en `layer=1001` por encima del overlay (`layer=1000`) y las dos pantallas quedan por encima de las apps. Latencia de pintado medida sobre 56 frames de un drag continuo: mediana 2,5 ms, p90 6,3 ms, antes 50-170 ms. Causa: `NSLog` sincrónico en el main thread por frame y `wantsLayer` (una transacción de Core Animation por evento). El log pasó a sólo archivo y la vista dejó de ser layer-backed.
L13. Límite conocido de la sonda: los eventos sintéticos de teclado no traen `charactersIgnoringModifiers`, así que ⌘Z y las teclas de herramienta no se pueden verificar inyectando; quedan para confirmación humana.

S19. "se pueda elegir si tener o no este borde en el overlay y si se tiene hay que hacer que sea del mismo color de los 8 el que este seleccionado" — el marco es opcional (ítem en el menú de la barra, persistido) y usa la tinta seleccionada. Decisión del usuario: queda visible mientras dure el modo dibujo, no desaparece con la primera marca.
S20. "en rect y elipse cuando se presiona shift debe dibujar un cuadrado y un circulo" — con Shift, rectángulo y elipse mantienen lados iguales conservando la dirección del arrastre.

L14. Tercera prueba: "al dibujar en el segundo monitor ya cmd+z no hace nada"; "en rect y elipse cuando se presiona shift debe dibujar un cuadrado y un circulo"; "hay un problema con arrow, rect, ellipse, line" (imágenes muestran estelas en escalera).
L15. Correcciones: (a) las herramientas definidas por extremos invalidaban sólo el último segmento, así que cada preview anterior quedaba pintado — ahora invalidan la unión de los bounds previos y actuales de la marca; (b) ⌘Z se intercepta con un monitor local de eventos, así no depende de qué ventana es key ni de qué display tiene el puntero; (c) Shift en rect/elipse ajusta el extremo con `PathBuilder.squareConstraint`; (d) cambiar tinta o herramienta repinta (el marco y los badges seguían con el color viejo); (e) el marco de armado es opcional desde el menú y persiste en UserDefaults.
L16. Verificado con capturas de pantalla tomadas a mitad de arrastre: la herramienta línea deja una sola línea limpia sin estela, y Shift+rectángulo produce un cuadrado exacto.

L17. "solo un detalle y es saber porque el borde desaparece con la primera pontada". Respuesta: lo decidí yo, no estaba en el spec; el marco era la señal de armado y vacío. El usuario eligió que quede mientras dure el modo dibujo. Verificado con captura posterior a un trazo: marco de la tinta activa en los cuatro bordes con la marca ya pintada.

S21. "faltan elementos en el dock como el ease erase" — borrador con tecla `E`: borra marcas completas por hit-test sobre el trazo, no píxeles. Los pasos numerados se renumeran sin huecos.
S22. "falta el puntero lazer" — láser con tecla `F`: trazo efímero que se desvanece en 1,2 s, se descarta solo y nunca se incluye en una captura.
S23. "el text" — texto con tecla `T`: click coloca un editor en línea, Enter o click afuera confirma, Escape cancela; fuente 20 pt con la tinta activa.
S24. "la opcion de poner un marco al cursor" — marco/anel de 40 pt alrededor del puntero que lo sigue, en la tinta activa, apagado por defecto y conmutable desde la palette o con `M`. Es un modo de presentación, no una marca: no se captura.

L18. "no podemos pasar a T4 porque faltan elementos en el dock como el ease erase y el text. Ademas falta el puntero lazer y algo que no hemos visto antes es la opcion de poner un marco al cursor."
L19. Implementado en el modelo y en la UI, con 49 tests unitarios en verde: borrado por trazo con renumeración, láser transitorio con desvanecido y poda, texto colocado por click y confirmado, marco del cursor como modo. Verificación manual pendiente (el usuario la corre).
L20. Nota de proceso: las sondas de eventos inyectados requieren normalizar el estado con Escape antes de activar; una corrida que no lo hizo dejó el modo dibujo apagado y el tipeo inyectado terminó en el chat del usuario.
