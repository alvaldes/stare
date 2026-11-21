# Stare: rediseño del Setup Guide

Objetivo: rediseñar la pantalla del Setup Guide (`Sources/Stare/OnboardingView.swift`) para que se vea moderna y tenga jerarquía de acciones clara al pedir el permiso de Screen Recording, con inspiración tomada de 21st.
Rama: `feat/setup-guide-redesign` (creada desde `main` para estos commits). Runner: `swift test` + `Scripts/bundle.sh release install`. Entrega: `ask-on-risk`.

## Specs

S1. "hay que mejorar la UI de esta pantalla usa 21st para que luzca moderna y buena UX al aceptar los permisos y demas": la pantalla del Setup Guide se rediseña — moderna, con jerarquía clara, consultando 21st para inspiración. Se conservan los tres estados del permiso (`denied`, `grantedPendingRestart`, `granted`), los tres caminos existentes (abrir System Settings, continuar, "Not now") y el único permiso que la app pide (Screen Recording). No se agregan permisos ni pasos nuevos.

S2. Con el permiso ya concedido la acción primaria es **Continuar**. Hoy "Open System Settings…" sigue siendo el botón `.borderedProminent` y solo queda `.disabled` (`OnboardingView.swift:47-55`), así que la acción más prominente de la pantalla es una que ya no sirve; en ese estado no puede quedar visible como acción principal.

S3. Cada estado muestra una sola acción primaria y como mucho una secundaria: `denied` → abrir System Settings; `grantedPendingRestart` → reiniciar Stare (con el camino de re-autorizar que describe el copy del modelo); `granted` → Continuar. "Not now" se mantiene siempre, relegado.

S4. El contrato con la ventana no cambia: `OnboardingModel` como fuente de estado, los callbacks `onContinue`, `onRestart`, `onNotNow`, el refresco del `OnboardingWindowController` (aparecer, activación, timer) y las reglas de S1–S3 del documento `odd/tasks/onboarding-settings.md` (se muestra una vez, reabrible desde "Setup Guide…", cerrarla sin conceder la marca como vista).

S5. Accesibilidad y teclado: foco visible en cada control, Return dispara la acción primaria, Escape equivale a "Not now", contraste WCAG AA, y el artefacto de diseño respeta `prefers-reduced-motion`.

S6. La dirección visual se elige entre alternativas mostradas en el canvas de `design/setup-guide/` antes de escribir SwiftUI; la elegida se anota en el Log y las demás quedan como alternativas.

## Tasks

| ID | Tarea | Specs | Ruta | Commit |
| --- | --- | --- | --- | --- |
| T1 | Direcciones de diseño: `design/system.md` (sync del proyecto) + `design/setup-guide/` con tres artboards y su `design.json` | S1, S5, S6 | worker | hecho, sin commit: `design/system.md`, `design/system.html`, `design/setup-guide/` (elegido `03-permission-checklist.html`) |
| T2 | Reimplementar `OnboardingView.swift` con la dirección elegida, sin tocar el contrato de S4 | S2–S4 | worker, después de T1 | hecho, sin commit: `Sources/Stare/OnboardingView.swift` + `Sources/StareCore/OnboardingActionPlan.swift` |
| T3 | Extraer la regla "una acción primaria por estado" a `StareCore` con test, y pinear el copy de la guía | S2–S3 | worker, después de T2 | hecho, sin commit: `OnboardingActionPlanTests` (5 tests), suite 394 verde |

## Log

L1. Pedido original, textual: "[Image#2] hay que mejorar la UI de esta pantalla usa 21st para que luzca moderna y buena UX al aceptar los permisos y demas". La imagen es la guía con el permiso ya concedido: ícono de la app, "Stare", el párrafo de qué hace, la fila "Screen Recording on / Stare can draw over the screen." en verde, y tres acciones apiladas — "Open System Settings…" en azul primario (deshabilitado), "Continue" en gris, "Not now" como texto.

