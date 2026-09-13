-- Integrio PMS — consolidate User.role down to OWNER / BOOKER
--
-- Background: the app used to recognize seven role values —
-- OWNER_ADMIN, CO_OWNER, ADMIN, AUDITOR, BOOKER, STAFF, HOUSEKEEPING —
-- plus lowercase legacy variants (owner, booker, auditor, housekeeping)
-- written before the uppercase convention existed. The application code
-- has been consolidated to two roles: OWNER and BOOKER. This script
-- performs the one-time data migration to match.
--
-- Mapping applied:
--   OWNER_ADMIN, CO_OWNER, ADMIN, owner, OWNER, AUDITOR, auditor  -> OWNER
--   BOOKER, STAFF, HOUSEKEEPING, booker, housekeeping             -> BOOKER
--
-- Rationale: CO_OWNER/ADMIN were already full-management aliases of
-- OWNER_ADMIN. AUDITOR's read-only financial/audit view is folded into
-- Owner's oversight (see the "Audit" tab under /owner in the app).
-- HOUSEKEEPING's day-to-day schedule/checklist page is now reachable by
-- any BOOKER (see /housekeeping), since housekeeping staff are not
-- owners/managers.
--
-- Safety: this UPDATE only touches rows whose role is one of the known
-- legacy values above — every other column (bookings, properties,
-- payments, etc.) and every row with an already-migrated or unrecognized
-- role is left untouched. No rows are deleted. Run the SELECT at the
-- bottom FIRST and review it before running the UPDATE if you want to
-- confirm scope on your data.

-- 1. Preview: how many rows will be affected, grouped by current role.
select role, count(*) as user_count
from "User"
group by role
order by role;

-- 2. The migration itself. Wrap in a transaction so you can inspect the
--    result and ROLLBACK if anything looks wrong before committing.
begin;

update "User"
set role = 'OWNER'
where role in ('OWNER_ADMIN', 'CO_OWNER', 'ADMIN', 'owner', 'AUDITOR', 'auditor');

update "User"
set role = 'BOOKER'
where role in ('BOOKER', 'STAFF', 'HOUSEKEEPING', 'booker', 'housekeeping');

-- 3. Anything left over is a role value this script doesn't recognize.
--    These rows are intentionally NOT modified — inspect them manually
--    and decide whether they should become OWNER or BOOKER, rather than
--    guessing and silently reassigning someone's access level.
select id, email, name, role, owner_id, status
from "User"
where role not in ('OWNER', 'BOOKER');

-- If the counts above look right and the "leftover" select returned no
-- rows (or only rows you've reviewed and are OK leaving as-is for now),
-- commit. Otherwise ROLLBACK and investigate.
commit;
-- rollback;
