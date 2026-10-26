# 02 — Baseline actual de HAIP (Justin/Jurassic PMS)

Documento vivo de la historia BASE-001. Plan: `docs/project/tasks/BASE-001.md`.
Este archivo se completa en tres subtareas: S1 (verificación, esta versión), S2 (versiones del
lockfile) y S3 (inventario de módulos).

## 1. Identidad de la base

| Dato | Valor |
|------|-------|
| `vendor/haip-v3.1.1` (SHA) | `a89f4134e0d47d6e98cea7f728b4d36955606d81` |
| `develop` verificado (SHA) | `7078f7340832f3a7a2f8ffeab836bda3250bbf3b` |
| Árbol verificado | rama `feat/BASE-001-baseline-verify`, creada desde `develop` (mismo SHA `7078f73`) más solo documentos sin commit de `docs/project/` |
| Fecha de la verificación | 2026-10-25 |

Salida de `git log --oneline vendor/haip-v3.1.1..develop`:

```text
7078f73 chore(agentes): configuracion de subagentes, backlog y flujo develop
```

`develop` solo añade un commit propio sobre el upstream congelado (configuración de agentes,
backlog y flujo; sin cambios de código de producto). Por tanto, todo fallo que aparezca abajo
y no dependa de ese commit es comportamiento de `vendor/haip-v3.1.1`.

**Discrepancia de versión.** La propuesta (`docs/project/referencia/propuesta-pms.pdf`) cita la
release v3.0.7 de HAIP; la base realmente congelada en el repositorio es **v3.1.1**
(rama `vendor/haip-v3.1.1`). Manda lo congelado (v3.1.1).

## 2. Toolchain usado

| Herramienta | Versión real |
|-------------|--------------|
| SO | Windows 11 Pro 10.0.26300 (shell: Git Bash/MSYS2 invocando comandos de Windows) |
| Node | v24.16.0 (el proyecto declara `engines.node >=20`; el CI de HAIP usa Node 22) |
| pnpm | 9.15.4 (coincide con `packageManager`) |
| Docker | cliente y servidor 29.5.2; Docker Compose v5.1.4 (Docker Desktop, backend Linux) |
| Fecha | 2026-10-25 |

Observaciones del entorno:

- Cada comando `pnpm` imprime `[WARN] The "pnpm" field in package.json is no longer read by pnpm.
  The following keys were ignored: "pnpm.overrides"`. Es solo una advertencia (los comandos
  terminan en 0), pero indica que el bloque `pnpm.overrides` del `package.json` raíz no lo lee
  la herramienta instalada. Investigado en S2: ver sección 6.6.
- Docker Desktop estaba apagado al inicio; se arrancó para esta verificación. Al arrancar,
  Docker Desktop reinició contenedores de otro proyecto ajeno a este repositorio,
  uno de los cuales ocupa `127.0.0.1:5432`. Ver F3 (sección 3.1) y 5.3.

## 3. Resultados por comando

Todos los comandos se ejecutaron desde la raíz del repositorio (excepto cuando se indica).

| # | Comando | Entorno | Exit code | Duración | Observaciones |
|---|---------|---------|-----------|----------|---------------|
| 1 | `pnpm install --frozen-lockfile` | Windows, sin servicios | 0 | 151 s | Lockfile sin cambios (`git status` limpio). |
| 2 | `pnpm build` | Windows | 0 | 65 s | API: `nest build` con SWC, 800 archivos. |
| 3 | `pnpm lint` | Windows | 0 | 31 s | 0 errores, 3017 advertencias (principalmente `no-explicit-any` y `consistent-type-imports`; ver abajo). |
| 4 | `pnpm typecheck` | Windows | 0 | 33 s | Todos los workspaces. |
| 5 | `pnpm test` sin servicios, sin `DATABASE_URL`/`REDIS_URL` | Windows | **1** | 69 s | Falla `apps/dashboard`: 15 pruebas en 3 archivos (clasificación abajo, F1). `pnpm -r` abortó antes de reportar `apps/api` y `packages/booking-requests`; sus conteos sin servicios se midieron aparte (fila 6). |
| 6 | `vitest run` en `apps/api` y `packages/booking-requests` sin servicios (informativo) | Windows, con los dos ajustes de la sección 5.3 | 0 / 0 | 206 s / 13 s | api: 1961 pasadas, 0 fallidas, 53 omitidas; booking-requests: 250 pasadas, 13 omitidas. |
| 7 | `pnpm db:migrate` con `DATABASE_URL` a `haip_test` | Windows + Postgres 16 en Docker | 0 | 5 s | Migraciones hasta `0030_charges_tax_rate_widen.sql`. |
| 8 | `node scripts/sync-test-count.mjs --check` literal, con Postgres + Redis | Windows | **1** | <1 s | `Could not discover pnpm test workspaces: unknown error` (F2). |
| 9 | Igual con `NODE_OPTIONS=--require winspawn.cjs` solo con ajuste de `spawn` | Windows | **1** | 261 s | `apps/api` pasa (2007 pasadas, 0 fallidas, 7 omitidas); falla `apps/dashboard` (F1). |
| 10 | Igual con ajustes de `spawn` y de locale (sección 5.3) | Windows + Postgres + Redis | **0** | 287 s | `Published test counts OK (2602 tests, 303 files)`. |

