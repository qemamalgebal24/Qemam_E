-- ============================================================================
-- تقييد حقيقي على مستوى قاعدة البيانات: عهدة الموظفين
-- المحاسب يقدر يضيف عهدة جديدة بس، والتعديل أو الحذف بعد الحفظ للمالك فقط
-- (هذا تقييد فعلي وليس واجهة فقط، فلا يمكن الالتفاف عليه)
-- شغّلي هذا الملف بعد كل الملفات السابقة
-- ============================================================================

drop policy if exists custody_write on public.custody;

create policy custody_insert on public.custody
  for insert with check (public.can_edit());

create policy custody_update on public.custody
  for update using (public.is_owner()) with check (public.is_owner());

create policy custody_delete on public.custody
  for delete using (public.is_owner());

-- ============================================================================
-- تم! دلوقتي حتى لو حد حاول يعدّل من غير الواجهة، النظام هيرفض العملية
-- إلا لو كان حساب "مالك".
-- ============================================================================
