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

Verificado el 2026-10-25 sobre la rama `feat/BASE-001-module-inventory` (desde `develop`
`d8b7bd1`; el código de `apps/` y `packages/` es el mismo de `vendor/haip-v3.1.1` más el commit
documental de S1). Solo lectura de código: **no se modificó ni se aplicó nada**. Todas las rutas
son relativas a la raíz del repositorio; las rutas HTTP llevan el prefijo global `api/v1`
(`apps/api/src/main.ts:49`). `archivo:línea` indica dónde se verificó cada afirmación; lo que no
se pudo comprobar está marcado **no verificado**.

Método reproducible: contar los identificadores `*Module` del arreglo `imports` de
`apps/api/src/app.module.ts` (líneas 59-119); listar `find apps/api/src/modules -name "*.module.ts"`;
buscar importadores con `grep -rn "<nombre>.module" apps/api/src`; buscar listeners con
`grep -rn "@OnEvent" apps/api/src`; buscar planificación interna con
`grep -rnE "@Cron|@Interval|setInterval|new Queue|new Worker" apps/api/src`.

### 7.1 Conteo real y composición de `AppModule`

| Concepto | Cantidad | Evidencia |
|----------|----------|-----------|
| Módulos de dominio importados estáticamente | **48** | `apps/api/src/app.module.ts:70-118` (49 líneas; la línea 79 es el spread `...bookingRequestsModules()`, no un módulo) |
| Infraestructura | 3 (`ConfigModule` global, `EventEmitterModule` con `wildcard: true`, `DatabaseModule`) | `app.module.ts:60-69`; `DatabaseModule` es `@Global()` en `apps/api/src/database/database.module.ts:34` |
| Condicional: `BookingRequestModule.forRoot(...)` de `@telivityhaip/booking-requests` | 0 o 1 | solo si `HAIP_BOOKING_REQUESTS === 'true'`: `apps/api/src/booking-requests.bootstrap.ts:100,110`; precarga en `apps/api/src/main.ts:23` |
| Condicional: `ServeStaticModule` del dashboard | 0 o 1 | `NODE_ENV=production` o `SERVE_DASHBOARD=true`: `app.module.ts:124-134` |
| Condicional: `ServeStaticModule` del widget `/booking` | 0 o 1 | `NODE_ENV=production` o `SERVE_BOOKING=true`: `app.module.ts:136-145` |
| Archivos `*.module.ts` bajo `apps/api/src/modules` | 50 | 48 de la raíz + 2 que **no** están en la raíz (7.3) |

El conteo de 48 del plan **coincide** con el código. `apps/api/src/modules/booking-request/` **no
es un módulo Nest**: solo contiene pruebas (`*.spec.ts`, `*.e2e-spec.ts`) y el ayudante
`regression-database-utils.ts`; el módulo real vive en `packages/booking-requests`.

### 7.2 Inventario de los 48 módulos de `AppModule`

Columna `L`: línea en `app.module.ts`. Columna `Clasificación`: `reutilizar (fila: acción)` cuando el módulo
corresponde claramente a una fila de la tabla "Qué ya trae y qué aprovecharía" de la propuesta
(`docs/project/referencia/propuesta-pms.pdf`, página 4); `deshabilitar (BASE-001)` para los tres que nombra la
historia; `pendiente Q-012` para todo lo demás (regla del plan: lo que no está en esa tabla ni en la historia no se
decide aquí). No se adivinaron correspondencias dudosas: p. ej. `AuthModule` (guards) y `WebhookModule` no tienen
fila propia en la tabla y quedan en `pendiente Q-012`; la fila "Auditoría" no se asignó a ningún módulo. Los
candidatos de Q-012 (a) se listan en la propia Q-012. El propósito se toma de los controladores, servicios y
comentarios (entre paréntesis lo inferido del nombre o de la ruta). Resumen: 13 `reutilizar`, 3 `deshabilitar`,
32 `pendiente Q-012` (total 48).