El comando 10 usa el script sin modificarlo y sin tocar código del repositorio; solo cambia el
entorno de proceso (ver 5.3). No se corrieron `test:e2e` ni `test:release-smoke` (opcionales).

Advertencias de lint: 3017 avisos, 687 corregibles con `--fix`. No bloquean (`0 errors`) y no
se corrigieron en S1.

### 3.1 Fallos registrados y clasificación propuesta

**F1 — `apps/dashboard`: 15 pruebas fallan según la configuración regional del SO.**

- Comando: `pnpm test` (y `node scripts/sync-test-count.mjs --check`). Exit 1.
- Archivos: `src/pages/BookingRequests.test.tsx`, `src/pages/Channels.test.tsx`,
  `src/components/booking-requests/ModifyStayModal.test.tsx` (15 pruebas; 215 pasan de 230).
- Salida relevante: `Unable to find an element with the text: €640.00` mientras la página
  muestra `EUR 640,00`.
- Causa: `apps/dashboard/src/lib/money.ts` formatea con `Intl.NumberFormat(locale)`, y `locale`
  por defecto es el del entorno. En esta máquina Node resuelve `es-CO`, que produce
  `EUR 640,00`; las pruebas esperan el formato `en-US` (`€640.00`). `LC_ALL`/`LANG` no
  cambian el valor en Windows.
- Evidencia de causa: con un preload que fija `en-US` como locale por defecto
  (`Intl.NumberFormat`, `Intl.DateTimeFormat`, `Number.prototype.toLocaleString`),
  `apps/dashboard` pasa 230/230 (25/25 archivos). No se cambió ningún archivo del repo.
- Clasificación: **entorno, con defecto de portabilidad de upstream**. No lo introdujo
  `develop` (el único commit propio no toca código). Fallaría en cualquier equipo con locale
  `es-*`, que es el caso de producción de este proyecto (COP, `America/Bogota`). Candidato a S4
  (fijar el locale en la configuración de pruebas del dashboard, por ejemplo en el setup de
  Vitest) o a documentarlo como requisito del entorno.

**F2 — `scripts/sync-test-count.mjs` y una prueba de `apps/api` no funcionan en Windows.**

- `scripts/sync-test-count.mjs` llama `spawnSync('pnpm', …)` sin `shell`; en Windows `pnpm`
  es `pnpm.cmd` y falla con ENOENT. El script lo reporta como
  `Could not discover pnpm test workspaces: unknown error`. Exit 1.
- `apps/api/src/modules/booking-request/booking-request-default-flow-regression.spec.ts` en
  la línea 181 llama `execFileBounded('pnpm', [...])`, y ese helper llama `execFileSync` sin `shell`
  en `regression-database-utils.ts:85`. Falla con
  `booking-requests schema installation failed (code ENOENT): spawnSync pnpm ENOENT`. El
  archivo se marca como fallido con 0 aserciones fallidas, lo que deja `apps/api` en exit 1
  (con servicios).
- Clasificación: **bug de portabilidad de upstream**, pero solo en Windows; no ocurre en Linux/CI
  (el CI de HAIP corre en Linux). Reproducible sobre `vendor/haip-v3.1.1` por inspección
  (el código es idéntico). No lo introdujo `develop`. Contorno sin tocar código: sección 5.3.
  Corrección posible (S4 o escalar a Danilo): usar `pnpm.cmd` o `shell: true` en Windows, o
  ejecutar siempre en WSL2/Linux.

**F3 — conflicto de puerto 5432 (solo entorno).** Había otro Postgres de un proyecto distinto
publicado en `127.0.0.1:5432`. El `docker-compose.yml` de HAIP publica `127.0.0.1:5432:5432`
sin variable para cambiarlo. Clasificación: **entorno**. Solución usada sin editar el compose:
un archivo override fuera del repo (sección 5.2).

**F4 — Advertencia `git` por rutas largas.** `git status --ignored` emite
`warning: could not open directory 'node_modules/.pnpm/…': Filename too long` por las rutas
anidadas de `node_modules/.pnpm`. No afectó a install, build ni pruebas. Clasificación:
**entorno** (Windows); la recomendación de `core.longpaths` de la sección 5.4 aplica.

Resumen: sin F1 y F2 los cuatro comandos de calidad y la suite completa terminan en 0. F1 y F2
no cambian el conteo pero hacen fallar el flujo estándar en Windows nativo.

## 4. Conteo de pruebas vs `docs/test-stats.json`

`docs/test-stats.json` publica **2602 pruebas / 303 archivos** (aprobadas; las omitidas no
cuentan; un archivo cuenta si tiene al menos una prueba aprobada).

