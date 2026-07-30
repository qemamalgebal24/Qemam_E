-- ============================================================================
-- سجل التدقيق (Audit Log): حفظ تفاصيل كل عملية — مش بس "مين عمل إيه وإمتى"،
-- لكن كمان "اتغيّر إيه من كام لكام" عند التعديل، و"كان فيه إيه" عند الحذف.
-- شغّلي هذا الملف بعد كل الملفات السابقة (يحتاج index.html محدّث كمان)
-- ============================================================================

-- 1) أعمدة جديدة في جدول audit_log لحفظ نسخة من الصف قبل وبعد كل عملية
--    (add column if not exists آمن تمامًا ولن يمسح أي بيانات موجودة)
alter table public.audit_log add column if not exists changed_by uuid;
alter table public.audit_log add column if not exists record_id bigint;
alter table public.audit_log add column if not exists old_data jsonb;
alter table public.audit_log add column if not exists new_data jsonb;

-- 2) تحديث الدالة اللي بتسجّل كل عملية (نفس الاسم، فكل التريجرات الموجودة
--    بالفعل على كل الجداول هتستخدم النسخة الجديدة تلقائيًا من غير ما
--    نحتاج نعيد إنشاء أي تريجر)
create or replace function public.write_audit_log()
returns trigger as $$
declare
  v_email text;
begin
  select email into v_email from public.profiles where id = auth.uid();

  insert into public.audit_log (table_name, action, changed_by, changed_by_email, changed_at, record_id, old_data, new_data)
  values (
    tg_table_name,
    lower(tg_op),
    auth.uid(),
    v_email,
    now(),
    case when tg_op = 'DELETE' then old.id else new.id end,
    case when tg_op = 'INSERT' then null else to_jsonb(old) end,
    case when tg_op = 'DELETE' then null else to_jsonb(new) end
  );

  return coalesce(new, old);
end;
$$ language plpgsql security definer;

-- ============================================================================
-- تم! دلوقتي حدّثي index.html للنسخة اللي فيها عرض التفاصيل، وهتلاقي في
-- سجل التدقيق زرار "تفاصيل" جنب كل عملية:
-- - تعديل: كل حقل اتغيّر، من قيمته القديمة لقيمته الجديدة.
-- - إضافة: كل بيانات الصف اللي اتضاف.
-- - حذف: كل بيانات الصف اللي كان موجود قبل الحذف.
-- ملحوظة: العمليات القديمة (قبل تشغيل هذا الملف) مش هيبقى ليها تفاصيل محفوظة
-- (كانت من غير النسخة القديمة/الجديدة أصلاً)، لكن أي عملية جديدة من دلوقتي
-- هتتسجل بالتفصيل الكامل.
-- ============================================================================