L2. Evidencia del código que sostiene S2: `OnboardingView.swift:47-55` deja "Open System Settings…" con `.buttonStyle(.borderedProminent)` y solo `.disabled(model.access == .granted)`, mientras "Continue" usa `.bordered` (`:57-60`). Con el permiso concedido la pantalla muestra la acción inútil como principal.

L3. Inspiración de 21st consultada (`get_inspiration`, query "macOS app onboarding permission setup screen…"): *Camera Permission Request Card* (tarjeta de permiso con acción), *Onboarding Checklist* (pasos con progreso), *Minimal Welcome Onboarding* (héroe centrado con un solo CTA), *Welcome Checklist Card* (checklist con barra de progreso), *Permissions Button* (par de acciones con microinteracción).
L4. T1: diseño creado en `design/setup-guide/` con `design.json` y tres artboards autocontenidos de 880×760 (ventana macOS dibujada con honestidad, icono nib en SVG, switcher de estado por teclado, foco visible, WCAG AA y `prefers-reduced-motion`): `01-status-hero.html` (héroe de estado con una acción primaria que se sustituye por estado), `02-two-step-guide.html` (guía de dos pasos con barra de acciones en el pie) y `03-permission-checklist.html` (tarjeta checklist con el permiso como única tarea). Sync del sistema en `design/system.md` + `design/system.html` desde `landing/src/style.css`, anotando que la ventana nativa debe usar colores semánticos de macOS, no los tokens web.
L5. T2/T3 implementados sin commit (estado de trabajo, sin confirmar): dirección elegida **03 · Permission checklist** (`design/setup-guide/03-permission-checklist.html`). `OnboardingView.swift` reescrito como tarjeta checklist — eyebrow, título, medidor de progreso, fila de tarea con copy del modelo y acciones por estado, pista posterior y "Not now" relegado al pie; colores semánticos de macOS. Contrato intacto (`OnboardingModel`, `onContinue`/`onRestart`/`onNotNow`, misma ventana de 460×430). La jerarquía «una acción primaria por estado» vive ahora en `OnboardingActionPlan` (StareCore, puro, de `ScreenRecordingAccess`) expuesta vía `OnboardingModel.actionPlan`, con 5 tests (`OnboardingActionPlanTests`); System Settings no existe como acción cuando el permiso está concedido. `swift test`: 389→394, 0 fallos; `swift build -c release`: OK.
L6. Comentario de canvas `vjbbmdsz` sobre `03-permission-checklist.html`, textual: "this one but in a minimalistic and no so big window. Remenber to use de logo image of stare". Aplicado en dos pasos: (a) el artboard pasa a 460×430 (el tamaño real de la ventana, `OnboardingWindowController`), pierde eyebrow, medidor y línea posterior, y estrena el logo real de `Resources/app-icon.svg` inline a 58 px; (b) lo mismo se lleva a `OnboardingView.swift` — icono de la app en el encabezado (`NSApp.applicationIconImage`, 58 pt), fuera el eyebrow/medidor/línea posterior. El copy de estado sigue viniendo del modelo; la jerarquía, de `OnboardingActionPlan`. Comentario resuelto en el canvas.
L7. Verificación independiente (`gentle-ai-verify`) sobre la vista y el artboard: PASS en jerarquía desde `OnboardingActionPlan`, `.accessibilityElement(children: .contain)`, shortcuts, autocontención del artboard, fidelidad del logo inline respecto de `Resources/app-icon.svg`, correspondencia binario instalado ↔ fuente, y tracking del doc. Advisories corregidos: (a) la pista de teclado usaba `tertiaryLabelColor` (~1.86:1, bajo AA) y pasa a `secondaryLabelColor` — residual anotado: 3.84:1 sigue bajo 4.5 para texto chico; (b) comentario de cabecera de `OnboardingView.swift` que aún mencionaba el medidor; (c) `design.json` con el brief diciendo "880×760 window" cuando la ventana real es 460×430. Añadidos `testGrantedPlanIsExactlyOneAction` y `testPlanOrderIsPrimaryThenSecondary`: suite 394→396, 0 fallos. Handoff del artboard marcado `implemented` en el canvas (la app es nativa: no hay `previewUrl` de loopback).
