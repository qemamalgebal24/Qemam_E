-- ============================================================================
-- سجلّ النسخ الاحتياطية اليومية — لتتبّع مين أخذ نسخة Excel كاملة وإمتى
-- (يفعّل تبويب "سجلّ النسخ الاحتياطية" في الإعدادات ← النسخ الاحتياطي والتصدير)
-- شغّلي هذا الملف بعد كل الملفات السابقة
-- ============================================================================

create table if not exists public.backup_log (
  id bigint generated always as identity primary key,
  triggered_by text not null default 'manual' check (triggered_by in ('manual','auto')),
  user_email text default '',
  created_at timestamptz not null default now()
);

alter table public.backup_log enable row level security;

-- أي عضو في النظام (مالك/محاسب/مدير) يقدر يشوف سجلّ النسخ
drop policy if exists backup_log_select on public.backup_log;
create policy backup_log_select on public.backup_log for select using (public.is_member());

-- فقط من يملك صلاحية تعديل (مالك/محاسب) يقدر يسجّل نسخة احتياطية جديدة
drop policy if exists backup_log_insert on public.backup_log;
create policy backup_log_insert on public.backup_log for insert with check (public.can_edit());

-- لا يوجد تعديل أو حذف لسجلّ النسخ (سجلّ ثابت لا يُعبث به)

do $$
begin
  execute 'alter publication supabase_realtime add table public.backup_log';
exception when duplicate_object then
  null;
end $$;

-- ============================================================================
-- تم! دلوقتي سجلّ النسخ الاحتياطية في تبويب "الإعدادات ← النسخ الاحتياطي
-- والتصدير" هيشتغل ويعرض تاريخ ووقت كل نسخة (تلقائية أو يدوية) ومين أخذها،
-- بدل رسالة "السجلّ غير متاح" اللي كانت بتظهر قبل كده.
-- ============================================================================
