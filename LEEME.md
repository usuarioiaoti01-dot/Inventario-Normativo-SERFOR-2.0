# Inventario Normativo — SERFOR

Aplicación web para consultar, buscar, descargar y **ampliar** la normativa
institucional, con **base de datos PostgreSQL (Supabase)**, **acceso por usuario**
y **carga de nuevos documentos**.

## Contenido de esta carpeta

```
inventario-normativo/
├── index.html               ← la aplicación (login, inventario, nuevos registros)
├── config.js                ← tus credenciales de Supabase (URL + clave anon)
├── supabase-setup.sql       ← esquema de base de datos + seguridad (ejecutar 1 vez)
├── supabase-coleccion.sql   ← (opcional) campo 'coleccion' para subdividir una tabla
├── supabase-tabla-opr.sql   ← crea la tabla normativos_opr (modelo para nuevas tablas)
├── migrar-a-supabase.mjs    ← sube los 123 PDF actuales a Supabase (Node 18+)
├── generar-inventario.ps1   ← genera el catalogo (soporta lotes con -Coleccion / -Anexar)
├── inventario.js            ← catálogo local (solo se usa para la migración inicial)
├── documentos/              ← 123 PDF locales (fuente para la migración inicial)
├── supabase/functions/preguntar/index.ts  ← Edge Function del Asistente IA (Claude)
└── LEEME.md                 ← este archivo
```

Cómo funciona una vez conectado:
- Los **datos** de cada documento viven en la tabla `documentos` de Postgres.
- Los **PDF** viven en el *Storage* privado de Supabase (bucket `documentos`).
- La página **lee todo desde Supabase** y genera enlaces temporales firmados
  para ver/descargar cada PDF solo a usuarios con sesión iniciada.

---

## Puesta en marcha (una sola vez)

### Paso 1 — Crear el proyecto Supabase
1. Entra a **https://supabase.com** → *Start your project* (plan gratuito sirve para empezar).
2. Crea un proyecto (elige región cercana, p. ej. *South America (São Paulo)*).
3. Espera a que termine de aprovisionar.

### Paso 2 — Crear la base de datos y la seguridad
1. En el proyecto, ve a **SQL Editor → New query**.
2. Abre `supabase-setup.sql`, copia todo y pégalo. Pulsa **Run**.
   Esto crea las tablas `profiles` y `documentos`, el bucket `documentos`,
   y todas las reglas de acceso (RLS).

### Paso 3 — Conectar la página
1. Ve a **Project Settings → API**.
2. Copia **Project URL** y la clave **anon public**.
3. Pégalas en `config.js`:
   ```js
   const SUPABASE_URL = "https://TU-PROYECTO.supabase.co";
   const SUPABASE_ANON_KEY = "eyJhbGciOi...";  // clave anon (pública)
   ```

### Paso 4 — Crear el primer usuario administrador
1. En Supabase: **Authentication → Users → Add user** (correo + contraseña).
2. En **SQL Editor**, conviértelo en administrador (cambia el correo):
   ```sql
   update public.profiles set role = 'admin'
   where email = 'adm-claude@serfor.gob.pe';
   ```
