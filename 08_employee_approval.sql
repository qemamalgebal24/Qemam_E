-- ============================================================================
-- نظام موافقات لإضافة/حذف الموظفين — أي طلب من "محاسب" يحتاج موافقة "المالك"
-- شغّلي هذا الملف بعد كل الملفات السابقة
-- ============================================================================

create table if not exists public.employee_requests (
  id bigint generated always as identity primary key,
  type text not null check (type in ('add','delete')),
  employee_id bigint references public.employees(id) on delete set null,
  payload jsonb not null default '{}',           -- بيانات الموظف المطلوب إضافته (لو type=add)
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  requested_by uuid,
  requested_by_email text,
  reason text default '',
  reviewed_by uuid,
  reviewed_by_email text,
  reviewed_at timestamptz,
  review_note text default '',
  created_at timestamptz not null default now()
);

alter table public.employee_requests enable row level security;

drop policy if exists employee_requests_select on public.employee_requests;
create policy employee_requests_select on public.employee_requests for select using (public.is_member());

-- أي مستخدم له صلاحية تعديل (محاسب/مالك) يقدر يفتح طلب
drop policy if exists employee_requests_insert on public.employee_requests;
create policy employee_requests_insert on public.employee_requests for insert with check (public.can_edit());

-- فقط المالك يقدر يوافق/يرفض (تحديث حالة الطلب)
drop policy if exists employee_requests_update on public.employee_requests;
create policy employee_requests_update on public.employee_requests for update using (public.is_owner()) with check (public.is_owner());

-- تسجيل في سجل التدقيق
drop trigger if exists trg_audit_employee_requests on public.employee_requests;
create trigger trg_audit_employee_requests after insert or update on public.employee_requests
  for each row execute function public.write_audit_log();

do $$
begin
  execute 'alter publication supabase_realtime add table public.employee_requests';
exception when duplicate_object then
  null;
end $$;

-- ============================================================================
-- تم! من دلوقتي: المالك يضيف/يحذف موظف مباشرة زي العادي.
-- المحاسب لما يضيف/يحذف موظف، الطلب هيروح لقائمة "طلبات بانتظار الموافقة"
-- تظهر للمالك في تبويب الموظفين، ويقدر يوافق أو يرفض بضغطة زرار.
-- ============================================================================
