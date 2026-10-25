# Orquestación del desarrollo con agentes — Justin/Jurassic PMS

Este archivo complementa el `CLAUDE.md` de HAIP. Si hay conflicto en convenciones de código,
manda `CLAUDE.md`; en flujo de trabajo y reglas del negocio de Justin/Jurassic, manda este archivo.

## Contexto
- Producto: PMS para dos sedes físicas en Barranquilla (Justin y Jurassic) con tres unidades
  lógicas: Justin Hotel, Justin Motel (estancias por horas) y Jurassic Hotel.
- Base: HAIP (fork privado), congelado en la release indicada en la rama `vendor/haip-*`.
- Propuesta completa de arquitectura: `docs/project/referencia/propuesta-pms.pdf`.
- Moneda COP, zona horaria `America/Bogota`, idioma de interfaz español.

## Ramas
| Rama | Uso | Quién escribe |
|------|-----|---------------|
| `main` | Versión estable para producción | Solo Danilo, por PR manual desde develop |
| `develop` | Integración continua del trabajo de los agentes | `integrador-git` vía PR squash |
| `feat/<ID>-<desc>` | Una subtarea | Desarrolladores y tester |
| `vendor/haip-vX.Y.Z` | Copia intacta del upstream | Nadie (solo lectura) |
| `upstream-sync/vX.Y.Z` | Prueba de actualización de HAIP | Danilo |

## Equipo de agentes
| Agente | Responsabilidad | Escribe código |
|--------|-----------------|----------------|
| Orquestador (sesión principal) | Elige historia, crea ramas, delega, actualiza backlog | No |
| `arquitecto` | Plan y subtareas en `docs/project/tasks/` | Solo docs |
| `desarrollador-backend` | API, Drizzle, migraciones, permisos, auditoría | Sí |
| `desarrollador-frontend` | Recepción táctil, PWA, dashboard | Sí |
| `tester` | Pruebas faltantes y suite completa | Solo pruebas |
| `revisor` | Revisión independiente del diff | No |
| `integrador-git` | Commits, push, PR a develop, CI, merge | No |

Flujo por subtarea: arquitecto → desarrollador → tester → revisor → integrador-git.

## Estados del backlog
`PENDIENTE` → `EN_CURSO` → `HECHA` | `BLOQUEADA` (con motivo y referencia a open-questions).

## Reglas no negociables
1. No inventar reglas de negocio hotelero ni de cumplimiento colombiano (DIAN, MinCIT, Ley 1581).
   Lo no definido va a `docs/project/open-questions.md` y la historia queda BLOQUEADA.
2. Permisos aplicados en backend. Todo dato lleva `property_id`.
3. Dinero, inventario, puertas y cámaras: idempotencia + evento de auditoría.
4. Precios siempre calculados en servidor.
5. Preferir módulos nuevos antes que modificar el núcleo de HAIP.
6. Nunca subir secretos ni `.env`. Nunca desplegar con `AUTH_ENABLED=false` fuera de desarrollo local.
7. Ningún agente toca `main` ni hace force push a ramas compartidas.

## Definition of Done (por subtarea)
- Migración incluida si cambia el esquema.
- Endpoint documentado en OpenAPI.
- Permisos en backend y evento de auditoría definidos.
- Errores y reintentos contemplados.
- Pruebas unitarias e integración; E2E cuando el flujo lo amerite.
- `pnpm build`, `pnpm typecheck`, `pnpm lint` y `pnpm test` en verde.
- PR fusionado a develop con CI en verde.
