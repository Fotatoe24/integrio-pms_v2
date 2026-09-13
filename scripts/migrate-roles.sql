-- Integrio PMS — consolidate User.role down to OWNER / BOOKER
--
-- IMPORTANT SCHEMA NOTE: "User"."role" is a Postgres ENUM
-- ("UserRole"), not free text. You cannot just UPDATE it to a value
-- that isn't already a label on that enum type — Postgres will raise
-- "invalid input value for enum UserRole". So this migration adds the
-- two labels it needs first, then moves the data, and only optionally
-- (Step 3) recreates the type to drop the old labels entirely — Postgres
-- has no ALTER TYPE ... DROP VALUE, so shrinking an enum means swapping
-- in a new type.
--
-- Mapping applied:
--   OWNER_ADMIN, CO_OWNER, ADMIN, AUDITOR   -> OWNER
--   STAFF, HOUSEKEEPING                     -> BOOKER
--   (already-OWNER / already-BOOKER rows are left untouched)
--
-- Rationale: CO_OWNER/ADMIN were already full-management aliases of
-- OWNER_ADMIN. AUDITOR's read-only financial/audit view is folded into
-- Owner's oversight (the "Audit" tab under /owner in the app).
-- HOUSEKEEPING's day-to-day schedule/checklist page is now reachable by
-- any BOOKER (/housekeeping), since housekeeping staff are not
-- owners/managers.
--
-- NOT touched, on purpose:
--   "Employee"."role"            — plain text, defaults to 'BOOKER', but
--                                   this is a JOB-FUNCTION tag (who
--                                   cleaned/booked/received a payment —
--                                   see Booking.bookerId/cleanerId/
--                                   receivedById/dpReceivedById, all FKs
--                                   to Employee), used for pay/commission
--                                   tracking. It is a different concept
--                                   from User.role (login/access level)
--                                   and the app never treats it as one —
--                                   changing it is out of scope for an
--                                   auth-role cleanup and would break
--                                   Employee-based pay/commission history.
--   "Settings".{housekeepingDayRate, housekeepingNightBonus,
--               bookerCommission, auditorWeeklyRate}
--                                — pay-rate configuration keyed by job
--                                   function, same reasoning as above.
--
-- Safety: every step below only touches rows/labels it explicitly names.
-- No rows are ever deleted. Step 3 is optional and guarded — it refuses
-- to run while any row still has an unmapped role.

-- ============================================================
-- STEP 0 — Inspect current state (read-only, safe to run any time)
-- ============================================================

-- What labels does the enum currently have?
select enumlabel
from pg_enum
where enumtypid = '"UserRole"'::regtype
order by enumsortorder;

-- How many users currently hold each role?
select role, count(*) as user_count
from "User"
group by role
order by role;


-- ============================================================
-- STEP 1 — Add the labels this migration needs, if missing.
-- Run this block BY ITSELF and let it finish/commit before running
-- Step 2. (Postgres enum values added by ALTER TYPE ... ADD VALUE are
-- not guaranteed usable within the same transaction they were added in
-- on every Postgres version — running these as separate statements
-- sidesteps that entirely, regardless of your Postgres version.)
-- ============================================================

alter type "UserRole" add value if not exists 'OWNER';
alter type "UserRole" add value if not exists 'BOOKER';


-- ============================================================
-- STEP 2 — Migrate the data. Run only AFTER Step 1 has completed.
-- Wrapped in a transaction so you can inspect the leftover-check
-- below and ROLLBACK instead of COMMIT if anything looks wrong.
--
-- Note the `role::text` casts in the WHERE clauses below: comparing
-- the enum column as text (rather than relying on the literal being
-- implicitly cast to the enum) means this never errors even if your
-- enum doesn't actually contain one of the legacy labels listed —
-- it just won't match any rows for that label, which is what you want.
-- ============================================================

begin;

update "User"
set role = 'OWNER'::"UserRole"
where role::text in ('OWNER_ADMIN', 'CO_OWNER', 'ADMIN', 'AUDITOR');

update "User"
set role = 'BOOKER'::"UserRole"
where role::text in ('STAFF', 'HOUSEKEEPING');

-- Anything left over is a role value this script doesn't recognize.
-- These rows are intentionally NOT modified — inspect them manually
-- and decide whether they should become OWNER or BOOKER, rather than
-- guessing and silently reassigning someone's access level.
select id, email, name, role, owner_id, status
from "User"
where role::text not in ('OWNER', 'BOOKER');

-- Also give every existing OWNER-tier user a sane default: new users
-- created without an explicit role should land as BOOKER (least
-- privileged), not the old 'STAFF' default.
alter table "User" alter column role set default 'BOOKER'::"UserRole";

-- If the counts above look right and the leftover select returned no
-- rows (or only rows you've reviewed and are OK leaving as-is for now),
-- commit. Otherwise ROLLBACK and investigate.
commit;
-- rollback;


-- ============================================================
-- STEP 3 (OPTIONAL) — fully remove the old labels from the enum type.
--
-- Only run this after Step 2 has committed and the leftover-check in
-- Step 2 returned zero rows. Postgres has no ALTER TYPE ... DROP VALUE,
-- so shrinking the enum means creating a new type with only the labels
-- you want, repointing the column at it, then dropping the old type.
-- This is schema cleanup only — no data is touched beyond the column's
-- type/default, since every row was already OWNER or BOOKER by Step 2.
--
-- Skip this step entirely if you'd rather keep the old labels around
-- on the enum for a while as a paper trail — Step 1 and 2 alone are
-- sufficient for the app to work correctly.
-- ============================================================

do $$
begin
  if exists (select 1 from "User" where role::text not in ('OWNER', 'BOOKER')) then
    raise exception 'Refusing to continue: % row(s) still have a role other than OWNER/BOOKER. Resolve them first (see Step 2''s leftover check).',
      (select count(*) from "User" where role::text not in ('OWNER', 'BOOKER'));
  end if;
end $$;

create type "UserRole_new" as enum ('OWNER', 'BOOKER');

alter table "User"
  alter column role drop default,
  alter column role type "UserRole_new" using (role::text::"UserRole_new"),
  alter column role set default 'BOOKER'::"UserRole_new";

drop type "UserRole";
alter type "UserRole_new" rename to "UserRole";