3. Ahora instala el **módulo de administración de usuarios**: en **SQL Editor**,
   pega `supabase-admin-usuarios.sql` y pulsa **Run** (renombra los roles a
   `administrador`/`especialista` — tu cuenta recién creada queda como
   `administrador` — y activa el resto de reglas descritas en
   [Dar acceso a más usuarios](#dar-acceso-a-más-usuarios--módulo-de-administración)).
   Luego despliega la función `admin-usuarios` (mismo paso que la función
   `preguntar`, ver más abajo):
   ```powershell
   supabase functions deploy admin-usuarios
   ```

### Paso 5 — Subir los 123 documentos actuales
En PowerShell, dentro de esta carpeta (requiere **Node 18+**):
```powershell
$env:SUPABASE_URL="https://TU-PROYECTO.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY="TU_SERVICE_ROLE_KEY"   # Settings → API → service_role (SECRETA)
node migrar-a-supabase.mjs
```
> La **service_role key** es secreta y omnipotente: úsala solo en tu equipo para
> esta migración. No la pongas en `config.js` ni la subas al servidor.

Al terminar, tendrás los 123 PDF y su metadata en Supabase.

---

## Uso diario

- **Ingresar:** cada usuario entra con su correo y contraseña.
- **Consultar:** buscar, filtrar por tipo/entidad/año y ver el PDF incrustado.
- **Nuevos registros** (solo administradores): pestaña para subir un PDF nuevo con
  sus datos; queda guardado en la base y visible para todos al instante.
- **Pestañas por conjunto:** cada tabla de normativa es una pestaña sobre el
  buscador — *Todas | Normativa base | Normativos OPR* — con su conteo. Filtra la
  lista y se combina con el buscador y los filtros de tipo/entidad/año. Si solo
  hay una tabla, la barra no aparece.

---

## Agregar un conjunto nuevo de documentos

Cada **conjunto** de normativa vive en **su propia tabla** de Supabase y aparece
como una **pestaña** del Inventario. Hoy hay dos:

| Pestaña | Tabla | Contenido |
|---|---|---|
| Normativa base | `documentos` | los 122 documentos de la carga inicial |
| Normativos OPR | `normativos_opr` | 116 PDF (70 lineamientos y directivas de OPR) |

Los PDF de **todas** las tablas se guardan en el mismo bucket privado
`documentos`, así que el visor y el asistente IA funcionan igual en cualquier
pestaña, sin cambios.

Dentro de una tabla, el campo opcional **`coleccion`** permite subdividir en
sublotes: si una tabla tiene más de uno, aparece el filtro *Toda colección* en la
barra de herramientas. Para eso sirve `supabase-coleccion.sql` (opcional).

### Crear una tabla nueva (un conjunto aparte)

1. **En Supabase.** Abre **SQL Editor → New query**, copia
   `supabase-tabla-opr.sql` y adapta el nombre de la tabla (usa minúsculas y
   guion bajo: `normativos_opr`, `normativa_2026`…). Pulsa **Run**.
   El script crea la tabla, sus índices y las mismas reglas de seguridad que
   `documentos`: leen todos los autenticados, solo los administradores escriben.

2. **En la app.** Añade una línea al registro `FUENTES`, cerca del inicio del
   `<script>` de `index.html`:

   ```js
   const FUENTES = [
     { tabla:"documentos",     nombre:"Normativa base" },
     { tabla:"normativos_opr", nombre:"Normativos OPR" },
     { tabla:"normativa_2026", nombre:"Normativa 2026" }   // <- la nueva
   ];
   ```

   El rótulo `nombre` es el que se ve en la pestaña. Una tabla que todavía no
   exista simplemente se omite: la app no se rompe.

3. **Carga los documentos** con cualquiera de las dos vías de abajo, indicando la
   tabla destino.

### Vía A — pocos documentos: desde la app

Entra como administrador → pestaña **Nuevos registros**. Si hay más de una tabla,
aparece el selector **Guardar en** para elegir el destino. El campo **Colección**
solo se muestra si esa tabla tiene la columna.

### Vía B — lote masivo: por PowerShell 7 (`pwsh`)

1. Generar el catálogo y copiar los PDF a `documentos/` sin borrar nada:

   ```
   pwsh -c "& ./generar-inventario.ps1 -Origen 'RUTA_DE_LOS_PDF' -Coleccion 'Normativa 2026' -Salida 'inventario-2026.js' -Anexar"
   ```

   `-Anexar` conserva lo que ya está y **omite** los PDF cuyo contenido ya se
   encuentre en `documentos/` (compara por hash), así que se puede repetir sin
   duplicar. Si no hay nada nuevo, no pisa el catálogo anterior.

   > Para el lote OPR el generador es otro: `generar-inventario-opr.ps1`, que toma
   > la metadata del índice oficial en vez de deducirla del nombre del archivo.

2. Subir ese catálogo **a su tabla**:

   ```
   pwsh -ExecutionPolicy Bypass -File .\migrar-a-supabase.ps1 -SupabaseUrl "https://armvuvoluoxspfjpefex.supabase.co" -ServiceKey "<service_role eyJ...>" -Inventario "inventario-2026.js" -Tabla "normativa_2026"
   ```

   ⚠️ **Cuidado con `-Tabla`.** El script **vacía la tabla destino** antes de
   cargar, para dejarla igual al catálogo. Si te equivocas de nombre y apuntas a
   `documentos`, borras los 122 documentos originales. Añade **`-Anexar`** si lo
   que quieres es *sumar* filas a una tabla que ya tiene contenido.

3. Recarga la app: la pestaña aparece sola con su conteo.

> Límite del plan gratuito de Supabase: **50 MB por archivo**. Los PDF que lo
> superen fallan en la subida y quedan listados como `[fallo]` al final del script.

---

### Dar acceso a más usuarios — módulo de Administración

Ya no hace falta entrar a Supabase para crear o quitar cuentas: la pestaña
**Administración** (solo visible para administradores) lo hace desde la app.

1. **Instalar el módulo (una sola vez):**
   - **SQL Editor → New query**, pega `supabase-admin-usuarios.sql` y pulsa **Run**.
     Renombra los roles (`admin`→`administrador`, `lector`→`especialista`), agrega
     el aviso de "cambiar contraseña en el primer acceso" y restringe **Normativa
     base** solo a administradores (el especialista solo ve **Normativos OPR**).
   - Despliega la función que crea/elimina cuentas (necesita la clave secreta
     `service_role`, que nunca debe estar en el navegador):
     ```powershell
     supabase functions deploy admin-usuarios
     ```
     (mismo `supabase login` / `supabase link` que ya usas para la función `preguntar`).

2. **Perfiles disponibles:**
   | Perfil | Puede |
   |---|---|
   | **Administrador** | Todo: agregar/eliminar usuarios, cambiar el perfil de alguien, subir documentos, ver **Normativa base** y **Normativos OPR** |
   | **Especialista** | Navegar, buscar, ver y descargar documentos — solo de **Normativos OPR** |

3. **Crear una cuenta:** pestaña Administración → formulario "Agregar usuario"
   (nombre, correo, perfil). La app genera una contraseña temporal que se
   muestra **una sola vez**: cópiala y entrégasela a la persona por un canal
   seguro (no por correo en texto plano). Al ingresar por primera vez, la
   aplicación le pedirá cambiarla antes de poder usar el resto de la app.

4. **Cambiar de perfil o eliminar:** desde la misma tabla, con el selector de
   perfil o el botón **Eliminar** de cada fila. No puedes cambiar tu propio
   perfil ni eliminar tu propia cuenta desde ahí (evita quedarte fuera por
   accidente), y el sistema no permite quitar al último administrador.

---

## Publicar la página

La app es estática (HTML + JS). Solo necesitas servir `index.html` y `config.js`.
Opciones:
- **Servidor web de SERFOR (IIS/Apache):** copia `index.html` y `config.js`.
  Ya **no** necesitas subir la carpeta `documentos/` al servidor: los PDF se
  sirven desde Supabase. (`documentos/`, `inventario.js`, los `.ps1/.mjs` y
  `supabase-setup.sql` son solo para la instalación/migración.)
- **Supabase Hosting / Vercel / Netlify:** también sirven, subiendo los dos archivos.

> Requiere conexión a internet (la app usa la API de Supabase y carga la
> biblioteca `@supabase/supabase-js` desde un CDN). Si el servidor de SERFOR no
> tiene salida a internet, avísame y adapto la app para alojar esa biblioteca
> localmente.

---

## Configuración aplicada (se puede cambiar)

| Decisión | Valor por defecto | Dónde se cambia |
|---|---|---|
| Registro de usuarios | Controlado por admin | Authentication (Supabase) |
| Quién sube documentos | Solo administradores | políticas RLS en `supabase-setup.sql` |
| Visibilidad de PDF | Privados (enlaces firmados) | bucket `documentos` (privado) |

Si quieres otra combinación (p. ej. auto-registro con dominio @serfor.gob.pe, o
que todos los usuarios puedan subir), dímelo y ajusto el SQL y la app.

---

## Asistente IA (Claude) — botón flotante "Consulta Contenido"

El botón flotante **"Consulta Contenido"** (abajo a la derecha, con la mascota
capibara) abre un chat para preguntarle a Claude sobre el **documento
seleccionado** y obtener respuestas con **cita de páginas**.

> La imagen del botón se lee de `capibara-serfor.png` en la raíz del sitio
> (junto a `index.html`). Si no está, el botón funciona igual pero sin imagen. La clave de Claude
es **secreta**, así que vive en una **Edge Function de Supabase** (`preguntar`),
nunca en el navegador.

```
Página web  →  Edge Function "preguntar" (guarda ANTHROPIC_API_KEY)  →  API de Claude (Haiku 4.5)
```

### Paso A — Crear la clave de Claude
1. Entra a **console.anthropic.com** → botón **"Obtener clave de API"** (Get API Key).
2. Crea una clave; cópiala (empieza con `sk-ant-...`). **Es secreta** — no la pongas en `config.js`.

### Paso B — Guardar la clave como secreto en Supabase
En Supabase: **Project Settings → Edge Functions → Secrets** (o *Manage secrets*),
agrega:
```
ANTHROPIC_API_KEY = sk-ant-...
```
(Las variables `SUPABASE_URL`, `SUPABASE_ANON_KEY` y `SUPABASE_SERVICE_ROLE_KEY`
ya están disponibles automáticamente dentro de las Edge Functions.)

### Paso C — Desplegar la función `preguntar`
**Opción 1 — Panel de Supabase (más simple):**
1. Ve a **Edge Functions → Create a new function**, nómbrala exactamente `preguntar`.
2. Pega el contenido de `supabase/functions/preguntar/index.ts` y pulsa **Deploy**.

**Opción 2 — CLI (si la tienes instalada):**
```bash
supabase login
supabase link --project-ref armvuvoluoxspfjpefex
supabase functions deploy preguntar
```

### Listo
Recarga la página, abre una directiva y usa el botón **Consulta Contenido**. La página
llama sola a la función (la URL se deriva de `SUPABASE_URL` en `config.js`; no hay
nada más que configurar en el frontend).

### Notas
- **Modelo:** Claude **Haiku 4.5** (el más económico). Para cambiarlo, edita
  `model: "claude-haiku-4-5"` en `index.ts` (p. ej. `claude-sonnet-5`).
- **Costo:** cada pregunta cuesta según el tamaño del documento (se envía el PDF
  como contexto). Una directiva de pocas páginas es de centavos; con US$5 alcanzan
  decenas o cientos de preguntas. Documentos muy grandes (>~22 MB o >100 páginas)
  pueden ser rechazados por el límite de Claude — el asistente lo avisa.
- **Seguridad:** la función verifica que quien pregunta tenga sesión iniciada, y
  descarga el PDF del bucket privado del lado del servidor. La clave nunca llega
  al navegador.
- **Alcance actual:** el asistente responde sobre **un documento a la vez**
  (Opción A). El siguiente paso (Opción B) sería preguntar sobre **todo el
  conjunto** a la vez con búsqueda semántica (RAG) — pendiente cuando lo decidas.