Resultado de `node scripts/sync-test-count.mjs --check` con Postgres 16 y Redis 7 (comando 10):
**2602 pruebas aprobadas / 303 archivos. Coincide exactamente.** `README.md` y
`docs/test-stats.json` quedaron sin cambios (`--check` no escribe).

| Workspace | Aprobadas | Fallidas | Omitidas | Archivos con al menos una aprobada |
|-----------|-----------|----------|----------|-----------------------------------|
| `apps/api` | 2007 | 0 | 7 | 244 |
| `apps/booking` | 78 | 0 | 0 | 14 |
| `apps/dashboard` | 230 | 0 | 0 | 25 |
| `packages/booking-requests` | 250 | 0 | 13 | 13 |
| `packages/database` | 17 | 0 | 0 | 4 |
| `packages/shared` | 20 | 0 | 0 | 3 |
| **Total** | **2602** | **0** | **20** | **303** |

Pruebas omitidas incluso con servicios (20), todas por interruptores opt-in, no por falta de
servicio:

| Archivo | Omitidas | Variable que las activa |
|---------|----------|-------------------------|
| `apps/api/src/common/database/accepted-pricing-lock.postgres.spec.ts` | 6 | `ACCEPTED_PRICING_LIVE_PG=1` |
| `apps/api/src/release-smoke.integration.spec.ts` | 1 | `RELEASE_SMOKE=1` |
| `packages/booking-requests/src/domain/booking-request-payment.db.spec.ts` | 7 | `PAYMENT_DB_TEST_URL` |
| `packages/booking-requests/src/database/booking-request-remediation.postgres.spec.ts` | 6 | `BOOKING_REQUEST_REMEDIATION_LIVE_PG=1` |

Sin servicios (sin `DATABASE_URL`, mismos ajustes de entorno de 5.3): 20 + 1961 + 78 + 230 +
250 + 12 = **2551 aprobadas** y 71 omitidas (53 en `apps/api`, 13 en booking-requests, 5 en
`packages/database`). La diferencia con 2602 (51 pruebas) son las pruebas de base de datos que
se omiten sin Postgres; por eso `pnpm test` sin servicios puede pasar "en verde" sin cubrirlas y
no es un baseline válido. El baseline válido es el de Postgres + Redis y `--check`.

Sin ajustes de entorno el conteo no se alcanza: F1 deja 15 pruebas fallidas del dashboard y F2
impide ejecutar el comando de conteo.

**Conclusión.** En Linux/CI se espera que el baseline cumpla los criterios sin ajustes (F1 y F2 son específicos
de Windows/locale), pero no se verificó en esta subtarea. En Windows nativo, `develop` pasa build, lint, typecheck y la suite
completa (2602/303, coincide con lo publicado) solo con los dos ajustes de entorno de 5.3.
Verificado sobre `develop` `7078f73` el 2026-10-25. No se ejecutó la suite en Linux real
(WSL2/CI) en esta subtarea.

## 5. Cómo correr el baseline en local

### 5.1 Secuencia de referencia (igual al CI de HAIP)

```text
corepack enable                      # usa pnpm@9.15.4 de packageManager
pnpm install --frozen-lockfile
pnpm build
pnpm lint
pnpm typecheck
docker compose up -d postgres redis  # SOLO estos dos servicios
<crear base haip_test>
DATABASE_URL=postgresql://haip:haip@localhost:5432/haip_test pnpm db:migrate
DATABASE_URL=... REDSYS_TEST_DATABASE_URL=... REDIS_URL=redis://localhost:6379 CI=true FORCE_COLOR=0 \
  node scripts/sync-test-count.mjs --check
```

No usar `docker compose up` sin argumentos: construye la API, corre `init` (migrate + seed demo)
y arranca con `AUTH_ENABLED=false`. Usar siempre `--check`; sin esa bandera el script reescribe
`README.md` y `docs/test-stats.json`.

### 5.2 Linux / WSL2 / CI

```bash
docker compose up -d postgres redis
docker exec haip-postgres createdb -U haip haip_test
export DATABASE_URL=postgresql://haip:haip@localhost:5432/haip_test
export REDSYS_TEST_DATABASE_URL=$DATABASE_URL REDIS_URL=redis://localhost:6379 CI=true FORCE_COLOR=0
pnpm db:migrate && node scripts/sync-test-count.mjs --check
```

Nota: el locale del SO debería ser `en-US` (ver F1); en CI/Linux lo es por defecto.

### 5.3 Windows (PowerShell)

Nota: la verificación de S1 se ejecutó en Git Bash con los equivalentes `export VAR=…`; los
comandos PowerShell de esta sección son su traducción directa.

Requisitos: Docker Desktop (backend Linux/WSL2) en ejecución, Node 22 o superior, pnpm 9.15.4.
`docker version` debe mostrar cliente y servidor; si falla con `dockerDesktopLinuxEngine`,
Docker Desktop no está arrancado.