| # | Módulo | Ruta (`apps/api/src/modules/`) | L | Rutas HTTP (controlador) | Propósito | Clasificación |
|---|--------|--------------------------------|---|--------------------------|-----------|-------|
| 1 | `HealthModule` | `health/` | 70 | `health` | Comprobación de salud del servicio | pendiente Q-012 |
| 2 | `PropertyModule` | `property/` | 71 | `properties`, `organizations` | Propiedades y organizaciones (el tenant) | reutilizar (Multi-hotel: Reutilizar) |
| 3 | `RoomModule` | `room/` | 72 | `rooms` | Habitaciones, tipos de habitación, estado y discrepancias | reutilizar (Estados habitaciones: Personalizar UX) |
| 4 | `GuestModule` | `guest/` | 73 | `guests` | Perfiles de huésped | pendiente Q-012 |
| 5 | `MediaModule` | `media/` | 74 | `media` | Imágenes de propiedad, tipo de habitación y habitación; almacenamiento | pendiente Q-012 |
| 6 | `ReservationModule` | `reservation/` | 75 | `reservations` | Reservas, disponibilidad y mensajería de reserva | reutilizar (Reservas por noche y Walk-in/check-in/check-out: Reutilizar) |
| 7 | `FolioModule` | `folio/` | 76 | `folios` | Folios, cargos, ruteo y documentos fiscales | reutilizar (Cargos/folios: Reutilizar) |
| 8 | `RatePlanModule` | `rate-plan/` | 77 | `rate-plans` | Planes de tarifa y restricciones | pendiente Q-012 |
| 9 | `PaymentModule` | `payment/` | 78 | `payments`, `webhooks/stripe`, `webhooks/redsys`, `webhooks/worldline` | Pagos y receptores de webhooks de pasarelas (rutas de los controladores `payment/*-webhook.controller.ts`) | pendiente Q-012 |
| 10 | `HousekeepingModule` | `housekeeping/` | 80 | `housekeeping` | Gobernanza de habitaciones | reutilizar (Housekeeping: Reutilizar/ampliar) |
| 11 | `LostAndFoundModule` | `lost-and-found/` | 81 | `lost-and-found` | Objetos perdidos | pendiente Q-012 |
| 12 | `ServiceRequestsModule` | `service-requests/` | 82 | `service-requests` | Solicitudes de servicio | pendiente Q-012 |
| 13 | `NightAuditModule` | `night-audit/` | 83 | `night-audit` | Auditoría nocturna | pendiente Q-012 |
| 14 | `ReportsModule` | `reports/` | 84 | `reports` | Reportes (ingresos, ocupación, etc.) | pendiente Q-012 |
| 15 | `WebhookModule` | `webhook/` | 85 | (sin controlador) | Emisión y entrega de eventos `entidad.acción`; cola BullMQ de entrega (`webhook-delivery.service.ts:397`) | pendiente Q-012 |
| 16 | `ChannelModule` | `channel/` | 86 | `channels`, `channels/inbound/*` | Channel manager (7.4) | deshabilitar (BASE-001) |
| 17 | `ConnectModule` | `connect/` | 87 | `connect`, `admin/connect/credentials` | API para agentes externos con API key (`connect.controller.ts:25-35`) | pendiente Q-012 |
| 18 | `EventsModule` | `events/` | 88 | (sin controlador) | Gateway websocket y feed de eventos del dashboard | reutilizar (Tiempo real, Socket.IO: Reutilizar) |
| 19 | `TaxModule` | `tax/` | 89 | `tax` | Perfiles y reglas de impuestos | pendiente Q-012 |
| 20 | `AuthModule` | `auth/` | 90 | (sin controlador) | Guards, permisos, API keys; exporta `PermissionsService` (`auth.module.ts:71`) | pendiente Q-012 |
| 21 | `AgentModule` | `agent/` | 91 | `agents` | Agentes de IA (7.6) | deshabilitar (BASE-001): solo los agentes de revenue; la frontera es Q-012 (b) |
| 22 | `AccountingModule` | `accounting/` | 92 | (controlador sin prefijo) | Depósitos, cuentas por cobrar, códigos contables | pendiente Q-012 |
| 23 | `CashierModule` | `cashier/` | 93 | `cash`, `cashier` | Cajones de caja | reutilizar (Caja/cash drawer: Reutilizar) |
| 24 | `HouseAccountModule` | `house-account/` | 94 | (controlador sin prefijo) | Cuentas de la casa y catálogo de productos retail | pendiente Q-012 |
| 25 | `AncillaryModule` | `ancillary/` | 95 | `ancillary` | Servicios vendibles de la estadía | pendiente Q-012 |
| 26 | `PolicyModule` | `policy/` | 96 | `cancellation-policies` | Políticas de cancelación | pendiente Q-012 |
| 27 | `GroupsModule` | `groups/` | 97 | `groups` | Grupos, bloqueos y rooming list | pendiente Q-012 |
| 28 | `AdminModule` | `admin/` | 98 | `admin` | Usuarios, roles y catálogo de permisos | reutilizar (Roles/permisos: Extender granularidad) |
| 29 | `BookingEngineModule` | `booking-engine/` | 99 | `booking-engine`, `admin/booking-engine`, `booking-return` | Reserva directa (7.5) | deshabilitar (BASE-001) |
| 30 | `ImportModule` | `import/` | 100 | `import` | Importación por entidad con `dryRun` | reutilizar (Importación: Extender) |
| 31 | `MigrationModule` | `migration/` | 101 | `migration` | Trabajos de migración asíncronos y reanudables (cola BullMQ, `migration-step-processor.service.ts:326`) | pendiente Q-012 |
| 32 | `AccountingExportModule` | `accounting-export/` | 102 | `accounting-export` | CSV de diario de ingresos y balance de comprobación | reutilizar (Exportación contable: Adaptar Colombia) |
| 33 | `NotificationsModule` | `notifications/` | 103 | `notifications` | Envío de SMS, WhatsApp y Telegram | pendiente Q-012 |
| 34 | `ReviewsModule` | `reviews/` | 104 | `reviews` | Reseñas; `ReviewsIngestService` emite `guest.review.ingested` (`reviews-ingest.service.ts:111-112`) | pendiente Q-012 |
| 35 | `PosModule` | `pos/` | 105 | `pos` | Cargos de puntos de venta al folio | pendiente Q-012 |
| 36 | `FolioInboundModule` | `folio-inbound/` | 106 | `folio-inbound` | Cargos incidentales externos al folio de un huésped alojado | reutilizar (Minibar como cargo: Extender a inventario físico) |
| 37 | `DoorLockModule` | `door-lock/` | 107 | `door-lock` | Credenciales de cerradura por reserva | reutilizar (Cerraduras: Crear proveedor real) |
| 38 | `GuestCheckInModule` | `guest-check-in/` | 108 | `guest-check-in` | Check-in en línea del huésped por enlace | pendiente Q-012 |
| 39 | `LlmModule` | `llm/` | 109 | (sin controlador) | `LlmService`, opt-in por `HAIP_AI_ENABLED` (`llm.service.ts:43`) | pendiente Q-012 |
| 40 | `SearchModule` | `search/` | 110 | `search` | Búsqueda universal | pendiente Q-012 |
| 41 | `StaffNotificationsModule` | `staff-notifications/` | 111 | `staff-notifications` | Notificaciones internas al personal y su listener (`staff-notifications.module.ts:11`) | pendiente Q-012 |
| 42 | `HelpModule` | `help/` | 112 | `help` | Ayuda contextual por ruta del dashboard; explicación con LLM opcional | pendiente Q-012 |
| 43 | `TurnawaysModule` | `turnaways/` | 113 | (controlador sin prefijo) | Códigos de motivo y registro de reservas denegadas | pendiente Q-012 |
| 44 | `WaitlistModule` | `waitlist/` | 114 | `waitlist-entries` | Lista de espera sin descontar inventario | pendiente Q-012 |
| 45 | `LoyaltyModule` | `loyalty/` | 115 | `loyalty` | Programa y cuentas de fidelización por organización | reutilizar (Fidelización: Localizar/reglas propias) |
| 46 | `IntegrationsModule` | `integrations/` | 116 | `integrations/catalog`, `admin/integrations` | Catálogo de integraciones y estado por propiedad | pendiente Q-012 |
| 47 | `IcalModule` | `ical/` | 117 | `ical` | Feeds iCal de importación y exportación; módulo independiente de `ChannelModule` (`ical.module.ts:6-8` no importa ningún módulo) | pendiente Q-012 |
| 48 | `FiscalModule` | `fiscal/` | 118 | `fiscal` | Configuración de proveedor fiscal y de registro de huéspedes por propiedad | pendiente Q-012 |

