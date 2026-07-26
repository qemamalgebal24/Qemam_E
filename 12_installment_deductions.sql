-- ============================================================================
-- تقسيط السلف والمخالصات: بدل ما ننزل المبلغ كامل مرة واحدة في شهر واحد
-- (وده اللي كان بيخلي الراتب يبقى بالسالب)، دلوقتي كل سلفة/مخالفة بقت
-- "التزام" مستقل ليه: مبلغ إجمالي + قسط شهري + متبقي بيتحدث لوحده كل شهر.
-- شغّلي هذا الملف بعد كل الملفات السابقة
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) جدول الالتزامات: كل صف = سلفة واحدة أو مخالفة واحدة لموظف معيّن
-- ---------------------------------------------------------------------------
create table if not exists public.employee_installments (
  id bigint generated always as identity primary key,
  employee_id bigint not null references public.employees(id) on delete cascade,
  kind text not null default 'سلفة' check (kind in ('سلفة','مخالفة مرورية','أخرى')),
  total_amount numeric not null default 0,        -- إجمالي السلفة أو المخالفة
  monthly_installment numeric not null default 0, -- المبلغ اللي هيتخصم كل شهر بس
  remaining_balance numeric not null default 0,   -- الباقي (بيتحدث تلقائيًا)
  status text not null default 'نشط' check (status in ('نشط','مسدد')),
  notes text default '',                          -- رقم المخالفة / سبب السلفة... إلخ
  created_by uuid,
  created_by_email text,
  created_at timestamptz not null default now()
);

-- عند إنشاء التزام جديد، لو "المتبقي" اتسابت فاضية، يبدأ = الإجمالي
create or replace function public.set_installment_remaining()
returns trigger as $$
begin
  if new.remaining_balance is null or new.remaining_balance = 0 then
    new.remaining_balance := new.total_amount;
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_installment_remaining on public.employee_installments;
create trigger trg_installment_remaining before insert on public.employee_installments
  for each row execute function public.set_installment_remaining();

-- ---------------------------------------------------------------------------
-- 2) عمود في كشف كل شهر يخزّن إجمالي الأقساط اللي اتخصمت فعلاً هذا الشهر
--    (منفصل عن أي خصم أو سلفة يدوية بتضيفيها بنفسك في نفس الشهر)
-- ---------------------------------------------------------------------------
alter table public.payroll_entries
  add column if not exists installment_deduction numeric not null default 0;

-- سجل تفصيلي: كام اتخصم من كل التزام في كل شهر (للمراجعة والتدقيق)
create table if not exists public.installment_deductions (
  id bigint generated always as identity primary key,
  installment_id bigint not null references public.employee_installments(id) on delete cascade,
  payroll_entry_id bigint references public.payroll_entries(id) on delete set null,
  amount numeric not null default 0,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 3) الدالة الأساسية: تطبيق أقساط شهر معيّن على كل الالتزامات النشطة
--    لموظف معيّن، وتحديث المتبقي، وتسجيل تفاصيل الخصم
--    (تُستدعى مرة واحدة لكل موظف عند إنشاء/فتح كشف شهر جديد)
-- ---------------------------------------------------------------------------
create or replace function public.apply_monthly_installments(
  p_employee_id bigint,
  p_payroll_entry_id bigint
)
returns numeric as $$
declare
  r record;
  applied numeric;
  total_applied numeric := 0;
begin
  for r in
    select * from public.employee_installments
    where employee_id = p_employee_id and status = 'نشط' and remaining_balance > 0
    order by created_at
  loop
    applied := least(r.monthly_installment, r.remaining_balance);
    if applied > 0 then
      insert into public.installment_deductions (installment_id, payroll_entry_id, amount)
      values (r.id, p_payroll_entry_id, applied);

      update public.employee_installments
      set remaining_balance = remaining_balance - applied,
          status = case when remaining_balance - applied <= 0 then 'مسدد' else status end
      where id = r.id;

      total_applied := total_applied + applied;
    end if;
  end loop;

  if p_payroll_entry_id is not null then
    update public.payroll_entries
    set installment_deduction = total_applied
    where id = p_payroll_entry_id;
  end if;

  return total_applied;
end;
$$ language plpgsql security definer;

-- ---------------------------------------------------------------------------
-- 4) RLS + سجل التدقيق + النشر اللحظي للجداول الجديدة
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  for t in select unnest(array['employee_installments','installment_deductions'])
  loop
    execute format('alter table public.%I enable row level security', t);

    execute format('drop policy if exists %I_select on public.%I', t, t);
    execute format('create policy %I_select on public.%I for select using (public.is_member())', t, t);

    execute format('drop policy if exists %I_write on public.%I', t, t);
    execute format('create policy %I_write on public.%I for all using (public.can_edit()) with check (public.can_edit())', t, t);

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
-- تم! دلوقتي المنطق بقى:
-- - تضيفي "التزام" جديد لموظف (سلفة أو مخالفة) بمبلغ إجمالي وقسط شهري.
-- - كل شهر، بدل ما تكتبي المبلغ كامل يدوي، النظام (بعد تحديث index.html)
--   هيحسب تلقائيًا أقل قيمة بين "القسط الشهري" و"المتبقي" ويخصمها بس،
--   ويحدّث "المتبقي"، ولما يوصل صفر يتحول الالتزام لـ"مسدد" ويوقف الخصم لوحده.
-- - تقدري أي وقت تشوفي كل الالتزامات (نشطة/مسددة) وتاريخ الخصم بالتفصيل
--   من جدول installment_deductions.
-- - لسه محتاجين تحديث index.html عشان يضيف واجهة "إضافة التزام" ويستدعي
--   الدالة apply_monthly_installments تلقائيًا عند إنشاء شهر جديد.
-- ============================================================================
