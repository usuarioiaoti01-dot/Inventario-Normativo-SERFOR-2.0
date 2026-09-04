-- ============================================================
--  Inventario Normativo SERFOR — Módulo de administración de usuarios
--
--  Introduce dos perfiles con nombre definitivo:
--    'administrador' (antes 'admin')   → control total de la aplicación
--    'especialista'  (antes 'lector')  → navega, ve y descarga documentos,
--                                        pero SOLO los de "Normativos OPR"
--
--  Requiere haber ejecutado antes  supabase-setup.sql  y, si aplica,
--  supabase-tabla-opr.sql.
--
--  Ejecutar UNA vez en:  Supabase → SQL Editor → New query → pegar → Run
--  Es idempotente: se puede volver a ejecutar sin efectos secundarios.
-- ============================================================

-- ---------- 1. Migrar los nombres de rol ----------
update public.profiles set role = 'administrador' where role = 'admin';
update public.profiles set role = 'especialista'  where role = 'lector' or role is null;

alter table public.profiles alter column role set default 'especialista';

-- Marca si el usuario debe cambiar su clave la próxima vez que entre.
-- Por defecto queda en false para no afectar a las cuentas ya existentes;
-- el módulo de administración la pone en true al crear una cuenta nueva.
alter table public.profiles add column if not exists must_change_password boolean not null default false;

-- ---------- 2. is_admin() ahora reconoce el rol 'administrador' ----------
create or replace function public.is_admin()
returns boolean language sql security definer stable set search_path = public as $$
  select exists(select 1 from public.profiles where id = auth.uid() and role = 'administrador');
$$;

-- ---------- 3. Un administrador puede ver y editar cualquier perfil ----------
-- (además de la política existente que deja a cada quien ver/editar el suyo)
drop policy if exists "perfil_admin_select_all" on public.profiles;
create policy "perfil_admin_select_all" on public.profiles
  for select to authenticated using (public.is_admin());

drop policy if exists "perfil_admin_update_all" on public.profiles;
create policy "perfil_admin_update_all" on public.profiles
  for update to authenticated using (public.is_admin());

-- ---------- 4. Resguardo de roles ----------
-- Nadie que no sea administrador puede cambiarse (o cambiarle a otro) el rol,
-- y nunca puede quedar la aplicación sin ningún administrador.
create or replace function public.profiles_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if TG_OP = 'UPDATE' then
    if new.role is distinct from old.role then
      if not public.is_admin() then
        raise exception 'Solo un administrador puede cambiar roles.';
      end if;
      if old.role = 'administrador' and new.role <> 'administrador'
         and (select count(*) from public.profiles where role = 'administrador' and id <> old.id) = 0 then
        raise exception 'Debe existir al menos un administrador.';
      end if;
    end if;
    return new;
  end if;
  if TG_OP = 'DELETE' then
    if old.role = 'administrador'
       and (select count(*) from public.profiles where role = 'administrador' and id <> old.id) = 0 then
      raise exception 'Debe existir al menos un administrador.';
    end if;
    return old;
  end if;
  return coalesce(new, old);
end;$$;

drop trigger if exists profiles_guard_trg on public.profiles;
create trigger profiles_guard_trg before update or delete on public.profiles
  for each row execute function public.profiles_guard();

-- ---------- 5. "Normativa base" queda reservada a administradores ----------
-- El especialista solo debe ver "Normativos OPR" (política ya existente
-- "opr_select" en supabase-tabla-opr.sql, sin cambios).
drop policy if exists "doc_select" on public.documentos;
drop policy if exists "doc_select_admin" on public.documentos;
create policy "doc_select_admin" on public.documentos
  for select to authenticated using (public.is_admin());

-- ---------- 6. Storage: el especialista solo baja PDF de Normativos OPR ----------
-- Los archivos del lote OPR se subieron con el prefijo "opr_" dentro del
-- bucket (ver HANDOFF.md), p. ej. "documentos/opr_....pdf".
drop policy if exists "storage_select" on storage.objects;
drop policy if exists "storage_select_admin" on storage.objects;
create policy "storage_select_admin" on storage.objects
  for select to authenticated using (bucket_id = 'documentos' and public.is_admin());

drop policy if exists "storage_select_opr" on storage.objects;
create policy "storage_select_opr" on storage.objects
  for select to authenticated using (bucket_id = 'documentos' and name like 'documentos/opr\_%' escape '\');

-- ============================================================
--  Después de ejecutar este script, la creación y eliminación de
--  cuentas se hace desde la pestaña "Administración" de la aplicación
--  (requiere desplegar la Edge Function admin-usuarios, ver LEEME.md).
-- ============================================================
