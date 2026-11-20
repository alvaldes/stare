# Landing de Stare

Objetivo: landing pública de Stare con demo interactiva en el navegador. Rama `feat/landing` (worktree `stare-wt-landing`), carpeta `landing/`.
Entrega: `ask-on-risk`. Runner: `pnpm` + Vitest (lógica de la demo) y `pnpm build` (pipeline estático).

## Specs

S1. "sin interferir en los trabajos que se estan haciendo en este repo": vive en `landing/` de este repo, en su propio worktree y rama; no toca `main`, `feat/t4-capture-core` ni `feat/t6-settings`.
S2. Framework: "quiero usar https://hono.dev/ si es posible y asi aprendo a usar este framework". Scaffold con "pnpm create hono@latest", template `cloudflare-workers+vite` (Hono puro, no HonoX). UI con `hono/jsx` + Tailwind; la demo con `hono/jsx/dom`.
S3. Deploy en Cloudflare Workers, "siempre que lo que vayamos a usar de claudflare sea gratis porque no tengo pensado pagar nada de claudflare ya que este proyecto va a ser de codigo abierto". Solo plan Workers Free.
S4. Pre-render estático (decisión "con lo recomendado"): el build genera HTML con `toSSG` de `hono/ssg` y Cloudflare lo sirve como static assets (gratis e ilimitados); visitar la landing no invoca al Worker.
S5. "debe haber una seccion donde se pueda probar la app como una especie de demo". Interactiva en el navegador, alcance "Núcleo fiel": Pen, Highlighter, Arrow, Line, Rectangle, Ellipse, Numbered steps con las teclas de la app (P H A L R O C); ocho tintas en 1–8 (rojo, naranja, amarillo, verde, azul, violeta, blanco, negro); ⌘Z deshace; Esc limpia; toolbar como la real; S captura y genera una card con Copy. Text, laser y eraser quedan fuera.
S6. "Debe tener un estilo moderno que se esilice como la verdadera app y puedes revisar 21st para ideas". Ideas de 21st.dev adaptadas a mano (sin React). Identidad visual propuesta por nosotros (no hay marca), alineada con macOS 26.
S7. Inspiración: "las paginas de las app en las que se basa stare": https://www.trylasso.online/, https://presentifyapp.com/, https://www.epicpencil.es/en/. Estructura e ideas, nunca copy ni marca.
S8. Contenido en inglés.
S9. CTA principal: descargar la app. Apunta al último GitHub Release; mientras no exista ninguno muestra "Coming soon". Sin costo (GitHub Releases, sin R2).

## Tasks

| ID | Tarea | Specs | Ruta | Estado | Commit |
| --- | --- | --- | --- | --- | --- |
| T1 | Scaffold, Tailwind, pipeline `toSSG` → static assets, wrangler sin costo | S1–S4 | inline | hecho | b7a4af5 |
| T2 | Sistema visual y secciones (hero, features, atajos, download, FAQ, footer) | S6–S9 | inline | hecho | ver Log L8 |
| T3 | Motor de la demo: herramientas, tintas, undo, Esc, toolbar | S5 | inline | hecho | ver Log L8 |
| T4 | Captura S → card con Copy al portapapeles | S5 | inline | hecho | ver Log L8 |
| T5 | Botón de descarga con GitHub Releases y "Coming soon" | S9 | inline | hecho | ver Log L8 |
| T6 | README de `landing/`: dev, build, deploy gratis | S3–S4 | inline | hecho | ver Log L8 |
| T7 | Efectos con vida (aurora, grilla, glass nav, blur-in, sheen, spotlight, reveals, atajos vivos) | S6 | inline | hecho, sin commit | |
| T8 | Logo: plumilla abierta sobre vidrio aurora + glifo relleno para barra de menú | S6 | inline | hecho, sin commit | |
| T8b | Nav alineado al contenedor y logo centrado; mini-escena animada en el hero (dibujar → S → Copied → chat) | S6 | inline | hecho, sin commit | |
| T9 | Commitear T2–T8b en slices en `feat/landing` | S1 | inline | pendiente | |
| T10 | Licencia (decisión del usuario) y repo público `alvaldes/stare`; hoy los links dan 404 y "open source" no es cierto aún | S9 | — | pendiente, bloquea publicar | |
| T11 | Primer deploy: `pnpm wrangler login` (usuario, interactivo) + `pnpm deploy` | S3–S4 | — | pendiente, bloquea publicar | |
| T12 | Imagen og:image generada en el build para previews en redes | S6 | inline | pendiente | |
| T13 | Auditoría Lighthouse: performance (blur de auroras en móviles) y accesibilidad | S6 | inline | pendiente | |
| T14 | Página 404 con el mismo estilo | S6 | inline | pendiente | |
| T15 | Demo: sumar text, laser, eraser (T7 de la app) y quizás el editor, cuando la app los tenga | S5 | inline | esperando app | |
| T16 | Video corto real de la app (dibujar → S → pegar) cuando la captura esté terminada | S7 | — | esperando app | |
| T17 | Mergear `feat/landing` a `main` cuando T4/T6 de la app se integren | S1 | — | esperando app | |
| T18 | Aplicar logo y glifo en la app: reemplazar `pencil.tip` en `StatusBarController.swift` (template image, relleno siempre) | S6 | — | esperando app | |

