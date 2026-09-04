# Inventario Normativo SERFOR — Versión 2

> Fork de [Inventario-Normativo-SERFOR](https://github.com/usuarioiaoti01-dot/Inventario-Normativo-SERFOR),
> punto de partida para las mejoras de la versión 2.

Aplicación web para consultar, buscar, descargar y ampliar la normativa
institucional del **SERFOR** (Servicio Nacional Forestal y de Fauna Silvestre).

- **Frontend:** HTML + JavaScript (estático, sin framework).
- **Backend:** [Supabase](https://supabase.com) — PostgreSQL, Storage y Auth.
- **Acceso:** por usuario (login). Roles `lector` y `admin`.
- **Funciones:** buscador y filtros (tipo/entidad/año), visor de PDF incrustado,
  y carga de nuevos documentos (solo administradores).

## Estructura

| Archivo / carpeta | Descripción |
|---|---|
| `index.html` | La aplicación completa |
| `config.js` | URL y clave pública (anon) de Supabase |
| `lib/supabase.js` | Librería de Supabase (local, sin depender de CDN) |
| `supabase-setup.sql` | Esquema de base de datos + reglas de seguridad (RLS) |
| `migrar-a-supabase.ps1` | Migración inicial de documentos a Supabase (PowerShell) |
| `migrar-a-supabase.mjs` | Igual, versión Node (alternativa) |
| `generar-inventario.ps1` | Regenera el catálogo local desde la carpeta de PDFs |
| `LEEME.md` | Guía detallada de instalación, uso y publicación |

> Los PDF (`documentos/`) **no** se versionan aquí: viven en Supabase Storage.
> Ver `LEEME.md` para el paso a paso completo.

## Puesta en marcha

Resumen (detalle en [`LEEME.md`](LEEME.md)):

1. Crear proyecto en Supabase y ejecutar `supabase-setup.sql`.
2. Poner la URL y la clave `anon` en `config.js`.
3. Crear el usuario administrador.
4. Migrar los documentos con `migrar-a-supabase.ps1`.
5. Publicar `index.html`, `config.js` y `lib/` en el servidor web.
