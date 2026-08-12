/**
 * Playwright tests for Problem 02 — Real-Time Incident Dashboard
 *
 * Run (from react/):
 *   npm run test:02
 *
 * These tests target a COMPLETED implementation of src/App.jsx.
 * Against the stub they will fail — that is expected behaviour.
 *
 * Copy the problem to activate:
 *   cp practice_problems/problem_02_incident_dashboard.jsx src/App.jsx
 *
 * Seed data reference (from SEED_INCIDENTS in the problem file):
 *   inc-s1  shooting   critical  Downtown   (2 critical total)
 *   inc-s2  car-crash  high      Midtown
 *   inc-s3  fire       critical  Eastside   (2 critical total)
 *   inc-s4  break-in   medium    Westside
 *   inc-s5  flooding   low       South Bay
 *
 * Determinism: these tests own the page's clock and `Math.random` (see
 * tests/helpers/deterministic.js). Seed incidents appear because the test
 * advances 300 ms, the 2 s random-incident interval never fires, and
 * `containIncident` succeeds or rejects because the test chose which.
 */

import { test, expect } from '@playwright/test'
import {
  installDeterminism,
  deliverSeedData,
  settleRequest,
  RANDOM_FAILURE,
} from './helpers/deterministic.js'

const HEADING = /incident dashboard/i

/** The five documented seed incidents, of which two are critical. */
const SEED_COUNT = 5
const SEED_CRITICAL_COUNT = 2

test.describe('Problem 02 — Incident Dashboard', () => {
  test.beforeEach(async ({ page }) => {
    await installDeterminism(page)
  })

  // ── Part 1: live incident feed ─────────────────────────────────────────────

  test('renders the Incident Dashboard heading', async ({ page }) => {
    await expect(page.getByRole('heading', { name: HEADING })).toBeVisible()
  })

  test('seed incidents appear in the active list', async ({ page }) => {
    await deliverSeedData(page, HEADING)
    await expect(page.locator('[data-testid="incident-row"]')).toHaveCount(SEED_COUNT)
  })

  test('each incident row contains a severity badge', async ({ page }) => {
    await deliverSeedData(page, HEADING)
    await expect(page.locator('[data-testid="severity-badge"]')).toHaveCount(SEED_COUNT)
  })

  test('seed incident locations appear in the list', async ({ page }) => {
    await deliverSeedData(page, HEADING)
    await expect(page.locator('body')).toContainText('Downtown')
    await expect(page.locator('body')).toContainText('Midtown')
  })

  test('"No incidents yet" disappears once feed connects', async ({ page }) => {
    await deliverSeedData(page, HEADING)
    await expect(page.locator('body')).not.toContainText('No incidents yet')
  })

  // ── Part 2: filtering ──────────────────────────────────────────────────────

  test('severity filter control is present', async ({ page }) => {
    await expect(page.getByTestId('filter-severity')).toBeVisible()
  })

  test('type filter control is present', async ({ page }) => {
    await expect(page.getByTestId('filter-type')).toBeVisible()
  })

  test('filtering by "critical" reduces the visible row count', async ({ page }) => {
    await deliverSeedData(page, HEADING)
    await expect(page.locator('[data-testid="incident-row"]')).toHaveCount(SEED_COUNT)

    await page.getByTestId('filter-severity').selectOption('critical')

    // Exact, not "fewer than before": with the clock frozen no incident can
    // arrive between the two counts, so the expected number is knowable.
    await expect(page.locator('[data-testid="incident-row"]')).toHaveCount(SEED_CRITICAL_COUNT)
  })

  test('filtering by type narrows to that type only', async ({ page }) => {
    await deliverSeedData(page, HEADING)
    await page.getByTestId('filter-type').selectOption('fire')
    await expect(page.locator('[data-testid="incident-row"]')).toHaveCount(1)
    await expect(page.locator('body')).toContainText('Eastside')
  })

  test('filter change does not restart the subscription (no layout flash)', async ({ page }) => {
    await deliverSeedData(page, HEADING)
    await page.getByTestId('filter-severity').selectOption('high')
    await expect(page.getByRole('heading', { name: HEADING })).toBeVisible()

    // A re-subscribe would replay the seed timers and re-emit; clearing the
    // filter must show exactly the original five, not ten.
    await page.getByTestId('filter-severity').selectOption('all')
    await expect(page.locator('[data-testid="incident-row"]')).toHaveCount(SEED_COUNT)
  })

  // ── Part 3: optimistic "Contain" action ───────────────────────────────────

  test('Contain button is present on each active incident row', async ({ page }) => {
    await deliverSeedData(page, HEADING)
    await expect(page.locator('[data-testid="contain-btn"]')).toHaveCount(SEED_COUNT)
  })

  test('Contain button is disabled immediately after clicking (optimistic)', async ({ page }) => {
    await deliverSeedData(page, HEADING)
    const btn = page.locator('[data-testid="contain-btn"]').first()
    await btn.click()
    // The request cannot settle: no time passes until a test advances it.
    await expect(btn).toBeDisabled()
  })

  test('contained incident appears in the Contained section on success', async ({ page }) => {
    await deliverSeedData(page, HEADING)
    await page.locator('[data-testid="contain-btn"]').first().click()
    await settleRequest(page)
    await expect(page.locator('[data-testid="contained-row"]')).toHaveCount(1)
    await expect(page.locator('[data-testid="incident-row"]')).toHaveCount(SEED_COUNT - 1)
  })

  test('a rejected contain reverts the incident to active', async ({ page }) => {
    // Previously untestable: the reject branch fired at random. Pinning
    // Math.random below the 0.2 threshold makes the rollback path assertable.
    await installDeterminism(page, { random: RANDOM_FAILURE })
    await deliverSeedData(page, HEADING)
    await page.locator('[data-testid="contain-btn"]').first().click()
    await settleRequest(page)
    await expect(page.locator('[data-testid="contained-row"]')).toHaveCount(0)
    await expect(page.locator('[data-testid="incident-row"]')).toHaveCount(SEED_COUNT)
  })
})