Si el puerto 5432 está ocupado (F3), no editar `docker-compose.yml`: crear fuera del repo un
archivo `haip-override.yml` que mueva el puerto y pasarlo con `-f` (`!override` requiere Docker Compose 2.24.4 o superior):

```yaml
services:
  postgres:
    ports: !override
      - '127.0.0.1:55432:5432'
```

```powershell
docker compose -f docker-compose.yml -f C:\ruta\fuera\del\repo\haip-override.yml up -d postgres redis
docker exec haip-postgres createdb -U haip haip_test
$env:DATABASE_URL = 'postgresql://haip:haip@localhost:55432/haip_test'   # 5432 si no hay conflicto
$env:REDSYS_TEST_DATABASE_URL = $env:DATABASE_URL
$env:REDIS_URL = 'redis://localhost:6379'
$env:CI = 'true'; $env:FORCE_COLOR = '0'
pnpm db:migrate
```

Para `node scripts/sync-test-count.mjs --check` en Windows nativo hacen falta dos ajustes de
entorno de proceso (no modifican el repo). Se aplican con un archivo preload fuera del repo,
por ejemplo `winspawn.cjs`, cargado con `NODE_OPTIONS`. Con Node 24, `shell: true` con argumentos emite la advertencia
DEP0190; es inofensiva:

```js
// winspawn.cjs (fuera del repositorio)
const cp = require('node:child_process');
// Ajuste 1 (F2): ejecutar `pnpm` como pnpm.cmd en Windows.
for (const fn of ['spawnSync', 'execFileSync']) {
  const orig = cp[fn];
  cp[fn] = function (cmd, args, opt) {
    if (cmd === 'pnpm' && process.platform === 'win32')
      return orig.call(cp, cmd, args, { ...(opt || {}), shell: true });
    return orig.apply(cp, arguments);
  };
}
// Ajuste 2 (F1): locale por defecto en-US para Intl y toLocaleString.
const N = Intl.NumberFormat;
function W(l, o) { return new N(l === undefined ? 'en-US' : l, o); }
W.prototype = N.prototype; W.supportedLocalesOf = N.supportedLocalesOf; Intl.NumberFormat = W;
const D = Intl.DateTimeFormat;
function V(l, o) { return new D(l === undefined ? 'en-US' : l, o); }
V.prototype = D.prototype; V.supportedLocalesOf = D.supportedLocalesOf; Intl.DateTimeFormat = V;
const tl = Number.prototype.toLocaleString;
Number.prototype.toLocaleString = function (l, o) { return tl.call(this, l === undefined ? 'en-US' : l, o); };
```

```powershell
$env:NODE_OPTIONS = '--require C:\ruta\fuera\del\repo\winspawn.cjs'
node scripts/sync-test-count.mjs --check
Remove-Item Env:NODE_OPTIONS
```

La alternativa recomendada, que evita ambos ajustes, es correr todo dentro de WSL2 (Linux).
El preload es un contorno de verificación; la corrección real (S4) sería código o configuración
del repo.

Para limpiar: `docker compose -f docker-compose.yml -f <override> stop postgres redis`
(sin `down -v`; los volúmenes `<proyecto>_postgres-data` y `<proyecto>_redis-data` (el prefijo es el nombre del directorio del clon; aquí `justin-pms`) se conservan).
El script crea el directorio `.vitest-count/`, ignorado por git.

Release-smoke (no ejecutado en S1): el script npm usa sintaxis POSIX y falla en Windows; invocarlo
con `$env:RELEASE_SMOKE='1'; pnpm --filter @telivityhaip/api exec vitest run src/release-smoke.integration.spec.ts`.

### 5.4 Trampas de Windows observadas o conocidas

| Trampa | Observada en S1 |
|--------|-----------------|
| `pnpm` se invoca sin `shell` en `scripts/sync-test-count.mjs` y en una prueba de la API (F2) | Sí |
| Pruebas del dashboard dependen del locale del SO (F1) | Sí |
| Puerto 5432 ocupado por otro Postgres (F3) | Sí |
| Rutas largas en `node_modules/.pnpm` (advertencias de git, F4); `pnpm install` terminó bien | Sí (solo advertencia). Recomendado: `git config core.longpaths true` |
| Scripts `clean` usan `rm -rf` | No se ejecutaron (no hacen falta para el baseline) |
| `test:release-smoke` usa `VAR=valor comando` (POSIX) | No se ejecutó |
| `keycloak/init-keycloak-db.sh` con CRLF rompería el init de Postgres (`.gitattributes` fuerza LF) | No se observó: el contenedor de Postgres arrancó sano |

### 5.5 Decisión sobre S4

La verificación requiere una subtarea S4 si se quiere que el baseline pase **sin** ajustes de
entorno en Windows. Resumen de lo pendiente (la decisión es del orquestador y de Danilo):

