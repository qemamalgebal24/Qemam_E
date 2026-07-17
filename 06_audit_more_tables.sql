-- ============================================================================
-- توسعة سجل التدقيق (Audit Log) ليشمل: الموظفين، المشاريع، وشهور الرواتب
-- (كانت غير مسجَّلة سابقًا) — شغّليه بعد كل الملفات السابقة
-- ============================================================================

drop trigger if exists trg_audit_employees on public.employees;
create trigger trg_audit_employees after insert or update or delete on public.employees
  for each row execute function public.write_audit_log();

drop trigger if exists trg_audit_projects on public.projects;
create trigger trg_audit_projects after insert or update or delete on public.projects
  for each row execute function public.write_audit_log();

drop trigger if exists trg_audit_payroll_sheets on public.payroll_sheets;
create trigger trg_audit_payroll_sheets after insert or update or delete on public.payroll_sheets
  for each row execute function public.write_audit_log();

-- ============================================================================
-- تم! هيبقى فيه تبويب "سجل التدقيق" في التطبيق بيوريكي مين عمل إيه وإمتى.
-- ============================================================================
