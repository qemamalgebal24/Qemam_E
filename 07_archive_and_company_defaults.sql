-- ============================================================================
-- 1) إضافة تاريخ الأرشفة (لازم لتفعيل قفل الحذف بعد 24 ساعة)
-- 2) تعبئة بيانات التواصل الحقيقية للشركة كقيم افتراضية (كانت فاضية فبالتالي
--    ما كانتش بتظهر في فوتر المستندات المطبوعة)
-- ============================================================================

alter table public.lpos add column if not exists archived_at timestamptz;
alter table public.contracts add column if not exists archived_at timestamptz;

-- أي عناصر مؤرشفة حاليًا (لو موجودة) هناخد لها تاريخ أرشفة = الآن، كبداية
update public.lpos set archived_at = now() where archived = true and archived_at is null;
update public.contracts set archived_at = now() where archived = true and archived_at is null;

-- تعبئة بيانات الشركة الافتراضية (لو الحقول لسه فاضية بس)
update public.company_settings set
  phone = case when phone = '' or phone is null then '056 609 4302' else phone end,
  email = case when email = '' or email is null then 'INFO@QAGC.AE' else email end,
  website = case when website = '' or website is null then 'QAGC.AE' else website end,
  location = case when location = '' or location is null then 'DUBAI' else location end
where id = 1;

-- ============================================================================
-- تم! حدّثي index.html وشوفي فوتر أي مستند مطبوع جديد.
-- ============================================================================
