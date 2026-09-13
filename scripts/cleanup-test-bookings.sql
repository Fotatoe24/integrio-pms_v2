-- Integrio PMS — clean up old test/placeholder Booking data (dev/staging)
--
-- There's no is_test flag on Booking, so "test data" can't be identified
-- with certainty — this uses common placeholder-name/email heuristics.
-- ALWAYS run Step 1 (preview) first and look at the actual rows it
-- returns before running Step 2. Edit the patterns in both steps (they
-- must stay identical between the two) to match what you actually see.
--
-- FK note: Booking has child rows in Payment (Payment.bookingId) and
-- CalendarBlock (CalendarBlock.bookingId), both FOREIGN KEY with no
-- ON DELETE CASCADE — so deleting a Booking row before its children are
-- gone will fail with a foreign-key violation. Step 2 deletes children
-- first, in a transaction, so a mistake can be rolled back instead of
-- leaving orphaned Payment/CalendarBlock rows.

-- ============================================================
-- STEP 1 — Preview: which bookings does this look like it will catch?
-- Read-only. Run this first and actually look at the result set.
-- ============================================================

select
  id, "propertyId", "guestName", "guestEmail", status, source,
  "checkIn", "checkOut", "totalFee", "createdAt"
from "Booking"
where
  -- common placeholder guest names
  "guestName" ilike any (array['%test%', '%asdf%', '%sample%', '%demo%',
                                '%placeholder%', '%dummy%', '%foo%', '%xxx%',
                                '%john doe%', '%jane doe%'])
  -- common placeholder/throwaway emails
  or "guestEmail" ilike any (array['%test%', '%example.com', '%mailinator.%',
                                   '%@test.%'])
  -- blank/near-blank guest name
  or trim(coalesce("guestName", '')) in ('', '-', 'n/a', 'N/A', 'na')
order by "createdAt" desc;

-- Optional extra filter you can AND onto the above once you know your own
-- cutoff — e.g. "everything created before real bookings started":
--   and "createdAt" < '2026-01-01'
-- Or scope to a specific property you were using to test with:
--   and "propertyId" = '<your-test-property-id>'


-- ============================================================
-- STEP 2 — Delete. Must match Step 1's WHERE clause exactly, so you're
-- only deleting what you just reviewed. Wrapped in a transaction —
-- check the row counts NOTICEd out below before COMMIT; ROLLBACK if
-- they don't match what Step 1 showed you.
-- ============================================================

begin;

-- Pin down the exact set of ids to delete, from the *same* filter as
-- Step 1, so the two child-deletes and the final Booking delete all
-- agree on exactly which bookings are "test data" even as rows get
-- removed along the way.
create temporary table _bookings_to_delete on commit drop as
select id
from "Booking"
where
  "guestName" ilike any (array['%test%', '%asdf%', '%sample%', '%demo%',
                                '%placeholder%', '%dummy%', '%foo%', '%xxx%',
                                '%john doe%', '%jane doe%'])
  or "guestEmail" ilike any (array['%test%', '%example.com', '%mailinator.%',
                                   '%@test.%'])
  or trim(coalesce("guestName", '')) in ('', '-', 'n/a', 'N/A', 'na');

select count(*) as bookings_matched from _bookings_to_delete;

delete from "Payment"
where "bookingId" in (select id from _bookings_to_delete);

delete from "CalendarBlock"
where "bookingId" in (select id from _bookings_to_delete);

delete from "Booking"
where id in (select id from _bookings_to_delete);

-- Review the "bookings_matched" count above (and re-run Step 1's SELECT
-- in a separate query tab if you want a second look) before committing.
commit;
-- rollback;