| Fallo | Clasificación | Acción propuesta |
|-------|---------------|------------------|
| F1 locale del dashboard | Entorno; defecto de portabilidad de upstream | S4 mínima: fijar locale en la configuración de pruebas del dashboard, o documentar el requisito |
| F2 `pnpm` sin shell en Windows | Bug de portabilidad de upstream (solo Windows) | Escalar a Danilo; o usar WSL2/Linux como entorno oficial; un parche debe ser mínimo y anotado para upstream |
| F3 puerto 5432 | Entorno | Documentado (override fuera del repo) |
| F4 rutas largas | Entorno | Documentado |

## 6. Versiones reales del lockfile

Extraído el 2026-10-25 de `pnpm-lock.yaml` en la rama `feat/BASE-001-lockfile-versions`
(lockfile idéntico al de `develop` `615f858`). Ninguna versión proviene del README.

### 6.1 Identidad del lockfile y toolchain declarado

| Dato | Valor | Fuente |
|------|-------|--------|
| `lockfileVersion` | `'9.0'` | `pnpm-lock.yaml`, primera línea |
| `settings` | `autoInstallPeers: true`, `excludeLinksFromLockfile: false` | `pnpm-lock.yaml`, cabecera |
| `overrides` registrados en el lockfile | `'@types/node': ^22.0.0` | `pnpm-lock.yaml`, cabecera |
| `packageManager` | `pnpm@9.15.4` | `package.json` raíz |
| `engines` | `node >=20.0.0`, `pnpm >=9.0.0` | `package.json` raíz |
| Node en CI | 22 | `.github/workflows/ci.yml` y otros (`node-version: 22`) |
| Node en imágenes Docker | 20 (`node:20-alpine`) | Dockerfiles (ver 6.3) |
| Workspaces | `apps/*`, `packages/*` | `pnpm-workspace.yaml` (solo `packages:`; sin `overrides`) |
| Importers del lockfile | `.`, `apps/api`, `apps/booking`, `apps/dashboard`, `packages/booking-requests`, `packages/database`, `packages/shared` | `pnpm-lock.yaml`, sección `importers` |

Solo `booking-requests`, `database` y `shared` declaran `@types/node` (`^22.0.0`). Ningún
`package.json` de workspace declara `engines`.

### 6.2 Versiones resueltas por workspace

Formato: `rango declarado` → **versión resuelta**. Fuente: sección `importers` de
`pnpm-lock.yaml` (los rangos coinciden con cada `package.json`). `-` = el workspace no declara
la dependencia. Se omiten números de línea porque cambian con cualquier regeneración; el
método de 6.5 permite repetir la extracción.

| Paquete | api | booking-requests | database | shared | dashboard | booking |
|---------|-----|------------------|----------|--------|-----------|---------|
| `typescript` | ^5.7.0 → **5.9.3** | ^5.7.0 → **5.9.3** | ^5.7.0 → **5.9.3** | ^5.7.0 → **5.9.3** | ^5.7.0 → **5.9.3** | ^5.7.0 → **5.9.3** |
| `@nestjs/core` | ^10.4.0 → **10.4.22** | ^10.4.0 → **10.4.22** | - | - | - | - |
| `@nestjs/common` | ^10.4.0 → **10.4.22** | ^10.4.0 → **10.4.22** | - | ^10.4.0 → **10.4.22** | - | - |
| `@nestjs/swagger` | ^7.4.0 → **7.4.2** | ^7.4.0 → **7.4.2** | - | - | - | - |
| `@nestjs/event-emitter` | ^3.0.1 → **3.0.1** | - | - | - | - | - |
| `@nestjs/websockets` | ^10.0.0 → **10.4.22** | - | - | - | - | - |
| `socket.io` | ^4.8.3 → **4.8.3** | - | - | - | - | - |
| `drizzle-orm` | ^0.39.0 → **0.39.3** | ^0.39.0 → **0.39.3** | ^0.39.0 → **0.39.3** | - | - | - |
| `drizzle-kit` | - | - | ^0.30.0 → **0.30.6** | - | - | - |
| `postgres` | ^3.4.5 → **3.4.9** | ^3.4.5 → **3.4.9** | ^3.4.5 → **3.4.9** | - | - | - |
| `bullmq` | ^5.81.1 → **5.81.1** | - | - | - | - | - |
| `class-validator` | ^0.14.1 → **0.14.4** | ^0.14.1 → **0.14.4** | - | ^0.14.1 → **0.14.4** | - | - |
| `class-transformer` | ^0.5.1 → **0.5.1** | ^0.5.1 → **0.5.1** | - | - | - | - |
| `decimal.js` | ^10.4.3 → **10.6.0** | ^10.4.3 → **10.6.0** | - | ^10.4.3 → **10.6.0** | - | - |
| `stripe` | ^22.0.0 → **22.0.0** | ^22.0.0 → **22.0.0** | - | ^22.0.0 → **22.0.0** | - | - |
| `jsonwebtoken` | ^9.0.3 → **9.0.3** | - | - | - | - | - |
| `jwks-rsa` | ^4.0.1 → **4.0.1** | - | - | - | - | - |
| `passport` | ^0.7.0 → **0.7.0** | - | - | - | - | - |
| `vitest` | ^2.1.0 → **2.1.9** | ^2.1.0 → **2.1.9** | ^2.1.0 → **2.1.9** | ^2.1.0 → **2.1.9** | ^2.1.0 → **2.1.9** | ^2.1.0 → **2.1.9** |
| `@swc/core` | ^1.9.0 → **1.15.24** | ^1.9.0 → **1.15.24** | - | - | - | - |
| `tsup` | - | ^8.3.0 → **8.5.1** | ^8.3.0 → **8.5.1** | ^8.3.0 → **8.5.1** | - | - |
| `eslint` | ^9.0.0 → **9.39.4** | ^9.0.0 → **9.39.4** | ^9.0.0 → **9.39.4** | ^9.0.0 → **9.39.4** | - | - |
| `react` | - | - | - | - | ^18.3.1 → **18.3.1** | ^18.3.1 → **18.3.1** |
| `react-dom` | - | - | - | - | ^18.3.1 → **18.3.1** | ^18.3.1 → **18.3.1** |
| `react-router-dom` | - | - | - | - | ^6.28.0 → **6.30.3** | ^6.28.0 → **6.30.3** |
| `@tanstack/react-query` | - | - | - | - | ^5.60.0 → **5.96.2** | ^5.60.0 → **5.96.2** |
| `vite` | - | - | - | - | ^6.0.0 → **6.4.2** | ^6.0.0 → **6.4.2** |
| `tailwindcss` | - | - | - | - | ^3.4.15 → **3.4.19** | ^3.4.15 → **3.4.19** |
| `keycloak-js` | - | - | - | - | ^26.2.3 → **26.2.3** | - |
| `socket.io-client` | - | - | - | - | ^4.8.0 → **4.8.3** | - |
| `i18next` | - | - | - | - | ^23.16.0 → **23.16.8** | - |
| `zod` | - | - | - | - | ^3.23.0 → **3.25.76** | - |

