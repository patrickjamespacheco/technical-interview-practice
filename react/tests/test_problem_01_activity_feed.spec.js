/**
 * Playwright tests for Problem 01 — Activity Feed
 *
 * Run (from react/):
 *   npm run test:01
 *
 * These tests target a COMPLETED implementation of src/App.jsx.
 * Against the stub they will fail — that is expected behaviour.
 *
 * Copy the problem to activate:
 *   cp practice_problems/problem_01_activity_feed.jsx src/App.jsx
 *
 * Determinism: these tests own the page's clock and `Math.random` (see
 * tests/helpers/deterministic.js). Problem 01 has no seed data — its only
 * source is a 1500 ms interval — so each test advances the clock by an exact
 * number of intervals and knows precisely how many events exist.
 *
 * With `Math.random` pinned to RANDOM_SUCCESS (0.5) the generator produces a
 * known event: EVENT_TYPES[floor(0.5 * 4)] = "payment" with
 * STATUSES[floor(0.5 * 3)] = "warning". That makes the filter assertions
 * two-sided — matching filter keeps rows, non-matching filter empties them —
 * rather than the previous "the app did not crash".
 *
 * Problem 01 specifies no data-testid contract, so these tests keep to the
 * role and text selectors a candidate can infer from the stub. Event count is
 * read from the Ack buttons, since the stub requires one per unacknowledged row.
 */

import { test, expect } from '@playwright/test'
import { installDeterminism, advanceClock, settleRequest, RANDOM_FAILURE } from './helpers/deterministic.js'

const HEADING = /activity feed/i
const EMIT_INTERVAL_MS = 1500

/** The event the pinned generator produces, and one it never produces. */
const GENERATED_TYPE = 'payment'
const OTHER_TYPE = 'deploy'

const ackButtons = page => page.getByRole('button', { name: /ack/i })

/** The type dropdown, identified by its options rather than by DOM order. */
const typeFilter = page =>
  page.locator('select').filter({ has: page.locator(`option[value="${GENERATED_TYPE}"]`) }).first()

test.describe('Problem 01 — Activity Feed', () => {
  test.beforeEach(async ({ page }) => {
    await installDeterminism(page)
  })

  // ── Part 1: live subscription ──────────────────────────────────────────────

  test('renders the Activity Feed heading', async ({ page }) => {
    await expect(page.getByRole('heading', { name: HEADING })).toBeVisible()
  })

  test('shows the empty state until the source emits', async ({ page }) => {
    await page.getByRole('heading', { name: HEADING }).waitFor()
    await expect(page.locator('body')).toContainText('No events yet')
  })

  test('events appear after the source connects', async ({ page }) => {
    await page.getByRole('heading', { name: HEADING }).waitFor()
    await advanceClock(page, EMIT_INTERVAL_MS)
    await expect(page.locator('body')).not.toContainText('No events yet')
    await expect(ackButtons(page)).toHaveCount(1)
  })

  test('events accumulate one per interval', async ({ page }) => {
    await page.getByRole('heading', { name: HEADING }).waitFor()
    await advanceClock(page, EMIT_INTERVAL_MS * 3)
    // Exact, not "at least": the clock only ticked three intervals.
    await expect(ackButtons(page)).toHaveCount(3)
  })

  // ── Part 2: client-side filtering ─────────────────────────────────────────

  test('filter controls are rendered', async ({ page }) => {
    await expect(page.locator('select').first()).toBeVisible()
  })

  test('filtering to the emitted type keeps the events visible', async ({ page }) => {
    await page.getByRole('heading', { name: HEADING }).waitFor()
    await advanceClock(page, EMIT_INTERVAL_MS * 2)
    await typeFilter(page).selectOption(GENERATED_TYPE)
    await expect(ackButtons(page)).toHaveCount(2)
  })

  test('filtering to a type with no events empties the list', async ({ page }) => {
    await page.getByRole('heading', { name: HEADING }).waitFor()
    await advanceClock(page, EMIT_INTERVAL_MS * 2)
    await typeFilter(page).selectOption(OTHER_TYPE)
    await expect(ackButtons(page)).toHaveCount(0)
  })

  test('changing a filter does not restart the subscription', async ({ page }) => {
    await page.getByRole('heading', { name: HEADING }).waitFor()
    await advanceClock(page, EMIT_INTERVAL_MS * 2)
    await expect(ackButtons(page)).toHaveCount(2)

    await typeFilter(page).selectOption(OTHER_TYPE)
    await typeFilter(page).selectOption('all')
    // Events already received survive the filter round-trip...
    await expect(ackButtons(page)).toHaveCount(2)

    // ...and the feed is still delivering into the same list.
    await advanceClock(page, EMIT_INTERVAL_MS)
    await expect(ackButtons(page)).toHaveCount(3)
  })

  // ── Part 3: optimistic acknowledgement ────────────────────────────────────

  test('Ack button appears on event rows', async ({ page }) => {
    await page.getByRole('heading', { name: HEADING }).waitFor()
    await advanceClock(page, EMIT_INTERVAL_MS)
    await expect(ackButtons(page).first()).toBeVisible()
  })

  test('Ack button is disabled immediately after clicking', async ({ page }) => {
    await page.getByRole('heading', { name: HEADING }).waitFor()
    await advanceClock(page, EMIT_INTERVAL_MS)
    const btn = ackButtons(page).first()
    await btn.click()
    // The request cannot settle: no time passes until a test advances it.
    await expect(btn).toBeDisabled()
  })

  test('a successful ack removes the Ack button from that row', async ({ page }) => {
    await page.getByRole('heading', { name: HEADING }).waitFor()
    await advanceClock(page, EMIT_INTERVAL_MS)
    await ackButtons(page).first().click()
    await settleRequest(page)
    // 600 ms of settle time stays short of the next 1500 ms emission, so the
    // only possible change to the count is the ack itself.
    await expect(ackButtons(page)).toHaveCount(0)
  })

  test('a rejected ack reverts the row and shows an inline error', async ({ page }) => {
    // Previously untestable: the reject branch fired at random. Pinning
    // Math.random below the 0.2 threshold makes the rollback path assertable.
    await installDeterminism(page, { random: RANDOM_FAILURE })
    await page.getByRole('heading', { name: HEADING }).waitFor()
    await advanceClock(page, EMIT_INTERVAL_MS)
    await ackButtons(page).first().click()
    await settleRequest(page)
    await expect(page.locator('body')).toContainText(/failed/i)
    await expect(ackButtons(page)).toHaveCount(1)
    await expect(ackButtons(page).first()).toBeEnabled()
  })
})