### 7.3 Piezas fuera del arreglo de `AppModule`

| Pieza | Ruta | Cómo se carga | Propósito |
|-------|------|---------------|-----------|
| `MigrationLegacyIdMapModule` | `apps/api/src/modules/migration/migration-legacy-id-map.module.ts` | Importado por `MigrationModule` (`migration.module.ts:12`) y por `ReservationModule` (`reservation.module.ts:33`) | Mapa de ids heredados |
| `EmailModule` / `EmailService` | `apps/api/src/modules/agent/guest-comms/email.module.ts` | Importado por `AgentModule`, `ReservationModule`, `GuestCheckInModule` y el bootstrap de booking-requests (7.6) | Transporte de correo con proveedores intercambiables (`email.module.ts:11-36`) |
| `BookingRequestModule.forRoot` | `packages/booking-requests` (cableado en `apps/api/src/booking-requests.bootstrap.ts`) | Solo con `HAIP_BOOKING_REQUESTS=true` | Solicitudes de reserva (modo "request") |
| `apps/dashboard` | `apps/dashboard/` | Estático vía `ServeStaticModule` (`app.module.ts:124-134`) | Interfaz de gestión |
| `apps/booking` | `apps/booking/` (`@telivityhaip/booking`) | Estático en `/booking` (`app.module.ts:136-145`) | Widget de reserva directa |
| `tools/mock-bookingcom`, `tools/mock-siteminder`, `tools/mock-derbysoft` | `tools/*/` | Perfil `channels` de docker-compose (`docker-compose.yml:158-200`) | Simuladores de canal para desarrollo |
| `tools/haip-connect-gpt`, `tools/repo-control` | `tools/` | **no verificado** (no se inspeccionaron) | - |

### 7.4 Channel manager

**Archivos y módulos Nest.** `apps/api/src/modules/channel/` (`channel.module.ts`, `channel.controller.ts`,
`channel.service.ts`, `ari.service.ts`, `content-sync.service.ts`, `inbound-reservation.service.ts`,
`rate-parity.service.ts`, `channel-adapter.factory.ts`) y `channel/adapters/<nombre>/`. Adaptadores
registrados como providers (`channel.module.ts:50-70`): `mock`, `booking-com`, `siteminder`, `expedia`,
`derbysoft`, `beds24`, `channex` y los de `wave3-console` (solo rutas de archivo; no se describen
sus productos).

**Dependencias salientes.** `ChannelModule` importa `ReservationModule`, `WebhookModule`, `MediaModule`
y `ReviewsModule` (`channel.module.ts:42`). Exporta `ChannelService`, `AriService` e
`InboundReservationService` (`channel.module.ts:71`).

**Dependencias entrantes.** Verificado con `grep` sobre `apps/api/src`: solo `app.module.ts:24,86`
importa `ChannelModule`. Otros resultados del `grep` fueron falsos positivos o pruebas:
`agent/revenue-manager/revenue-manager.agent.ts` coincide por `ChannelMixAgent` (un agente, no el
módulo; línea 20) y `auth/legacy-role-controllers-migration.spec.ts:13` importa `ChannelController`
en una prueba. Ningún módulo de producción depende del channel manager.

**Controladores montados siempre (sin flag).** `ChannelController` (`channels`, permiso de clase
`channels.manage`, `channel.controller.ts:28-29`) y cuatro receptores entrantes marcados `@Public()` con
autenticación propia por conexión (`channel.module.ts:43-48`):

| Ruta | Archivo | Autenticación |
|------|---------|---------------|
| `channels/inbound/booking-com` | `channel/adapters/booking-com/booking-com-inbound.controller.ts:38-39` | Basic Auth contra `config.inboundAuth` de la conexión (líneas 21-35); se omite con `AUTH_ENABLED=false` |
| `channels/inbound/expedia` | `channel/adapters/expedia/expedia-inbound.controller.ts:26-27` | Firma HMAC por conexión (líneas 18-44) |
| `channels/inbound/derbysoft` | `channel/adapters/derbysoft/derbysoft-inbound.controller.ts:41-42` | **no verificado** el mecanismo |
| `channels/inbound/channex` | `channel/adapters/channex/channex-inbound.controller.ts:29-30` | Secreto compartido por cabecera (líneas 20-25) |

`SiteMinder`, `Beds24` y `wave3-console` son adaptadores sin controlador entrante propio.

**Listeners de eventos (se activan solos).**

| Servicio | Eventos | Archivo:línea |
|----------|---------|---------------|
| `AriService` | `reservation.created`, `reservation.modified`, `reservation.cancelled` | `channel/ari.service.ts:356,372,393` |
| `AriService` | `rate_plan.updated`, `rate_restriction.created`, `rate_restriction.updated`, `rate_restriction.deleted` | `channel/ari.service.ts:412-415` |
| `ContentSyncService` | `property.content_updated`, `roomtype.content_updated` | `channel/content-sync.service.ts:132-133` |

