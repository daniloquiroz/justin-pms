# BASE-001 — Verificar baseline de HAIP y documentarlo

| Campo | Valor |
|-------|-------|
| Historia | Verificar baseline: build, typecheck y pruebas de HAIP en verde en `develop`; documentar en `02-current-haip-baseline.md` versiones reales del lockfile y módulos a deshabilitar (channel manager, booking engine, agentes de revenue) |
| Depende de | — |
| Estado del plan | **LISTA** (ver "Preguntas abiertas": Q-012 se registra pero NO bloquea esta historia) |
| Tipo | Verificación + documentación. Sin cambios de código de producto, sin migraciones. |
| Base | `vendor/haip-v3.1.1` (rama de solo lectura), integración en `develop` |

## 1. Objetivo

Dejar constancia verificable y reproducible de:

1. Que el fork de HAIP en `develop` compila, pasa lint, typecheck y la suite de pruebas
   (con los servicios que la suite necesita), en Linux (referencia CI) y en Windows local.
2. Las versiones **reales resueltas en `pnpm-lock.yaml`** (no las del README, que no están
   alineadas con los manifiestos — la propuesta lo señala como primer ticket técnico).
3. El inventario de módulos de HAIP y, en particular, cómo están acoplados y cómo se
   deshabilitarían los tres que nombra la historia: channel manager, booking engine y agentes
   de revenue. Documentar, no deshabilitar en código.

## 2. Ruta del entregable

`docs/project/02-current-haip-baseline.md`

