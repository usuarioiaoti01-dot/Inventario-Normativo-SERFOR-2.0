// ============================================================
//  Edge Function: admin-usuarios
//  Crea y elimina cuentas de acceso a la aplicación. Solo puede
//  invocarla un usuario cuyo perfil tenga role = 'administrador'.
//  Usa la clave service_role (secreto de la función) porque crear o
//  eliminar usuarios de auth.users requiere permisos que la clave
//  "anon" del navegador no tiene.
//
//  Despliegue (ver LEEME.md):
//    supabase functions deploy admin-usuarios
// ============================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (obj: unknown, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: { ...cors, "content-type": "application/json" } });

const ROLES = ["administrador", "especialista"];

// Clave temporal legible: evita caracteres que se confunden (0/O, 1/l/I)
function generarClaveTemporal(): string {
  const alfabeto = "ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789";
  const bytes = new Uint8Array(12);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, b => alfabeto[b % alfabeto.length]).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
    const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // 1) Verificar que quien llama tiene sesión y es administrador
    const authHeader = req.headers.get("Authorization") ?? "";
    const userClient = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: authHeader } } });
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return json({ error: "No autenticado." }, 401);

    const admin = createClient(SUPABASE_URL, SERVICE_KEY);

    const { data: perfil } = await admin.from("profiles").select("role").eq("id", user.id).single();
    if (!perfil || perfil.role !== "administrador") {
      return json({ error: "Solo un administrador puede gestionar cuentas." }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const { accion } = body;

    if (accion === "crear") {
      const { nombre, correo, rol } = body;
      const email = String(correo || "").trim().toLowerCase();
      if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        return json({ error: "Correo institucional inválido." }, 400);
      }
      if (!ROLES.includes(rol)) return json({ error: "Rol inválido." }, 400);

      const claveTemporal = generarClaveTemporal();
      const { data: nuevo, error: errCrear } = await admin.auth.admin.createUser({
        email,
        password: claveTemporal,
        email_confirm: true,
      });
      if (errCrear || !nuevo?.user) {
        return json({ error: "No se pudo crear el usuario: " + (errCrear?.message ?? "") }, 400);
      }

      // El trigger on_auth_user_created ya insertó una fila básica en profiles.
      const { error: errPerfil } = await admin
        .from("profiles")
        .update({ nombre: nombre || null, role: rol, must_change_password: true })
        .eq("id", nuevo.user.id);
      if (errPerfil) {
        return json({ error: "Usuario creado, pero falló al asignar el perfil: " + errPerfil.message }, 500);
      }

      return json({ ok: true, id: nuevo.user.id, claveTemporal });
    }

    if (accion === "eliminar") {
      const { id } = body;
      if (!id) return json({ error: "Falta el id del usuario." }, 400);
      if (id === user.id) return json({ error: "No puedes eliminar tu propia cuenta." }, 400);

      const { error: errBorrar } = await admin.auth.admin.deleteUser(id);
      if (errBorrar) return json({ error: "No se pudo eliminar: " + errBorrar.message }, 400);

      return json({ ok: true });
    }

    return json({ error: "Acción no reconocida. Use 'crear' o 'eliminar'." }, 400);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
