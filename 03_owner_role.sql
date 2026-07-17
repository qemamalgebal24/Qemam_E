-- ============================================================================
-- إضافة صلاحية "Owner" (مالك) — شغّل هذا الملف بعد الملفين السابقين
-- ============================================================================

-- 1) السماح بدور "owner" في جدول الملفات الشخصية
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('owner','accountant','manager'));

-- 2) أول حساب يتسجّل في النظام يصبح "owner" تلقائيًا، وأي حساب بعده "accountant"
create or replace function public.handle_new_user()
returns trigger as $$
declare
  cnt int;
begin
  select count(*) into cnt from public.profiles;
  insert into public.profiles (id, email, full_name, role)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'full_name',''), case when cnt = 0 then 'owner' else 'accountant' end);
  return new;
end;
$$ language plpgsql security definer;

-- 3) دوال صلاحيات جديدة
create or replace function public.is_owner()
returns boolean as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'owner');
$$ language sql security definer stable;

create or replace function public.can_edit()
returns boolean as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role in ('owner','accountant'));
$$ language sql security definer stable;

-- 4) تحديث كل سياسات "التعديل" في الجداول لتشمل owner أيضًا (بدل accountant بس)
do $$
declare
  t text;
begin
  for t in select unnest(array[
    'projects','employees','payroll_sheets','payroll_entries','residencies','custody','cars',
    'company_settings','lpos','contracts','counters',
    'client_contracts','project_payments','payment_transactions','gov_fees','office_expenses'
  ])
  loop
    execute format('drop policy if exists %I_write on public.%I', t, t);
    execute format('create policy %I_write on public.%I for all using (public.can_edit()) with check (public.can_edit())', t, t);
  end loop;
end $$;

-- 5) السماح لـ Owner بتعديل أي ملف شخصي (لتغيير أدوار المستخدمين من الواجهة)
drop policy if exists profiles_update_owner on public.profiles;
create policy profiles_update_owner on public.profiles for update using (public.is_owner()) with check (true);

-- ============================================================================
-- ملاحظة مهمة: التريجر الجديد بيأثر على الحسابات الجديدة بس.
-- لو عندك حساب مسجّل بالفعل وعايزة تخليه "owner"، شغّلي السطر ده بعد ما تغيّري
-- الإيميل للإيميل بتاعك:
--
-- update public.profiles set role = 'owner' where email = 'ايميلك@example.com';
-- ============================================================================
