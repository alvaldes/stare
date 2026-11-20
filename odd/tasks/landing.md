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
| T1 | Scaffold, Tailwind, pipeline `toSSG` → static assets, wrangler sin costo | S1–S4 | inline | pendiente | |
| T2 | Sistema visual y secciones (hero, features, atajos, download, FAQ, footer) | S6–S9 | inline | pendiente | |
| T3 | Motor de la demo: herramientas, tintas, undo, Esc, toolbar | S5 | inline | pendiente | |
| T4 | Captura S → card con Copy al portapapeles | S5 | inline | pendiente | |
| T5 | Botón de descarga con GitHub Releases y "Coming soon" | S9 | inline | pendiente | |
| T6 | README de `landing/`: dev, build, deploy gratis | S3–S4 | inline | pendiente | |

Ruta: todo inline; T2 y T3 comparten tokens visuales y la toolbar, así que no son unidades independientes para escritores paralelos.

## Log

L1 (2026-11-20, pedido original): "sin interferir en los trabajos que se estan haciendo en este repo quiero ir pensando en la landing. Ir trabajando en esto me va a permitir ir adelantando. Por ahora no tengo mucho pero si tenemos inpiracion que son las paginas de las app en las que se basa stare. Si tengo claro que debe haber una seccion donde se pueda probar la app como una especie de demo. Debe tener un estilo moderno que se esilice como la verdadera app y puedes revisar 21st para ideas.Antes de empezar a implementar hazme todas las pregutnas que necesites para tener todo claro. un detalle es que quiero usar https://hono.dev/ si es posible y asi aprendo a usar este framework que es bien ligero"
L2 (2026-11-20, respuestas): ubicación "Carpeta en este repo"; demo "Interactiva en el navegador"; deploy "Cloudflare"; CTA "Descargar la app"; marca "No, proponela vos"; inspiración Lasso + https://presentifyapp.com/ + https://www.epicpencil.es/en/; idioma "Inglés"; alcance "Núcleo fiel"; UI "hono/jsx + Tailwind".
L3 (2026-11-20): "estoy viendo lo de de honoX y no se si es lo que usa la doc offical porque lo que quiero usar es pnpm create hono@latest" → template `cloudflare-workers+vite`, "con claudflare-workers+vite siempre que lo que vayamos a usar de claudflare sea gratis". Verificado en developers.cloudflare.com: Workers Free = 100k requests/día; static assets gratis e ilimitados.
L4 (2026-11-20): pre-render estático, "con lo recomendado". El plugin de Cloudflare para Vite no tiene pre-render genérico (solo TanStack Start / React Router), así que usamos `toSSG` sobre el Worker compilado.
L5 (investigación): ninguna referencia tiene una demo que termine en captura + copia; Epic Pen es la única con canvas en el navegador (solo dibujar). Ese es el diferencial de Stare.