Comportamiento verificado: todos capturan errores y no relanzan (`ari.service.ts:357-368`,
`content-sync.service.ts:134-141`). Sin conexiones activas **no hay llamada externa**:
`pushAvailability`/`pushRates`/`pushContent` toman `ChannelService.getActiveConnections`
(`ari.service.ts:41,129`; `content-sync.service.ts:35-37`), que filtra `status = 'active'` y
`is_active = true` (`channel.service.ts:85-96`), y el bucle por conexión no se ejecuta. Sí hay
lecturas de base de datos por evento (la consulta de conexiones; además `pushContent` lee la propiedad
y sus imágenes antes de iterar, `content-sync.service.ts:39-45`).

**Crons y colas.** Ninguno propio. No hay `@Cron`/`@Interval`/`setInterval` en `apps/api/src`; las únicas
colas BullMQ son entrega de webhooks, pasos de migración y desafíos de la pasarela
(`webhook-delivery.service.ts:397`, `migration-step-processor.service.ts:326`,
`worldline-challenge.queue.ts:107`).

**Flags y variables de entorno.** No existe flag para montar o no el módulo. Variables que usan los
adaptadores, definidas en `docker-compose.yml:126-143` (`BOOKING_COM_*`, `SITEMINDER_*`, `EXPEDIA_*`,
`DERBYSOFT_*`); servicios simuladores bajo el perfil `channels` (`docker-compose.yml:158-200`).
`AUTH_ENABLED=false` relaja la autenticación del receptor Booking.com (arriba).

**Configuración por propiedad.** Tabla `channel_connections` (`packages/database/src/schema/channel.ts:28`):
`status` con default `pending_setup` (línea 36) e `is_active` con default `true` (línea 60). Para
sincronizar se necesitan ambos: `status='active'` e `is_active=true`. **Datos demo:** `seed.ts` crea
tres conexiones: `channelCode` `booking_com` en `active`, `demo_channel` (adaptador `mock`) en `active` y `expedia` en `pending_setup`
(`packages/database/src/seed.ts:728-777`).

**RBAC y dashboard.** Permiso `channels.manage` (`packages/shared/src/permissions-catalog.ts:59`,
navegación `/channels`); lo tienen por defecto `admin` (todos), `general_manager` (todos menos
`admin.*`) y `revenue_manager` (`permissions-catalog.ts:171`). Dashboard: ruta `/channels/*`
(`apps/dashboard/src/App.tsx:21,64`), entrada de menú (`components/layout/Sidebar.tsx:78`), y el
submódulo iCal se monta bajo `/channels/ical` (`pages/Channels.tsx:834`, `pages/IcalCalendars.tsx`).
Los receptores entrantes **no** pasan por RBAC (son `@Public()`). `IcalController` no usa
`channels.manage`: usa `@Roles('admin'|'revenue_manager')` (`ical/ical.controller.ts:48-119`).

### 7.5 Booking engine (reserva directa)

**Archivos y módulos Nest.** `apps/api/src/modules/booking-engine/` (`booking-engine.module.ts`,
`booking-engine.controller.ts`, `booking-engine-admin.controller.ts`, `booking-return.controller.ts`,
`booking-engine.service.ts`, `booking-engine-config.service.ts`, `booking-throttle.guard.ts`) más los
guards `auth/booking-key.guard.ts` y `auth/booking-engine-scope.guard.ts`. Las dos guards son
**providers de `BookingEngineModule`**, no de `AuthModule` (`booking-engine.module.ts:37-43`;
`auth.module.ts:68-71` no los lista). Widget: `apps/booking/`.

**Dependencias salientes.** `BookingEngineModule` importa `ConnectModule`, `ReservationModule`,
`RatePlanModule`, `TaxModule`, `GuestModule`, `FolioModule`, `PaymentModule`, `AccountingModule`,
`AuthModule`, `AncillaryModule`, `PolicyModule` (`booking-engine.module.ts:23-34`).

**Dependencias entrantes.** `app.module.ts:37,99` y, de forma dinámica, el bootstrap de
booking-requests (`booking-requests.bootstrap.ts:17-18,66,81-82,92`), que solo se ejecuta con
`HAIP_BOOKING_REQUESTS=true`. Exporta `BookingEngineService`, `BookingEngineConfigService`,
`BookingKeyGuard`, `BookingEngineScopeGuard`, `BookingThrottleGuard` (`booking-engine.module.ts:44-55`).

**Cadena `ConnectModule`.** `ConnectModule` solo la importan `AppModule` y `BookingEngineModule`
(`connect.module.ts`; `grep` sin otros resultados). Además `PaymentModule` resuelve en tiempo de
ejecución el token `CONNECT_CHECKOUT_STRIPE_HANDLER` que provee `ConnectModule`
(`connect.module.ts:42`) en el webhook `checkout.session.completed`
(`payment/stripe-webhook.controller.ts:147-162`). La resolución usa `moduleRef.get(..., { strict: false })`,
así que mientras `ConnectModule` se cargue (lo arrastra `BookingEngineModule`) el token se resuelve. Si
`ConnectModule` deja de cargarse (requiere quitar también `BookingEngineModule` y no activar
`HAIP_BOOKING_REQUESTS`; el paquete `booking-requests` no importa `ConnectModule`, pero sí
`BookingEngineModule`, que lo arrastra), el `catch` deja el handler en `undefined` y el webhook ignora
`checkout.session.completed` sin error ni log. Alcance del impacto: las sesiones de checkout solo las crea
`ConnectPaymentService` (`connect/connect-payment.service.ts:214,227`), por lo que sin `ConnectModule` no se
crean sesiones nuevas; el efecto se limita a sesiones creadas antes de retirarlo o a otras integraciones que
compartan la cuenta de la pasarela. Este acoplamiento no estaba en el plan.