Notas:

- `eslint` ^9.0.0 → **9.39.4** también está en el importer raíz (`.`), junto con `@eslint/js`
  ^10.0.1 y `typescript-eslint` ^8.58.0. `dashboard` y `booking` no declaran `eslint` propio.
- `vitest` es 2.1.9 en todos los workspaces. La API se compila con `@nestjs/cli` y SWC.
- Otras dependencias relevantes (misma fuente):

| Paquete | Workspace | Rango → resuelta |
|---------|-----------|------------------|
| `@nestjs/platform-express` | api (dep) | ^10.4.0 → 10.4.22 |
| `@nestjs/platform-socket.io` | api (dep) | ^10.0.0 → 10.4.22 |
| `@nestjs/config` | api (dep), booking-requests (dev) | ^3.3.0 → 3.3.0 |
| `@nestjs/passport` | api (dep) | ^11.0.5 → 11.0.5 |
| `@nestjs/cli` | api (dev) | ^10.4.0 → 10.4.9 |
| `@swc/cli` | api (dev) | ^0.5.0 → 0.5.2 |
| `fast-xml-parser` | api (dep) | ^5.5.10 → 5.5.10 (el lockfile también contiene 5.7.3, transitivo) |
| `tsx` | database, booking-requests (dev) | ^4.19.0 → 4.21.0 |
| `@vitejs/plugin-react` | dashboard, booking (dev) | ^4.3.0 → 4.7.0 |
| `@types/react`, `@types/react-dom` | dashboard, booking (dev) | ^18.3.12 → 18.3.28; ^18.3.1 → 18.3.7 |
| `jsdom` | dashboard, booking (dev) | ^25.0.0 → 25.0.1 |
| `recharts`, `lucide-react`, `react-i18next` | dashboard | ^2.13.0 → 2.15.4; ^0.460.0 → 0.460.0; ^15.1.0 → 15.7.4 |

- **Cliente de Redis:** ningún workspace declara `ioredis`, `redis` ni `pg`. Redis lo usa
  `bullmq` mediante `ioredis` **transitivo, resuelto a 5.11.1** (paquete `ioredis@5.11.1` en el
  lockfile). El driver de PostgreSQL es `postgres` (postgres.js) 3.4.9, no `pg`.
- **`socket.io` (dos entradas en el lockfile):**
  - `socket.io` ^4.8.3 → 4.8.3 es dependencia directa de `api` (sección `dependencies` del importer).
  - `@nestjs/platform-socket.io@10.4.22` declara su propia dependencia normal `socket.io: 4.8.1`
    (entrada `socket.io@4.8.1`, distinta de `socket.io@4.8.3`); conviven dos versiones.
  - El código de `api` (`apps/api/src/modules/events/events.gateway.ts`, línea 12) importa tipos
    de `socket.io` que resuelven a 4.8.3; el servidor lo instancia el adaptador
    `@nestjs/platform-socket.io`, que resuelve su propia `socket.io@4.8.1`. Qué versión atiende
    las conexiones en ejecución **no se verificó**.