Ruta: todo inline; T2 y T3 comparten tokens visuales y la toolbar, así que no son unidades independientes para escritores paralelos.

## Log

L1 (2026-11-20, pedido original): "sin interferir en los trabajos que se estan haciendo en este repo quiero ir pensando en la landing. Ir trabajando en esto me va a permitir ir adelantando. Por ahora no tengo mucho pero si tenemos inpiracion que son las paginas de las app en las que se basa stare. Si tengo claro que debe haber una seccion donde se pueda probar la app como una especie de demo. Debe tener un estilo moderno que se esilice como la verdadera app y puedes revisar 21st para ideas.Antes de empezar a implementar hazme todas las pregutnas que necesites para tener todo claro. un detalle es que quiero usar https://hono.dev/ si es posible y asi aprendo a usar este framework que es bien ligero"
L2 (2026-11-20, respuestas): ubicación "Carpeta en este repo"; demo "Interactiva en el navegador"; deploy "Cloudflare"; CTA "Descargar la app"; marca "No, proponela vos"; inspiración Lasso + https://presentifyapp.com/ + https://www.epicpencil.es/en/; idioma "Inglés"; alcance "Núcleo fiel"; UI "hono/jsx + Tailwind".
L3 (2026-11-20): "estoy viendo lo de de honoX y no se si es lo que usa la doc offical porque lo que quiero usar es pnpm create hono@latest" → template `cloudflare-workers+vite`, "con claudflare-workers+vite siempre que lo que vayamos a usar de claudflare sea gratis". Verificado en developers.cloudflare.com: Workers Free = 100k requests/día; static assets gratis e ilimitados.
L4 (2026-11-20): pre-render estático, "con lo recomendado". El plugin de Cloudflare para Vite no tiene pre-render genérico (solo TanStack Start / React Router), así que usamos `toSSG` sobre el Worker compilado.
L5 (investigación): ninguna referencia tiene una demo que termine en captura + copia; Epic Pen es la única con canvas en el navegador (solo dibujar). Ese es el diferencial de Stare.
L6 (T1): RED `src/prerender.test.ts` → GREEN. El Worker compilado sale en `dist/<nombre_del_worker>` (`stare_landing`); `scripts/prerender.ts` busca el directorio con `wrangler.json` y el build arranca con `rm -rf dist`.
L7 (T3–T5): 17 tests (atajos, sesión, puntas de flecha portadas de PathBuilder, selección de release). Verificado en navegador: dibujo, S → card, la captura excluye toolbar y cards. Corregidos: `aria-pressed` vacío en hono/jsx/dom, feedback inmediato al capturar, toolbar en dos filas en mobile.
L8 (2026-11-20): "le falta algo de vida ese fondo esta muy plano y no tiene animaciones. El demo funciona pero el resto no tiene vida. de verdad revisaste 21st?" → T7.
L9 (2026-11-20): logo "el que pusiste esta feisimo" → tras 3 rondas: D3 nib, "N1 pero la punta del boligrafo no es cerrada es abbireta como una real estilografica"; barra de menú "definitivamente filled siempre" → T8. SF Symbols no se puede usar como logo (licencia).
L10 (2026-11-20): "en la app aun no podemos tocar nada porque aun se esta trabajando asi que seguimos trabajando en la landing y depues mesclamos" → T15–T18 esperan a la app. "pon todo esto en cosas que hacer para retomarlas despues" → T9–T18.
L11 (2026-11-20): barra de menú de la demo: "debe estar el logo de mac con el nombre de la app Stare y la hora real". Hora real hecha (clock.ts, 3 tests). Logo de Apple: se advirtió que las guías de Apple para terceros lo prohíben sin licencia escrita; el usuario respondió "el icono de la mac claro que se puede usar" y, tras la explicación del riesgo, eligió "1." (la manzana, aceptando el riesgo). Implementado con el glifo del sistema U+F8FF solo en dispositivos Apple; círculo neutro en el resto. Pendiente: nombre "Stare" vs "Ledger" en negrita (Stare no toma el foco, en un Mac real se vería la app de abajo).
L12 (2026-11-20): "porque usar ascii cuando puedes usar svg o algun otro icono de internet como el que esta en svgl.app" → la manzana pasa a ser un path SVG (svgl.app) dentro de DemoScreen; se eliminan el glifo U+F8FF, el círculo de fallback y la detección de plataforma. Se ve igual en todos los sistemas.
