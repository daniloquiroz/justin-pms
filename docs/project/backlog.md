# Backlog — Justin/Jurassic PMS

Orden de prioridad según la propuesta: habitación → estancia → consumo → cobro → caja → aseo →
inventario → auditoría. Hardware (cerraduras, cámaras), offline y contabilidad vienen después
del levantamiento técnico.

Estados: PENDIENTE · EN_CURSO · HECHA · BLOQUEADA

## Fase 0 — Fundación (P0-MVP)

| ID | Historia | Depende de | Estado | PRs |
|----|----------|------------|--------|-----|
| BASE-001 | Verificar baseline: build, typecheck y pruebas de HAIP en verde en develop; documentar en `02-current-haip-baseline.md` versiones reales del lockfile y módulos a deshabilitar (channel manager, booking engine, agentes de revenue) | — | PENDIENTE | |
| BASE-002 | Configurar CI propio en GitHub Actions para PRs a develop (build, typecheck, lint, test) reutilizando `.github/workflows` de HAIP | BASE-001 | PENDIENTE | |
| ORG-001 | Modelo de unidades: crear seed con 3 propiedades (Justin Hotel, Justin Motel, Jurassic Hotel) agrupadas por sede física, COP y America/Bogota | BASE-001 | PENDIENTE | |
| RBAC-001 | Roles propios: Propietaria, Admin general, Gerente por sede, Supervisor, Recepcionista, Caja, Housekeeping, Inventario, Contabilidad, Auditor; matriz de permisos | ORG-001 | PENDIENTE | |
| AUD-001 | Bitácora de eventos sensibles no editable por operadores (descuentos, anulaciones, aperturas, diferencias de caja) | RBAC-001 | PENDIENTE | |

## Fase 1 — Operación mínima (P0-MVP)

| ID | Historia | Depende de | Estado | PRs |
|----|----------|------------|--------|-----|
| FD-001 | Room Board: ver todas las habitaciones de la unidad con estado en tiempo real | ORG-001 | PENDIENTE | |
| SS-001 | Motor tarifario de estancias cortas configurable (paquete inicial, bloques adicionales, gracia, redondeo) | ORG-001 | PENDIENTE | |
| SS-002 | Iniciar estancia corta desde una habitación libre (`short_stay_session` + folio) | SS-001, FD-001 | PENDIENTE | |
| SS-003 | Extender estancia corta sin duplicar cargos | SS-002 | PENDIENTE | |
| FD-005 | Cerrar cuenta: no permitir cierre con consumos pendientes | SS-002 | PENDIENTE | |
| MGR-001 | Descuentos por niveles con autorización, motivo y auditoría | SS-002, AUD-001 | PENDIENTE | |
| CASH-001 | Apertura/cierre de turno con arqueo ciego por usuario (sobre cash drawer de HAIP) | RBAC-001 | PENDIENTE | |
| REF-001 | Registro de conductores/referidos y comisión enlazada a la estancia | SS-002 | PENDIENTE | |

## Fase 2 — Aseo e inventario (P0)

| ID | Historia | Depende de | Estado | PRs |
|----|----------|------------|--------|-----|
| HK-001 | Housekeeping ve solo habitaciones asignadas, sin datos financieros | RBAC-001 | PENDIENTE | |
| HK-003 | Marcar habitación limpia y propagar estado en tiempo real | HK-001 | PENDIENTE | |
| INV-001 | Inventario por ubicación (almacén → habitación) con movimientos | ORG-001 | PENDIENTE | |
| HK-002 | Registrar consumo de minibar: stock + folio una sola vez (idempotente) | INV-001, SS-002 | PENDIENTE | |
| PWA-001 | PWA móvil de aseo/minibar (online-first; offline en fase posterior) | HK-002, HK-003 | PENDIENTE | |

## Fase 3 — Recepción táctil y portal (P1)

| ID | Historia | Depende de | Estado | PRs |
|----|----------|------------|--------|-----|
| FD-UX-001 | App `frontdesk-touch` (React) con cambio rápido de usuario por PIN | FD-001, SS-003 | PENDIENTE | |
| OWN-001 | Portal de la propietaria: consolidado de las 3 unidades | CASH-001, SS-003 | PENDIENTE | |

## Fuera del MVP (requieren levantamiento técnico primero)
Cerraduras (FD-004), cámaras (SEC-001), Edge Gateway/offline (OFF-001, OFF-002),
adaptador contable, facturación electrónica, fidelización, migración de datos.
No las tomes hasta que Danilo las mueva a una fase activa.