Justificación: la propuesta (`docs/project/referencia/propuesta-pms.pdf`, sección "Entregables
preparados para trabajar con Claude") define el paquete `/docs/project/` con numeración
`00-vision.md`, `01-business-context.md`, `02-current-haip-baseline.md`, `03-domain-model.md`, …
Se respeta exactamente esa ruta y nombre. No va en `referencia/` (esa carpeta es para insumos
externos, no para documentos vivos del proyecto).

## 3. Criterios de aceptación (Gherkin)

```gherkin
Feature: Baseline verificado de HAIP en develop

  Scenario: Identidad de la base
    Given la rama develop y la rama vendor/haip-v3.1.1
    When se consulta 02-current-haip-baseline.md
    Then el documento indica el SHA exacto de vendor/haip-v3.1.1 y el SHA de develop verificado
    And lista los commits de develop que no están en vendor/haip-v3.1.1 (git log vendor/haip-v3.1.1..develop)
    And registra la discrepancia entre la release citada en la propuesta (v3.0.7) y la congelada (v3.1.1)

  Scenario: Comandos de calidad en verde
    Given un clon limpio de develop con pnpm install --frozen-lockfile
    When se ejecutan pnpm build, pnpm lint, pnpm typecheck y la suite de pruebas con Postgres y Redis
    Then todos terminan con código de salida 0
    And el documento registra, por comando, fecha, SO, versión de Node/pnpm, duración y resultado
    And el conteo de pruebas aprobadas coincide con docs/test-stats.json (2602 pruebas / 303 archivos)
        o se explica cada diferencia (pruebas omitidas por falta de servicio, plataforma, etc.)

  Scenario: Fallo en algún comando
    Given algún comando de calidad falla en develop
    When se documenta el resultado
    Then el fallo queda registrado con salida resumida y causa probable
    And NO se corrige dentro de las subtareas de documentación
    And el orquestador abre la subtarea condicional BASE-001-fix (ver sección 9) o escala a Danilo

  Scenario: Versiones reales del lockfile
    Given pnpm-lock.yaml (lockfileVersion 9.0) en develop
    When se consulta la sección de versiones
    Then cada dependencia clave aparece con la versión RESUELTA en el lockfile por workspace
    And se listan las discrepancias README vs manifiestos (p. ej. README declara React 19)
    And se registran las imágenes Docker usadas (postgres, redis, keycloak, minio)

  Scenario: Módulos a deshabilitar documentados
    Given los módulos de apps/api/src/modules y la composición de AppModule
    When se consulta la sección de módulos
    Then aparecen channel manager, booking engine y agentes de revenue con:
      | dato                                             |
      | archivos/módulos Nest implicados                 |
      | dependencias entrantes y salientes               |
      | listeners de eventos que se activan solos        |
      | flags de entorno y configuración por propiedad   |
      | permisos RBAC y rutas del dashboard asociadas    |
      | estrategia de deshabilitación y su riesgo        |
    And no se modifica ningún archivo fuera de docs/project/
```

## 4. Hallazgos ya verificados por el arquitecto (insumo para el documento)

Los desarrolladores deben **re-verificar** cada dato antes de copiarlo al entregable.

### 4.1 Scripts raíz confirmados (`package.json`)

| Script | Comando real | Notas |
|--------|--------------|-------|
| `pnpm build` | `pnpm -r run build` | Existe. `apps/dashboard` y `apps/booking` usan `tsc -b && vite build`; paquetes con `tsup`; API con `nest build`. |
| `pnpm lint` | `pnpm -r run lint` | Existe. ESLint 9 flat config (`eslint.config.mjs`). |
| `pnpm typecheck` | `pnpm -r run typecheck` | Existe. Requiere `dist/` de `shared`, `database` y `booking-requests` construidos antes (el CI de HAIP construye esos tres primero). |
| `pnpm test` | `pnpm -r run test` | Existe. Vitest 2.x en cada workspace. |
| `node scripts/sync-test-count.mjs --check` | Corre toda la suite con reporter JSON y falla si el conteo publicado en `README.md`/`docs/test-stats.json` está desactualizado | Es el comando que usa el CI. **Usar siempre `--check`**: sin esa bandera reescribe `README.md` y `docs/test-stats.json` (prohibido en esta historia). |
| `pnpm db:migrate` | `tsx src/run-migrations.ts` en `packages/database` | Necesario antes de las pruebas con base de datos. |
| `pnpm --filter @telivityhaip/api run test:e2e` | `vitest.e2e.config.ts` (`*.e2e-spec.ts`) | No forma parte de `pnpm test`. Opcional en el baseline; registrar si se corre. |
| `pnpm --filter @telivityhaip/api run test:release-smoke` | `RELEASE_SMOKE=1 vitest run …` | Sintaxis POSIX: **falla tal cual en Windows** (ver 6.3). Job separado en CI. |

Workspaces (`pnpm-workspace.yaml`): `apps/*` y `packages/*` → `@telivityhaip/api`, `dashboard`,
`booking`, `database`, `shared`, `booking-requests`. Los directorios `tools/*` y `ops/harden/cli`
**no** están en el workspace y no entran en `pnpm -r`.

Toolchain declarado: `engines.node >=20`, `engines.pnpm >=9`, `packageManager: pnpm@9.15.4`,
CI con Node 22. Override `@types/node ^22`.

### 4.2 Pruebas que dependen de servicios

- La suite usa `DATABASE_URL` (por defecto `postgresql://haip:haip@localhost:5432/haip_test`) y
  `REDIS_URL` (`redis://localhost:6379`). Varios specs usan `describe.skipIf(...)` cuando no hay
  base: `packages/database/src/migration-runner.spec.ts`,
  `packages/database/src/integration-principal.link.spec.ts`,
  `apps/api/src/modules/payment/redsys-*.spec.ts` (usan `REDSYS_TEST_DATABASE_URL`),
  `apps/api/src/common/database/accepted-pricing-lock.postgres.spec.ts`,
  `apps/api/src/modules/booking-request/*regression.spec.ts`,
  `packages/booking-requests/src/database/*.postgres.spec.ts`.
- Consecuencia: `pnpm test` sin servicios puede quedar "verde" con pruebas omitidas. El baseline
  **válido** es con Postgres + Redis y `--check` contra `docs/test-stats.json` (2602/303).
- `docker-compose.yml` crea solo la base `haip`; la base `haip_test` hay que crearla a mano.

### 4.3 Composición de módulos (API)

`apps/api/src/app.module.ts` importa estáticamente 48 módulos de dominio + `DatabaseModule`, más
el paquete opcional `@telivityhaip/booking-requests` solo si `HAIP_BOOKING_REQUESTS=true`
(`apps/api/src/booking-requests.bootstrap.ts`). No existe hoy un mecanismo genérico de
activación/desactivación de módulos por entorno. Flags de entorno existentes relevantes:
`HAIP_BOOKING_REQUESTS`, `HAIP_AI_ENABLED` (LLM, opt-in), `SERVE_DASHBOARD`, `SERVE_BOOKING`,
`SWAGGER_ENABLED`, `AUTH_ENABLED`, `HAIP_ALLOW_INSECURE`, `STRIPE_MODE`.

### 4.4 Los tres módulos que nombra la historia

**Channel manager** — `apps/api/src/modules/channel/`
- `ChannelModule` importa `ReservationModule`, `WebhookModule`, `MediaModule`, `ReviewsModule`.
  Ningún otro módulo importa `ChannelModule` (solo `AppModule`).
- Controladores siempre montados: `ChannelController` y receptores inbound de Booking.com,
  Expedia, DerbySoft y Channex (además adaptadores SiteMinder, Beds24 y "wave3-console").
- Listeners automáticos: `AriService` escucha `reservation.created|modified|cancelled`,
  `rate_plan.updated`, `rate_restriction.*`; `ContentSyncService` escucha
  `property.content_updated` y `roomtype.content_updated`. Son fire-and-forget (capturan errores);
  verificar que sin `channel_connections` activas no hacen llamadas externas.
- Configuración por propiedad: tabla de conexiones con `status` (default `pending_setup`) e
  `is_active` (`packages/database/src/schema/channel.ts`).
- RBAC: permiso `channels.manage` (nav `/channels`) en `packages/shared/src/permissions-catalog.ts`.
- Dashboard: ruta `/channels/*` (`apps/dashboard/src/App.tsx`), `Sidebar.tsx`, `IcalCalendars.tsx`.
- docker-compose: servicios mock bajo el perfil `channels` (no arrancan por defecto) y variables
  `BOOKING_COM_*`, `SITEMINDER_*`, `EXPEDIA_*`, `DERBYSOFT_*` en el servicio `api`.
- Relacionado (decidir en Q-012): `ical` (calendarios iCal) y `connect` (API para agentes externos).

**Booking engine** — `apps/api/src/modules/booking-engine/` + `apps/booking/` (widget)
- `BookingEngineModule` importa `ConnectModule`, `ReservationModule`, `RatePlanModule`,
  `TaxModule`, `GuestModule`, `FolioModule`, `PaymentModule`, `AccountingModule`, `AuthModule`,
  `AncillaryModule`, `PolicyModule`. Exporta servicios y guards que consume
  `booking-requests.bootstrap.ts` **solo** cuando `HAIP_BOOKING_REQUESTS=true`.
- Configuración por propiedad: `booking_engine_configs.is_enabled` con default `false`
  (`packages/database/src/schema/booking-engine.ts`); el servicio responde 403 "Direct booking is
  not enabled for this property" si está apagado. Con `AUTH_ENABLED=true` exige booking key.
- El widget `apps/booking` se sirve en `/booking` solo con `NODE_ENV=production` o
  `SERVE_BOOKING=true`.
- Dashboard: `components/admin/BookingEngineSettings.tsx` (Settings → Booking Engine) y
  `/booking-requests/*` detrás de `VITE_HAIP_BOOKING_REQUESTS`.

**Agentes de revenue** — `apps/api/src/modules/agent/`
- Enum `agent_type` (`packages/database/src/schema/agent.ts`): `pricing`, `demand_forecast`,
  `channel_mix`, `overbooking`, `night_audit`, `housekeeping`, `cancellation`, `guest_comms`,
  `review_response`, `ar_collections`, `deposit_risk`, `group_pickup`, `revenue_manager`.
- HAIP agrupa como "money" (`agent-autopilot-tiers.ts`): `pricing`, `overbooking`, `channel_mix`,
  `revenue_manager`, `group_pickup`. `demand_forecast` alimenta a pricing y `cancellation` es
  predictivo. **Definición propuesta de "agentes de revenue"** para el documento: los cinco
  "money" + `demand_forecast` (+ `cancellation` marcado como dudoso). La frontera exacta queda en
  Q-012; el documento debe mostrarla como propuesta, no como decisión.
- Configuración por propiedad: `agent_configs.is_enabled` default `false`, `mode` default
  `suggest`. Entrenamiento/ejecución programada por cron externo (`scripts/cron/agent-runs.sh`,
  `docs/deployment.md`).
- **Acoplamiento crítico**: `EmailModule`/`EmailService` viven en
  `agent/guest-comms/` y los importan `ReservationModule`, `GuestCheckInModule` y el bootstrap de
  booking-requests. Quitar `AgentModule` de `AppModule` es posible; **borrar la carpeta `agent/`
  rompe reservas y check-in**.
- Listeners del `AgentModule` que corren solos: `GuestCommsListener`
  (`reservation.created|checked_in|checked_out` → `runAgent('guest_comms')`) y
  `ReviewIngestListener` (`guest.review.ingested`). `StaffNotificationListener` escucha
  `agent.decision_created`. Estos NO son de revenue: quitar el módulo completo apagaría también
  comunicaciones al huésped (decisión en Q-012).
- LLM: `LlmModule` opt-in con `HAIP_AI_ENABLED=true`; lo usan `AgentModule` y `HelpModule`.
- RBAC: `revenue.manage` (nav `/revenue`); dashboard `/revenue/*` (`pages/Revenue.tsx`).

### 4.5 Estrategias de deshabilitación a documentar (sin aplicarlas)

| Nivel | Qué es | Toca núcleo HAIP | Reversible | Cuándo |
|-------|--------|------------------|------------|--------|
| A. Operativo | Dejar en default/apagado la config por propiedad (`booking_engine_configs.is_enabled=false`, `agent_configs.is_enabled=false`, sin `channel_connections`), no programar `agent-runs.sh`, no levantar perfil `channels`, `SERVE_BOOKING` sin definir, `HAIP_AI_ENABLED` sin definir | No | Sí | Desde ya (MVP) |
| B. RBAC | No otorgar `channels.manage` ni `revenue.manage` en los roles propios (RBAC-001); oculta nav y bloquea endpoints | No (usa catálogo existente) | Sí | RBAC-001 |
| C. Composición | Import condicional en `AppModule` por flag de entorno (patrón `bookingRequestsModules()`), extrayendo antes `EmailModule` fuera de `agent/` o manteniéndolo importado | Sí (conflicto con upstream) | Sí | Historia futura, solo si Q-012 lo pide |
| D. Eliminación | Borrar módulos | Sí | No | Descartado (rompe merges de upstream y dependencias) |

Recomendación técnica a registrar: A + B para el MVP; C solo con decisión explícita.

## 5. Módulos de HAIP que se reutilizan y cómo

No aplica código. Se reutilizan como **fuente de verdad documental**: `package.json` raíz y de
cada workspace, `pnpm-lock.yaml`, `.github/workflows/ci.yml` (orden de pasos y variables de
entorno de prueba), `docker-compose.yml`, `scripts/sync-test-count.mjs`, `docs/test-stats.json`,
`apps/api/src/app.module.ts`, `packages/shared/src/permissions-catalog.ts`.

## 6. Cómo correr el baseline

### 6.1 Secuencia de referencia (igual al CI de HAIP)

```text
corepack enable                      # usa pnpm@9.15.4 de packageManager
pnpm install --frozen-lockfile
pnpm build
pnpm lint
pnpm typecheck
docker compose up -d postgres redis  # SOLO estos dos servicios
<crear base haip_test>               # ver 6.2 / 6.3
DATABASE_URL=postgresql://haip:haip@localhost:5432/haip_test pnpm db:migrate
DATABASE_URL=… REDSYS_TEST_DATABASE_URL=… REDIS_URL=redis://localhost:6379 CI=true FORCE_COLOR=0 \
  node scripts/sync-test-count.mjs --check
```

No usar `docker compose up` sin argumentos: construye la imagen de la API, corre `init`
(migrate + seed demo) y arranca con `AUTH_ENABLED=false`; no es necesario para el baseline.

### 6.2 Linux / WSL2 / CI

```bash
docker exec haip-postgres createdb -U haip haip_test
export DATABASE_URL=postgresql://haip:haip@localhost:5432/haip_test
export REDSYS_TEST_DATABASE_URL=$DATABASE_URL REDIS_URL=redis://localhost:6379 CI=true FORCE_COLOR=0
pnpm db:migrate && node scripts/sync-test-count.mjs --check
```

### 6.3 Windows (PowerShell)

Requisitos: Docker Desktop con backend WSL2, Node 22 LTS, `corepack enable`. Puertos 5432 y 6379
libres (si hay un PostgreSQL nativo de Windows, detenerlo o cambiar el puerto en la URL).

```powershell
docker compose up -d postgres redis
docker exec haip-postgres createdb -U haip haip_test
$env:DATABASE_URL = 'postgresql://haip:haip@localhost:5432/haip_test'
$env:REDSYS_TEST_DATABASE_URL = $env:DATABASE_URL
$env:REDIS_URL = 'redis://localhost:6379'
$env:CI = 'true'; $env:FORCE_COLOR = '0'
pnpm db:migrate
node scripts/sync-test-count.mjs --check
# release-smoke (opcional): el script npm usa sintaxis POSIX, invocarlo así:
$env:RELEASE_SMOKE = '1'
pnpm --filter @telivityhaip/api exec vitest run src/release-smoke.integration.spec.ts
Remove-Item Env:RELEASE_SMOKE
```

Trampas conocidas en Windows a registrar en el documento si se reproducen:
- Scripts `clean` usan `rm -rf` (no funcionan en cmd). No se necesitan para el baseline.
- `test:release-smoke` usa `VAR=valor comando` (POSIX).
- `.gitattributes` fuerza LF; si el clon se hizo antes de esa regla, `keycloak/init-keycloak-db.sh`
  con CRLF rompe el init de Postgres (`docker compose down -v` y re-clonar/normalizar).
- Rutas largas: si `pnpm install` falla por longitud de ruta, habilitar `git config core.longpaths true`
  y LongPathsEnabled en Windows; registrar si ocurrió.

## 7. Archivos a crear o modificar

| Archivo | Acción | Subtarea |
|---------|--------|----------|
| `docs/project/02-current-haip-baseline.md` | Crear (esqueleto + resultados de verificación) | S1 |
| `docs/project/02-current-haip-baseline.md` | Completar sección de versiones del lockfile | S2 |
| `docs/project/02-current-haip-baseline.md` | Completar sección de inventario y módulos a deshabilitar | S3 |
| `docs/project/open-questions.md` | Q-012 ya registrada por el arquitecto | — |
| `docs/project/backlog.md` | Solo el orquestador (estado y PRs) | — |

Prohibido en esta historia: tocar `apps/`, `packages/`, `.github/`, `README.md`,
`docs/test-stats.json`, `pnpm-lock.yaml` o cualquier `package.json`.

## 8. Migración, RBAC, auditoría y webhooks

- Migración de base de datos: **ninguna**.
- Permisos RBAC nuevos: **ninguno** (solo se documentan `channels.manage` y `revenue.manage`
  existentes como palanca para RBAC-001).
- Eventos de auditoría/webhook: **ninguno**.

## 9. Subtareas (una por PR, en orden)

Las tres primeras son de tipo docs, editan el mismo archivo y deben fusionarse **en secuencia**
(no en paralelo) para evitar conflictos. Mientras BASE-002 no exista, el CI de HAIP solo corre
en PRs a `main`; los PRs a `develop` no tendrán CI automático y la verificación es la ejecución
local documentada.

### S1 — `feat/BASE-001-baseline-verify`
- Tipo: docs (ejecuta comandos; no cambia código). Agente: `desarrollador-backend`.
- Archivos: crear `docs/project/02-current-haip-baseline.md` con estas secciones:
  1. Identidad de la base: SHA de `vendor/haip-v3.1.1`, SHA de `develop` verificado, salida de
     `git log --oneline vendor/haip-v3.1.1..develop`, nota v3.0.7 (propuesta) vs v3.1.1 (congelada).
  2. Toolchain usado: SO, `node -v`, `pnpm -v`, `docker version` (cliente/servidor), fecha.
  3. Resultados por comando (tabla: comando, entorno, exit code, duración, observaciones) para
     `pnpm install --frozen-lockfile`, `pnpm build`, `pnpm lint`, `pnpm typecheck`,
     `pnpm test` sin servicios (informativo: nº de pruebas omitidas),
     `node scripts/sync-test-count.mjs --check` con Postgres + Redis, y opcionalmente
     `test:e2e` y release-smoke.
  4. Conteo de pruebas vs `docs/test-stats.json` y explicación de diferencias.
  5. "Cómo correr el baseline en local" con las instrucciones de la sección 6 de este plan,
     ajustadas a lo que realmente funcionó.
  6. Secciones vacías con encabezado y "Pendiente — S2" / "Pendiente — S3".
- Criterios de aceptación:
  - Los cuatro comandos de calidad y la suite con servicios están registrados con exit code real.
  - Si todo está verde: el documento lo declara explícitamente con SHA y fecha.
  - Si algo falla: queda registrado con extracto de error (sin secretos ni rutas personales) y la
    subtarea se entrega igual; el orquestador decide S4.
  - `git diff --name-only develop` solo muestra `docs/project/02-current-haip-baseline.md`.
  - `README.md` y `docs/test-stats.json` sin cambios (`git status` limpio salvo el doc).
- Verificación (la ejecuta el desarrollador y la repite el tester):
  `pnpm install --frozen-lockfile`, `pnpm build`, `pnpm lint`, `pnpm typecheck`,
  `pnpm db:migrate` (con `DATABASE_URL` de prueba), `node scripts/sync-test-count.mjs --check`.

### S2 — `feat/BASE-001-lockfile-versions`
- Tipo: docs. Agente: `desarrollador-backend`.
- Archivos: `docs/project/02-current-haip-baseline.md` (sección "Versiones reales del lockfile").
- Contenido mínimo:
  - `lockfileVersion` y `packageManager`.
  - Tabla por workspace (`api`, `dashboard`, `booking`, `database`, `shared`, `booking-requests`)
    con rango declarado y **versión resuelta** de: `typescript`, `@nestjs/core`, `@nestjs/common`,
    `@nestjs/swagger`, `@nestjs/event-emitter`, `@nestjs/websockets`, `socket.io`, `drizzle-orm`,
    `drizzle-kit`, `postgres`, `bullmq`, `class-validator`, `class-transformer`, `decimal.js`,
    `stripe`, `jsonwebtoken`, `jwks-rsa`, `passport`, `vitest`, `@swc/core`, `tsup`, `eslint`,
    `react`, `react-dom`, `react-router-dom`, `@tanstack/react-query`, `vite`, `tailwindcss`,
    `keycloak-js`, `socket.io-client`, `i18next`, `zod`.
  - Imágenes Docker y versión: `postgres:16-alpine`, `redis:7-alpine`,
    `quay.io/keycloak/keycloak:24.0`, `minio/minio:latest` (marcar `latest` como riesgo de
    reproducibilidad).
  - Discrepancias README vs manifiestos/lockfile (mínimo: README línea "React 19 + Vite" vs
    React 18.3.x resuelto; revisar también Tailwind).
  - Método de extracción reproducible (p. ej. `pnpm list -r --depth 0 --json` o lectura de la
    sección `importers` del lockfile) para que un tercero pueda repetirlo.
- Criterios de aceptación:
  - Cada versión de la tabla coincide con `pnpm-lock.yaml` (el revisor contrasta al menos 10 al azar
    con `pnpm why <paquete> -r` o búsqueda en el lockfile).
  - Ninguna versión se toma del README.
  - Solo cambia `docs/project/02-current-haip-baseline.md`.
- Verificación: `pnpm install --frozen-lockfile` (confirma que el lockfile no cambia) y
  `git status` limpio salvo el doc. No se requiere correr la suite.

### S3 — `feat/BASE-001-module-inventory`
- Tipo: docs. Agente: `desarrollador-backend`.
- Archivos: `docs/project/02-current-haip-baseline.md` (sección "Inventario de módulos y módulos
  a deshabilitar").
- Contenido mínimo:
  - Tabla de los 48 módulos importados por `AppModule` (más submódulos no importados en la raíz,
    como `MigrationLegacyIdMapModule` y `agent/guest-comms/EmailModule`) + `booking-requests`
    (paquete opcional) + apps `dashboard`/`booking` + `tools/mock-*`: propósito en una línea y
    clasificación `reutilizar` / `deshabilitar (historia BASE-001)` / `pendiente Q-012`.
    Las clasificaciones de "reutilizar" se apoyan en la tabla "Qué ya trae y qué aprovecharía"
    de la propuesta (páginas 4–5); todo lo que no aparezca ahí ni en la historia va a
    `pendiente Q-012`, nunca se decide por cuenta propia.
  - Para channel manager, booking engine y agentes de revenue: los datos de la sección 4.4 de este
    plan, re-verificados en código (imports, exports, `@OnEvent`, tablas y defaults, permisos,
    rutas del dashboard, cron, variables de docker-compose).
  - Grafo de dependencias de esos tres módulos (texto o Mermaid), destacando:
    `EmailModule` dentro de `agent/`, `BookingEngineModule` requerido por booking-requests,
    `ConnectModule` requerido por booking engine, listeners de `AriService` y `GuestCommsListener`.
  - Tabla de estrategias A/B/C/D de la sección 4.5 con la recomendación técnica, aclarando que
    la implementación de C (si se decide) es una historia futura que debe crear el orquestador.
  - Definición propuesta de "agentes de revenue" y la referencia explícita a Q-012.
- Criterios de aceptación:
  - Cada afirmación de dependencia cita archivo (y línea si aplica) verificable.
  - El conteo de módulos coincide con `apps/api/src/app.module.ts`.
  - No se propone ni aplica ningún cambio de código; no se decide qué módulos adicionales apagar.
  - Solo cambia `docs/project/02-current-haip-baseline.md`.
- Verificación: revisión cruzada por el `revisor` contra el código; `git status` limpio salvo el doc.

### S4 (condicional) — `feat/BASE-001-fix-<corto>`
- Solo si S1 registra un fallo. Tipo: backend o frontend según el fallo.
- Antes de abrirla: clasificar el fallo.
  - Entorno/documentación (versión de Node, base `haip_test` faltante, variable de entorno,
    Windows): se corrige en el documento, no en código.
  - Fallo reproducible también en Linux/CI sobre `vendor/haip-v3.1.1`: es un defecto de upstream.
    Escalar a Danilo; un parche en el núcleo debe ser mínimo, aislado y anotado para upstream.
  - Fallo introducido por commits de `develop` posteriores a `vendor/haip-v3.1.1`: corregir en
    esta subtarea con la prueba que lo cubre.
- Criterios: el comando que fallaba pasa; `pnpm build`, `pnpm lint`, `pnpm typecheck` y
  `node scripts/sync-test-count.mjs --check` en verde; el documento de S1 se actualiza con el
  resultado. PR < 400 líneas.

## 10. Pruebas exigidas

- Unitarias/integración/E2E nuevas: **ninguna** (no hay código de producto).
- El `tester` reproduce de forma independiente la secuencia de la sección 6 en su entorno y
  confirma que los resultados de S1 coinciden (exit codes y conteo de pruebas).
- El `revisor` contrasta las versiones de S2 con el lockfile y las dependencias de S3 con el código.

## 11. Preguntas abiertas

- **Q-012** (registrada en `docs/project/open-questions.md`): qué módulos de HAIP, además de los
  tres que nombra la historia, se deshabilitan en el MVP; frontera exacta de "agentes de revenue";
  y si channel manager y booking engine se apagan definitivamente o solo durante el MVP.
  **No bloquea BASE-001**: la historia pide documentar los tres módulos ya nombrados y las
  palancas existentes; los candidatos adicionales se listan como "pendiente Q-012". Sí bloqueará
  una eventual historia que implemente la estrategia C.

## 12. Riesgos

- Sin BASE-002, los PRs a `develop` no tienen CI automático: la evidencia depende de la
  ejecución local registrada en S1.
- `minio/minio:latest` e imágenes sin digest afectan la reproducibilidad (documentar, no corregir).
- Diferencias de conteo de pruebas entre Windows y Linux por pruebas condicionadas a servicios o
  plataforma: deben explicarse, no ocultarse.
