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
  la herramienta instalada. Queda para revisión en S2 (versiones del lockfile).
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

Pendiente — S2.

## 7. Inventario de módulos y módulos a deshabilitar

Pendiente — S3.