**Controladores montados siempre.** `BookingEngineController` (`booking-engine`, `@Public()` más
`BookingKeyGuard` y `BookingEngineScopeGuard`, `booking-engine.controller.ts:38-40`),
`BookingEngineAdminController` (`admin/booking-engine`, permiso `bookingengine.manage`,
`booking-engine-admin.controller.ts:37-78`) y `BookingReturnController` (`booking-return`, `@Public()`,
`booking-return.controller.ts:12-13`; no se encontró consulta de `is_enabled` en
`booking-return.service.ts`).

**Listeners, crons y colas.** Ninguno propio (`grep @OnEvent` en `booking-engine/` sin resultados). El
`ConnectModule` sí tiene un listener global `@OnEvent('**')` (`connect/connect-events.service.ts:176`)
que consulta suscripciones a webhooks de agentes por cada evento emitido.

**Flags y variables de entorno.**

| Variable | Efecto verificado | Fuente |
|----------|-------------------|--------|
| `HAIP_BOOKING_REQUESTS` | Carga o no el paquete `booking-requests` (que arrastra `BookingEngineModule`, `EmailModule` y otros) | `booking-requests.bootstrap.ts:100,110`; compose `docker-compose.yml:118` (default `false`) |
| `SERVE_BOOKING` / `NODE_ENV=production` | Sirve el widget en `/booking` | `app.module.ts:136`; **el compose del `api` fija `SERVE_BOOKING: 'true'`** (`docker-compose.yml:105`) |
| `AUTH_ENABLED` | Si es `false`, `BookingKeyGuard` y el guard de ámbito dejan pasar con la propiedad demo | `auth/booking-key.guard.ts:46-47,93`; `auth/booking-engine-scope.guard.ts:38` |
| `VITE_HAIP_BOOKING_REQUESTS` | Muestra en el dashboard `/booking-requests` | `apps/dashboard/src/App.tsx:46`, `components/layout/Sidebar.tsx:99`, `lib/bookingRequestsFeature.ts:2` |

**Configuración por propiedad.** Tabla `booking_engine_config` (en singular; el plan la menciona como
`booking_engine_configs`): `is_enabled` default `false`
(`packages/database/src/schema/booking-engine.ts:90,93`). Con `is_enabled=false` el servicio responde
403 `Direct booking is not enabled for this property` en búsqueda (`booking-engine.service.ts:63-65`),
servicios vendibles (112-114) y reserva (403-405). `getConfig` **crea una fila con defaults en el primer
acceso** (`booking-engine-config.service.ts:143-157`), también desde rutas públicas. **Datos demo:**
`seed.ts` inserta la configuración con `isEnabled: true` (`packages/database/src/seed.ts:1248-1250`).

**RBAC y dashboard.** Permiso `bookingengine.manage` (`permissions-catalog.ts:63`, sin entrada de menú;
solo `admin` y `general_manager` lo tienen por defecto). Dashboard: pestaña Settings → Booking Engine
(`apps/dashboard/src/pages/Settings.tsx:20,62`, `components/admin/BookingEngineSettings.tsx`);
`/booking-requests/*` detrás de `isBookingRequestsUiEnabled()` (`App.tsx:46-47`; `Sidebar.tsx:53,99`).
Las rutas públicas del motor y el retorno de pago **no** pasan por RBAC.

### 7.6 Agentes de revenue (`AgentModule`)

**Archivos y módulos Nest.** `apps/api/src/modules/agent/` (`agent.module.ts`, `agent.controller.ts`,
`agent.service.ts`, `agent-autopilot-tiers.ts`, `agent-graph.ts`, una carpeta por agente). Registro:
cada agente se auto-registra en el constructor con `agentService.registerAgent(this)`
(`agent.service.ts:96-97`).

**Agentes implementados (12 clases, `agent.module.ts:25-41`).** `demand_forecast`, `pricing`,
`channel_mix`, `overbooking`, `night_audit`, `housekeeping`, `cancellation`, `guest_comms`,
`review_response`, `ar_collections`, `group_pickup`, `revenue_manager`. El enum `agent_type` tiene 13
valores (`packages/database/src/schema/agent.ts:4-18`); **`deposit_risk` no tiene clase**: pedirlo
devuelve `Agent 'deposit_risk' is not implemented yet` (`agent.service.ts:694-701`).

