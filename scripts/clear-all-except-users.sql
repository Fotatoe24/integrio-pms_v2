-- Integrio PMS — wipe every table EXCEPT "User" (dev/staging only)
--
-- Every other table in this schema references "User" (owner_id,
-- created_by, userId, actorUserId, etc.) — never the reverse — so
-- "User" is fully safe here regardless of how the other 29 tables are
-- ordered: TRUNCATE only cascades DOWN to rows that reference what
-- you're truncating, never UP to a table that's merely referenced.
--
-- All 29 non-User tables are listed in ONE TRUNCATE statement so
-- Postgres resolves the FK dependencies between them (Booking <->
-- Employee <-> CalendarBlock <-> Property, Checklist <-> ChecklistItem
-- <-> ChecklistInstance <-> ChecklistInstanceItem, etc.) atomically,
-- instead of me hand-ordering 29 DELETEs and risking a constraint-order
-- mistake. CASCADE is there as a safety net for anything not explicitly
-- listed that turns out to reference one of these tables.
--
-- "Settings" is a singleton config row (business name, nightly rate,
-- pay rates, etc.), not really "leftover" transactional data — it's
-- included below because you asked for everything except User, but see
-- the commented re-seed INSERT at the bottom if you'd rather the app
-- have a working default Settings row afterward instead of an empty
-- table.

-- ============================================================
-- STEP 0 (optional) — see row counts before wiping, for your own sanity.
-- ============================================================

select 'Property' as table_name, count(*) from "Property"
union all select 'Booking', count(*) from "Booking"
union all select 'Payment', count(*) from "Payment"
union all select 'IcalFetchLog', count(*) from "IcalFetchLog"
union all select 'ExpenseNote', count(*) from "ExpenseNote"
union all select 'Receiver', count(*) from "Receiver"
union all select 'UnitCleaningStatus', count(*) from "UnitCleaningStatus"
union all select 'HousekeepingLog', count(*) from "HousekeepingLog"
union all select 'Checklist', count(*) from "Checklist"
union all select 'ChecklistItem', count(*) from "ChecklistItem"
union all select 'ChecklistInstance', count(*) from "ChecklistInstance"
union all select 'ChecklistInstanceItem', count(*) from "ChecklistInstanceItem"
union all select 'PropertyOwner', count(*) from "PropertyOwner"
union all select 'IcalSyncLog', count(*) from "IcalSyncLog"
union all select 'Employee', count(*) from "Employee"
union all select 'SalaryHistory', count(*) from "SalaryHistory"
union all select 'EliteBookerAward', count(*) from "EliteBookerAward"
union all select 'WeeklyExpense', count(*) from "WeeklyExpense"
union all select 'ExpenseRequest', count(*) from "ExpenseRequest"
union all select 'CalendarBlock', count(*) from "CalendarBlock"
union all select 'HousekeepingPropertyState', count(*) from "HousekeepingPropertyState"
union all select 'CleaningLog', count(*) from "CleaningLog"
union all select 'Shift', count(*) from "Shift"
union all select 'Stock', count(*) from "Stock"
union all select 'RecurringExpenseTemplate', count(*) from "RecurringExpenseTemplate"
union all select 'Bill', count(*) from "Bill"
union all select 'AuditFinding', count(*) from "AuditFinding"
union all select 'Settings', count(*) from "Settings"
union all select 'AuditLog', count(*) from "AuditLog"
order by table_name;


-- ============================================================
-- STEP 1 — the wipe. Wrapped in a transaction: TRUNCATE can be rolled
-- back like any other statement as long as you haven't committed yet.
-- ============================================================

begin;

truncate table
  "Property",
  "Booking",
  "Payment",
  "IcalFetchLog",
  "ExpenseNote",
  "Receiver",
  "UnitCleaningStatus",
  "HousekeepingLog",
  "Checklist",
  "ChecklistItem",
  "ChecklistInstance",
  "ChecklistInstanceItem",
  "PropertyOwner",
  "IcalSyncLog",
  "Employee",
  "SalaryHistory",
  "EliteBookerAward",
  "WeeklyExpense",
  "ExpenseRequest",
  "CalendarBlock",
  "HousekeepingPropertyState",
  "CleaningLog",
  "Shift",
  "Stock",
  "RecurringExpenseTemplate",
  "Bill",
  "AuditFinding",
  "Settings",
  "AuditLog"
cascade;

-- Confirm "User" is untouched (should show the same count as before Step 0):
select count(*) as user_count_should_be_unchanged from "User";

commit;
-- rollback;


-- ============================================================
-- OPTIONAL — re-seed a default Settings row (Settings is a singleton;
-- some pages may expect exactly one row with id = 1 to exist). Uncomment
-- and run this AFTER the commit above if you want the app to keep
-- working normally rather than hitting an empty Settings table.
-- ============================================================

-- insert into "Settings" (id) values (1);