- **Servidores:** las versiones de PostgreSQL y Redis no las fija el lockfile sino las imágenes
  Docker (6.3).

### 6.3 Imágenes Docker

Fuente: `docker-compose.yml`, `docker-compose.prod.yml`, `docker-compose.auth.yml`,
`.github/workflows/ci.yml`, `.github/workflows/release.yml` y los Dockerfiles. Ninguna imagen se fija por digest.

| Imagen | Tag | Dónde se usa | Perfil | Observaciones |
|--------|-----|--------------|--------|---------------|
| `postgres` | `16-alpine` | `docker-compose.yml` (servicio `postgres`); servicios de dos jobs de `ci.yml` y de dos jobs de `release.yml` | por defecto | Tag flotante dentro de 16.x. |
| `redis` | `7-alpine` | `docker-compose.yml` (servicio `redis`); servicios de dos jobs de `ci.yml` y de dos jobs de `release.yml` | por defecto | Tag flotante dentro de 7.x. |
| `quay.io/keycloak/keycloak` | `24.0` | `docker-compose.yml` (servicio `keycloak`) | `auth` | Tag de minor, flotante en parches. |
| `minio/minio` | `latest` | `docker-compose.yml` (servicio `minio`) | `storage` | **Riesgo de reproducibilidad:** `latest` cambia sin aviso y puede traer cambios incompatibles. Solo se levanta con el perfil `storage`. |
| `node` | `20-alpine` | `apps/api/Dockerfile` (etapas `base` y `production`); `tools/haip-connect-gpt/Dockerfile` (`build` y `runtime`); `tools/mock-bookingcom`, `tools/mock-derbysoft`, `tools/mock-siteminder` | - | Node 20 en imágenes, frente a Node 22 en CI y Node 24.16.0 en la verificación local de S1. |
| `haip-api` (construida) | local | `docker-compose.yml` (servicios `init` y `api`); `docker-compose.prod.yml` y `docker-compose.auth.yml` construyen con `apps/api/Dockerfile` | - | En los compose se construye localmente (`image: haip-api` + `build`). El flujo de release del upstream (`.github/workflows/release.yml`, job `publish-image`) además la publica en GHCR con tag de versión y `latest`; ningún compose del repo consume esa imagen publicada. |

Los servicios `mock-bookingcom`, `mock-siteminder` y `mock-derbysoft` (perfil `channels`) se
construyen desde `tools/*/Dockerfile`.

Observaciones de reproducibilidad en Dockerfiles (solo documentadas, no corregidas):

- `apps/api/Dockerfile` activa `pnpm@9.15.4` con `corepack prepare` (coincide con `packageManager`).
- El mismo Dockerfile ejecuta `pnpm install --frozen-lockfile || pnpm install`: si el lockfile
  no coincide, la imagen cae a una instalación sin congelar y las versiones resueltas pueden
  diferir de las de este documento.

### 6.4 Discrepancias README vs manifiestos y lockfile

Fuente del README: tabla de tecnologías de `README.md`. Los valores reales salen de 6.2.

| Tema | README dice | Manifiesto / lockfile dice | Efecto |
|------|-------------|----------------------------|--------|
| React | "React 19 + Vite" | `react` y `react-dom` `^18.3.1` → 18.3.1; `@types/react` 18.3.28 en `dashboard` y `booking` | Es React 18. Ningún workspace usa React 19. |
| Tailwind CSS | "Tailwind CSS 4" | `tailwindcss` `^3.4.15` → 3.4.19, con `postcss`, `autoprefixer` y `tailwind.config.ts` en `dashboard` y `booking` | Es Tailwind 3. La configuración de v4 no aplica. |
| Enrutado del frontend | "TanStack Query + TanStack Router (file-based routing)" | `react-router-dom` `^6.28.0` → 6.30.3; no hay `@tanstack/react-router` en ningún manifiesto ni en el lockfile; `@tanstack/react-query` sí (5.96.2) | El enrutado es React Router 6, no TanStack Router. |
| Node.js | "Node.js ≥ 20" | `engines.node >=20.0.0`; CI en Node 22; imágenes en `node:20-alpine`; S1 verificó con Node 24.16.0 | Coherente con el mínimo, pero hay tres versiones de Node en uso (20 / 22 / 24). |
| Redis | "Redis 7 + BullMQ" | `redis:7-alpine`; `bullmq` 5.81.1; `ioredis` 5.11.1 solo transitivo | Coherente. |
| PostgreSQL | "PostgreSQL 16" | `postgres:16-alpine`; driver `postgres` 3.4.9 | Coherente. |
| NestJS | Sin versión | `@nestjs/core` y `@nestjs/common` 10.4.22; `@nestjs/swagger` 7.4.2 | Versión mayor 10. |
| pnpm | "pnpm ≥ 9" | `packageManager: pnpm@9.15.4`; `engines.pnpm >=9.0.0` | Coherente. Ver 6.6 sobre el pnpm global 11.x observado. |
| Pruebas | "2602 passing tests across 303 files with passing tests" | Verificado en S1: 2602 / 303 con Postgres + Redis | Coincide (sección 4). |
| Build | "tsup (packages) + Vite (dashboard) + nest build (API)" | `tsup` 8.5.1 en `booking-requests`, `database`, `shared`; `vite` 6.4.2 en `dashboard` y `booking`; `@nestjs/cli` 10.4.9 | Coherente; `apps/booking` también usa Vite. |
| Tipos de Node | Sin mención | `@types/node` único en el lockfile: 22.19.17 | Los tipos son de Node 22 aunque el runtime sea 20 (Docker) o 24 (local S1). |