**Clasificación por riesgo que ya define HAIP** (`agent-autopilot-tiers.ts:7-17`): `money` =
`pricing`, `overbooking`, `channel_mix`, `revenue_manager`, `group_pickup`; `guest` = `guest_comms`,
`review_response`; todo lo demás es `ops`. Es un dato del código, **no** una decisión sobre cuáles son
"de revenue" (ver 7.9). Observación: `execute()` de `pricing` y de `channel_mix` no escribe tarifas ni
llama al channel manager en esta versión (`pricing/pricing.agent.ts:187-204`, comentario "log the
intended changes"; `channel-mix/channel-mix.agent.ts:173-179`).

**Dependencias salientes.** `AgentModule` importa `WebhookModule`, `LlmModule`, `EmailModule`
(`agent.module.ts:23`). Exporta `AgentService` y `DemandForecastAgent` (línea 42).

**Dependencias entrantes.** Verificado con `grep`: solo `app.module.ts:29,91` importa `AgentModule`;
ningún otro módulo usa `AgentService` ni los agentes. Fuera de `agent/` solo se importan archivos de
`agent/guest-comms/email.*` (siguiente tabla).

**Listeners de eventos.**

| Listener | Módulo que lo registra | Eventos | Archivo:línea |
|----------|------------------------|---------|---------------|
| `GuestCommsListener` | `AgentModule` (`agent.module.ts:14,35`) | `reservation.created`, `reservation.checked_in`, `reservation.checked_out` -> `runAgent(..., 'guest_comms')` | `agent/guest-comms/guest-comms.listener.ts:22,27,32,40` |
| `ReviewIngestListener` | `AgentModule` (`agent.module.ts:16,37`) | `guest.review.ingested` -> `runAgent(..., 'review_response')` | `agent/review-response/review-ingest.listener.ts:17-23` |
| `StaffNotificationListener` | **`StaffNotificationsModule`, no `AgentModule`** (`staff-notifications.module.ts:11`) | `agent.decision_created`, además `WEBHOOK_DELIVERY_FAILED` y `audit.completed` | `staff-notifications/staff-notification.listener.ts:19,52,79` |

Correspondencia importante: ambos listeners del `AgentModule` pasan por `AgentService.runAgent`, que
devuelve `{ skipped: true }` si `agent_configs.is_enabled` es falso (`agent.service.ts:104-110`).
Antes de esa comprobación, `getOrCreateConfig` **inserta una fila deshabilitada** (default
`isEnabled: false`, `mode: 'suggest'`) si no existe (`agent.service.ts:329-355`); la inserción ocurre una sola
vez por pareja propiedad-agente y solo para los agentes que disparan los listeners (la fila de `guest_comms`
la crea el primer evento de reserva y la de `review_response` la primera reseña ingerida); después queda
una lectura por evento.

**Crons y colas.** Ninguno interno: "HAIP does not run in-process agent cron"
(`docs/operations/cron.md:36`). Planificación externa: `scripts/cron/agent-runs.sh <agentType>` hace
`POST agents/<propertyId>/<agentType>/run?triggeredBy=schedule` (`scripts/cron/agent-runs.sh:9-23`;
ejemplos activos en `scripts/cron/crontab.example:26-27`). La matriz por defecto es
`revenue_manager`, `ar_collections`, `housekeeping`, `cancellation`, `night_audit`, `guest_comms`, más
ingesta horaria de reseñas (`docs/operations/cron.md:49-55`); `demand_forecast`, `pricing`,
`overbooking`, `channel_mix` y `group_pickup` se ejecutan solo a través de `revenue_manager`
(`docs/operations/cron.md:59`; `agent/revenue-manager/revenue-manager.agent.ts:51,65`). El
entrenamiento nocturno `POST agents/:propertyId/train-all` solo toca agentes con `is_enabled=true`
(`agent.service.ts:512-516`). Nota de deriva documental: `cron.md` dice "Role: admin" para ejecutar
agentes, pero el controlador exige `revenue.manage` (`agent.controller.ts:27`).

**Flags y variables de entorno.** `HAIP_AI_ENABLED` se lee solo en `LlmService` (`llm/llm.service.ts:43`),
que usan `AgentService` (`agent.service.ts:6,32`) y `HelpService` (`help/help.service.ts:2,8`).
**No apaga los agentes**: los agentes heurísticos corren igual; solo se desactiva la explicación con
modelo de lenguaje. `AUTH_ENABLED=false` concede todos los permisos (`auth/permissions.guard.ts:33-35`).

**Configuración por propiedad.** `agent_configs` (`packages/database/src/schema/agent.ts:38`):
`is_enabled` default `false` (línea 44), `mode` default `suggest` (línea 45; valores `manual`,
`suggest`, `autopilot`, líneas 20-24). **Datos demo:** `seed.ts` habilita 12 agentes en modo `suggest`
para la propiedad demo (`packages/database/src/seed.ts:1022-1040`).

**RBAC y dashboard.** `AgentController` tiene permiso de clase `revenue.manage`
(`agent.controller.ts:27`); sus rutas de reseñas (`POST|GET|PATCH :propertyId/reviews`) usan
`reviews.manage` a nivel de método (`agent.controller.ts:172-174,213-217,234-236`). Como el guard usa
`getAllAndOverride([handler, class])` (`permissions.guard.ts:37-40`), el permiso del método reemplaza
al de la clase (inferido del código; no ejecutado). Dashboard: `/revenue/*` (`App.tsx:18,61`,
`Sidebar.tsx:75`), `/communications` y `/reviews` (`App.tsx:66-67`, `Sidebar.tsx:80-81`).
`revenue.manage` está en `permissions-catalog.ts:56` y lo tienen `admin`, `general_manager` y
`revenue_manager` (línea 170).

### 7.7 Acoplamientos detectados por el arquitecto, verificados en código

| # | Afirmación del plan (4.4) | Veredicto | Evidencia |
|---|---------------------------|-----------|-----------|
| 1 | `EmailModule`/`EmailService` viven en `agent/guest-comms/` y los importan `ReservationModule`, `GuestCheckInModule` y el bootstrap de booking-requests | **Correcto**, e incompleto: también `AgentModule` | `reservation.module.ts:9,32`; `guest-check-in.module.ts:7,21`; `booking-requests.bootstrap.ts:23-24,47-48,67,83`; `agent.module.ts:20,23`. Además dos servicios importan el archivo por ruta: `reservation/reservation-messaging.service.ts:12`, `guest-check-in/guest-check-in.service.ts:25` |
| 2 | "Quitar `AgentModule` de `AppModule` es posible; borrar la carpeta `agent/` rompe reservas y check-in" | **Correcto**, con matiz: quitar `AgentModule` no afecta a `EmailModule` porque `ReservationModule` y `GuestCheckInModule` lo importan por su cuenta | mismos archivos del punto 1; ningún otro importador de `AgentModule` |
| 3 | `GuestCommsListener` dentro de `AgentModule` | **Correcto** | `agent.module.ts:14,35`; `guest-comms.listener.ts:22,27,32` |
| 4 | `ReviewIngestListener` (`guest.review.ingested`) del `AgentModule` | **Correcto** | `agent.module.ts:16,37`; `review-ingest.listener.ts:17` |
| 5 | `StaffNotificationListener` es un listener "del `AgentModule`" | **Incorrecto**: lo registra `StaffNotificationsModule`. Escucha `agent.decision_created`, pero también `WEBHOOK_DELIVERY_FAILED` y `audit.completed` | `staff-notifications.module.ts:11`; `staff-notification.listener.ts:19,52,79` |
| 6 | `AriService` escucha eventos de reserva y tarifa | **Correcto** (eventos exactos en 7.4) | `channel/ari.service.ts:356,372,393,412-415` |
| 7 | `ContentSyncService` escucha `property.content_updated` y `roomtype.content_updated` | **Correcto** | `channel/content-sync.service.ts:132-133` |
| 8 | Ningún otro módulo importa `ChannelModule` | **Correcto** | `grep` sobre `apps/api/src`: solo `app.module.ts:24,86`; el resto son pruebas o falsos positivos (7.4) |
| 9 | Cron externo `scripts/cron/agent-runs.sh` | **Correcto**; no hay planificación interna | `scripts/cron/agent-runs.sh:9-23`; `docs/operations/cron.md:36` |
| 10 | `HAIP_AI_ENABLED` (LLM, opt-in) | **Correcto**, pero **no es una palanca para apagar agentes** | `llm/llm.service.ts:43`; los agentes corren sin él |
| 11 | `booking_engine_configs.is_enabled` default `false`; 403 si apagado | **Correcto**; el nombre real es `booking_engine_config` (singular) | `schema/booking-engine.ts:90,93`; `booking-engine.service.ts:63-65,112-114,403-405` |
| 12 | "`SERVE_BOOKING` sin definir" apaga el widget (estrategia A) | **Insuficiente**: con `NODE_ENV=production` se sirve siempre, y el compose lo fija en `true` | `app.module.ts:136`; `docker-compose.yml:105` |
| 13 | "Defaults apagados" como base de la estrategia A | **Condicionado**: `seed.ts` deja encendidos conexiones de canal activas, 12 agentes y el motor de reservas para la propiedad demo; el servicio `init` del compose ejecuta el seed | `seed.ts:728-777,1022-1040,1248-1250`; `docker-compose.yml:82` |
| 14 | `ConnectModule` requerido por el booking engine | **Correcto**; además `PaymentModule` lo usa de forma opcional y silenciosa | `booking-engine.module.ts:24`; `payment/stripe-webhook.controller.ts:147-162` |
| 15 | 48 módulos en `AppModule` | **Correcto** | 7.1 |

### 7.8 Grafo de dependencias (solo los tres bloques y sus vecinos)

```mermaid
graph LR
  App[AppModule] --> Channel[ChannelModule]
  App --> BE[BookingEngineModule]
  App --> Connect[ConnectModule]
  App --> Agent[AgentModule]
  App --> Res[ReservationModule]
  App --> CheckIn[GuestCheckInModule]
  App --> Staff[StaffNotificationsModule]
  App -. "HAIP_BOOKING_REQUESTS=true" .-> BR[BookingRequestModule]

  Channel --> Res
  Channel --> Media[MediaModule]
  Channel --> Reviews[ReviewsModule]
  Channel --> WH[WebhookModule]

  BE --> Connect
  BE --> Res
  BE --> Pay[PaymentModule]
  BE --> Folio[FolioModule]
  BE --> Rate[RatePlanModule]
  BR --> BE
  BR --> Email
  Pay -. "token CONNECT_CHECKOUT_STRIPE_HANDLER, opcional" .-> Connect

  Agent --> LLM[LlmModule]
  Agent --> WH
  Agent --> Email["EmailModule (agent/guest-comms)"]
  Res --> Email
  CheckIn --> Email

  Ari["AriService en Channel"] -. "escucha reservation.*, rate_plan.*, rate_restriction.*" .-> Res
  GCL["GuestCommsListener en Agent"] -. "escucha reservation.created/checked_in/checked_out" .-> Res
  RIL["ReviewIngestListener en Agent"] -. "escucha guest.review.ingested" .-> Reviews
  Staff -. "escucha agent.decision_created" .-> Agent
```

Las líneas punteadas son acoplamiento por eventos o resolución opcional, no por `imports`. Los nodos
omitidos (`TaxModule`, `GuestModule`, `AccountingModule`, `AncillaryModule`, `PolicyModule`, `AuthModule`)
están en las listas de 7.5.

### 7.9 Estrategias para deshabilitar (documentadas, **no aplicadas**)

Niveles de la sección 4.5 del plan. Ninguna está aplicada en este repositorio.

| Estrategia | Channel manager | Booking engine | Agentes de revenue | Impacto | Riesgo y verificaciones | Toca núcleo | Reversible |
|------------|-----------------|----------------|--------------------|---------|-------------------------|-------------|------------|
| **A. Configuración por propiedad / entorno** | No crear `channel_connections` o dejarlas distintas de `status='active'` con `is_active=true`; no levantar perfil `channels` | `booking_engine_config.is_enabled=false` (default); no definir `SERVE_BOOKING`; `HAIP_BOOKING_REQUESTS` sin definir | `agent_configs.is_enabled=false` (default); no programar `agent-runs.sh`; no llamar `train-all` | Las rutas y listeners siguen cargados pero no actúan: el motor responde 403, los agentes devuelven `skipped`, los listeners de canal no hacen llamadas externas | (1) El seed deja todo encendido para la propiedad demo (7.7 #13): no ejecutar el seed ni apagar a mano. (2) `NODE_ENV=production` sirve el widget aunque no se defina `SERVE_BOOKING`. (3) `HAIP_AI_ENABLED` no apaga agentes. (4) Los receptores entrantes de canal siguen públicos. (5) Quedan lecturas residuales por evento (consulta de conexiones, de `agent_configs` y de suscripciones de `connect`) y una única inserción por pareja propiedad-agente en `agent_configs` para `guest_comms` y `review_response`. (6) Con `AUTH_ENABLED=false` A y B quedan anuladas (ver recomendación) | No | Sí, inmediata |
| **B. RBAC** | No otorgar `channels.manage` | No otorgar `bookingengine.manage` | No otorgar `revenue.manage` (y `reviews.manage` para las rutas de reseñas del agente) | Oculta menús y bloquea endpoints autenticados de gestión | (1) Los roles de sistema son de solo lectura (`admin/roles.service.ts:19,62`) y traen estos permisos: `admin: ALL_PERMISSIONS` (`permissions-catalog.ts:84`), `general_manager` casi todos, `revenue_manager` incluye `revenue.manage` y `channels.manage` (`permissions-catalog.ts:158-171`); hay que asignar solo roles propios (RBAC-001). (2) `AUTH_ENABLED=false` concede todo (`permissions.guard.ts:33-35`). (3) No cubre rutas `@Public()` (receptores entrantes, motor de reservas, retorno de pago), ni `connect` (API key), ni los listeners, ni el cron externo. (4) `IcalController` usa `@Roles`, no permisos. (5) El permiso de método reemplaza al de clase en `AgentController` | No (usa el catálogo existente) | Sí |
| **C. Sacar de `AppModule`** | Quitar `ChannelModule` (`app.module.ts:24,86`): nadie más lo importa | Quitar `BookingEngineModule` (y `ConnectModule` si no se quiere): exige `HAIP_BOOKING_REQUESTS` apagado; el paquete lo importa | Quitar `AgentModule` (`app.module.ts:29,91`): `EmailModule` ya lo importan `ReservationModule` y `GuestCheckInModule` | Desaparecen controladores, listeners y rutas; el dashboard seguiría mostrando las pantallas (comportamiento sin API no verificado) | (1) Si `ConnectModule` deja de cargarse (requiere quitar también `BookingEngineModule` y no activar `HAIP_BOOKING_REQUESTS`), el webhook de Stripe ignora `checkout.session.completed` sin error ni log (7.5). (2) Quitar `AgentModule` elimina también `AgentController` y con él las rutas `agents/:propertyId/reviews` (uso por el dashboard **no verificado**), las notificaciones al personal por `agent.decision_created` y `GuestCommsListener`, que no es de revenue (depende de Q-012). (3) Borrar la carpeta `agent/` rompería reservas y check-in (7.7 #1). (4) Requiere un patrón de importación condicional como `bookingRequestsModules()` (`app.module.ts:79`); **no existe hoy** | Sí (conflicto con upstream) | Sí |
| **D. Eliminación de código** | Borrar `channel/` | Borrar `booking-engine/` | Borrar `agent/` | Descartada en el plan | Rompe merges con upstream y dependencias (7.7 #1, #14) | Sí | No |

**Recomendación técnica del plan (registrada, no decidida aquí).** A + B para el MVP; C solo con
decisión explícita y como historia futura que debe crear el orquestador. Con las verificaciones de
esta sección, A + B es viable sin tocar código **a condición de**: (a) no ejecutar el seed de demostración
en entornos reales (o apagar sus filas), (b) usar solo roles propios sin `channels.manage`,
`revenue.manage` ni `bookingengine.manage`, (c) no programar `agent-runs.sh` ni `train-all`, (d) tener
en cuenta que siguen montados los receptores inbound de canal (`@Public()`), las rutas públicas del motor,
`connect` (API con API key, siempre montada) y `booking-return` (`@Public()`, no comprueba `is_enabled`), y
(e) `AUTH_ENABLED=true` (regla 6 de `docs/project/ORQUESTACION.md`).

Con `AUTH_ENABLED=false`, A y B quedan anuladas: el guard de permisos concede todo
(`auth/permissions.guard.ts:33-35`), `BookingKeyGuard` (`auth/booking-key.guard.ts:93`) y el guard de ámbito
(`auth/booking-engine-scope.guard.ts:38`) dejan pasar, y el receptor inbound de Booking.com omite el Basic
Auth (`booking-com-inbound.controller.ts:59`). El servicio `api` de `docker-compose.yml` fija
`AUTH_ENABLED: 'false'` y `NODE_ENV: development` (`docker-compose.yml:101,112`); no debe usarse como base de
un entorno real.

### 7.10 Qué depende de Q-012 y qué no se verificó

- **Q-012 (abierta, no bloquea BASE-001):** (a) qué otros módulos se deshabilitan (candidatos listados en la propia Q-012, `docs/project/open-questions.md`);
  (b) qué agentes son "de revenue"; (c) si el apagado de channel manager y booking engine es temporal (MVP) o definitivo.
  Este documento **no decide** ninguno. Dato de apoyo para (b): la clasificación `money` del código
  (`agent-autopilot-tiers.ts:7-13`) y la regla de que las palancas corren vía `revenue_manager`
  (`docs/operations/cron.md:59`); la frontera final (incluir `demand_forecast` y `cancellation`) es de
  Danilo. Para (c): A, B y C son reversibles; C toca el núcleo y solo procede si Q-012 lo pide.
- **No verificado:** mecanismo
  de autenticación del receptor DerbySoft; uso real de las rutas `agents/:propertyId/reviews` por el dashboard;
  `agent-graph.ts` y las dependencias entre agentes más allá de `revenue_manager`; comportamiento en tiempo de
  ejecución de los listeners (no se arrancó la API ni se emitieron eventos); permiso con que se muestra la
  pestaña Settings -> Booking Engine; propósito de `tools/haip-connect-gpt` y `tools/repo-control`.
