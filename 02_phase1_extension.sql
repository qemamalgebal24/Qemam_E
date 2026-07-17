-- ============================================================================
-- المرحلة 1 — الأساس المالي للمشاريع
-- شغّل هذا الملف بعد ملف supabase_schema.sql الأول (آمن، لن يمسح بياناتك الحالية)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) توسعة جدول المشاريع بحقول إدارية ومالية
-- ---------------------------------------------------------------------------
alter table public.projects add column if not exists owner text default '';
alter table public.projects add column if not exists project_type text default '';
alter table public.projects add column if not exists status text default 'جارٍ' check (status in ('جارٍ','منتهٍ','متوقف'));
alter table public.projects add column if not exists start_date date;
alter table public.projects add column if not exists budget_amount numeric default 0;
alter table public.projects add column if not exists notes text default '';
alter table public.projects add column if not exists project_no int;

-- ---------------------------------------------------------------------------
-- 2) عقود العميل (عقد المشروع مع صاحب المبنى — مختلف عن عقود المقاولين
--    من الباطن الموجودة في جدول contracts)
-- ---------------------------------------------------------------------------
create table if not exists public.client_contracts (
  id bigint generated always as identity primary key,
  project_id bigint references public.projects(id) on delete set null,
  contract_no text default '',
  cdate date,
  value numeric not null default 0,
  vat_rate numeric not null default 5,
  payment_terms text default '',
  notes text default '',
  archived boolean not null default false,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 3) الدفعات والمستحقات من العميل
-- ---------------------------------------------------------------------------
create table if not exists public.project_payments (
  id bigint generated always as identity primary key,
  project_id bigint references public.projects(id) on delete set null,
  contract_id bigint references public.client_contracts(id) on delete set null,
  title text default '',
  amount numeric not null default 0,
  due_date date,
  paid_amount numeric not null default 0,
  status text not null default 'مستحق' check (status in ('مستحق','محصل جزئياً','محصل بالكامل')),
  notes text default '',
  sort_order int default 0
);

create table if not exists public.payment_transactions (
  id bigint generated always as identity primary key,
  payment_id bigint not null references public.project_payments(id) on delete cascade,
  amount numeric not null default 0,
  pdate date,
  method text default 'تحويل بنكي',
  ref_no text default '',
  notes text default '',
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 4) الرسوم الحكومية (أمانات تُدفع وتُسترد)
-- ---------------------------------------------------------------------------
create table if not exists public.gov_fees (
  id bigint generated always as identity primary key,
  project_id bigint references public.projects(id) on delete set null,
  description text default '',
  payer_type text default 'الشركة' check (payer_type in ('الشركة','المالك مباشرة')),
  amount numeric not null default 0,
  paid_status text default 'غير مدفوع' check (paid_status in ('مدفوع','غير مدفوع')),
  paid_date date,
  reimburse_status text default 'غير مسترد' check (reimburse_status in ('مسترد','غير مسترد','لا ينطبق')),
  reimburse_date date,
  notes text default '',
  sort_order int default 0
);

-- ---------------------------------------------------------------------------
-- 5) مصروفات المكتب (عامة، أو مرتبطة بمشروع اختياريًا)
-- ---------------------------------------------------------------------------
create table if not exists public.office_expenses (
  id bigint generated always as identity primary key,
  edate date,
  category text default '',
  description text default '',
  amount numeric not null default 0,
  project_id bigint references public.projects(id) on delete set null,
  method text default 'تحويل بنكي',
  notes text default '',
  sort_order int default 0
);

-- ---------------------------------------------------------------------------
-- 6) RLS + السجل + النشر اللحظي لكل الجداول الجديدة
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  for t in select unnest(array[
    'client_contracts','project_payments','payment_transactions','gov_fees','office_expenses'
  ])
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I_select on public.%I', t, t);
    execute format('create policy %I_select on public.%I for select using (public.is_member())', t, t);
    execute format('drop policy if exists %I_write on public.%I', t, t);
    execute format('create policy %I_write on public.%I for all using (public.is_accountant()) with check (public.is_accountant())', t, t);

    execute format('drop trigger if exists trg_audit_%I on public.%I', t, t);
    execute format('create trigger trg_audit_%I after insert or update or delete on public.%I for each row execute function public.write_audit_log()', t, t);

    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then
      null;
    end;
  end loop;
end $$;

-- ============================================================================
-- تم! رجّع لملف "دليل_الإعداد.md" لمعرفة إزاي تشغّل هذا الملف.
-- ============================================================================