### 6.5 Método de extracción reproducible

Sin regenerar el lockfile y sin ejecutar `pnpm install` sin `--frozen-lockfile`:

1. Lectura directa: la sección `importers:` de `pnpm-lock.yaml` lista, por workspace, cada
   dependencia con `specifier` (rango declarado) y `version` (resuelta; el sufijo entre
   paréntesis son peers y no forma parte de la versión).
2. Comandos de solo lectura desde la raíz:

```bash
pnpm list -r --depth 0 --json            # versiones resueltas por workspace
pnpm why <paquete> -r                    # quién trae el paquete y en qué versión
grep -n "^  '\?<paquete>@" pnpm-lock.yaml   # entradas de un paquete (con o sin scope; los scoped van entre comillas)
```

3. La tabla 6.2 se generó con un script de solo lectura que recorre `importers:` y toma
   `specifier` y `version`; no escribe en el repositorio.
4. Consistencia: `pnpm install --frozen-lockfile` terminó en 0 y dejó el lockfile sin cambios
   (S1, comando 1).

### 6.6 Advertencia `pnpm.overrides` "no longer read by pnpm"

**Observación (S1).** Cada comando `pnpm` ejecutado en el repositorio imprime:

```text
[WARN] The "pnpm" field in package.json is no longer read by pnpm. The following keys were
ignored: "pnpm.overrides". See https://pnpm.io/settings for the new home of each setting.
```

**Causa investigada.**

| Hecho | Evidencia |
|-------|-----------|
| El `package.json` raíz declara `"pnpm": { "overrides": { "@types/node": "^22.0.0" } }` y `packageManager: pnpm@9.15.4`. | `package.json` raíz |
| `pnpm-workspace.yaml` solo contiene `packages:`; no tiene `overrides` ni otra configuración. No existe `.npmrc` en la raíz. | `pnpm-workspace.yaml` |
| Fuera del repositorio, `pnpm --version` imprime **11.5.1** (instalación global de pnpm del usuario). Dentro del repositorio imprime `9.15.4`, precedido de la advertencia. | `pnpm --version` ejecutado en ambos sitios |
| `node_modules/.modules.yaml` registra `packageManager: pnpm@9.15.4`. | `node_modules/.modules.yaml` |

Causa: el pnpm global es 11.x. Al ejecutarse en el repositorio, lee el `package.json`, emite la
advertencia (en pnpm 11 los ajustes del campo `pnpm` pasaron a `pnpm-workspace.yaml`) y delega en
la versión fijada por `packageManager` (9.15.4), que es la que ejecuta el comando. La advertencia
procede del lanzador 11.x, no de pnpm 9.15.4. El mecanismo de delegación se infiere de lo
observado (versión efectiva 9.15.4 y `.modules.yaml`); no se inspeccionó el código del lanzador.

**Efecto real sobre el lockfile actual.** Los overrides **sí se aplican** con el flujo actual:

- El lockfile contiene `overrides: '@types/node': ^22.0.0`; la instalación que lo generó leyó
  el bloque.
- `pnpm install --frozen-lockfile` termina en 0 con este `package.json` (S1, comando 1). Una
  instalación congelada falla si los `overrides` del lockfile no coinciden con la configuración
  leída; no falla.
- El lockfile contiene una única versión de `@types/node`: **22.19.17**.
- El efecto práctico es pequeño hoy: los tres workspaces que declaran `@types/node` ya piden
  `^22.0.0`, por lo que el resultado probablemente sería el mismo sin override. Es una
  inferencia; no se comprobó regenerando un lockfile sin override (prohibido en S2).

**Riesgo residual (no verificado, no corregido).** Si alguien ejecuta pnpm 11.x sin que se
delegue en 9.15.4, el bloque `pnpm.overrides` se ignoraría y no coincidiría con el lockfile.
La corrección posible (mover el override a `pnpm-workspace.yaml`, o exigir pnpm 9.15.4 vía
`corepack`) queda fuera de S2 y es decisión del orquestador o de Danilo. El CI usa
`pnpm/action-setup@v4` y el Dockerfile de la API usa `corepack prepare pnpm@9.15.4`, ambos con la
versión de `packageManager`.

## 7. Inventario de módulos y módulos a deshabilitar

Pendiente — S3.
