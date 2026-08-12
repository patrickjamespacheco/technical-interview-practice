/**
 * Playwright tests for Problem 03 — Alert Triage Console
 *
 * Run (from react/):
 *   npm run test:03
 *
 * These tests target a COMPLETED implementation of src/App.jsx.
 * Against the stub they will fail — that is expected behaviour.
 *
 * Copy the problem to activate:
 *   cp practice_problems/problem_03_alert_triage_console.jsx src/App.jsx
 *
 * Seed data reference (from SEED_ALERTS in the problem file):
 *   alt-s1  radio-dispatch  sev=5  "Reports of shots fired at Central Station"
 *   alt-s2  sensor-alert    sev=4  "Collision detected on Highway 12"
 *   alt-s3  radio-dispatch  sev=3  "Structural fire reported at Warehouse District"
 *   alt-s4  sensor-alert    sev=2  "Flooding sensors triggered at Riverside Park"
 *
 * Determinism: these tests own the page's clock and `Math.random` (see
 * tests/helpers/deterministic.js). Seed alerts appear because the test advances
 * 300 ms, the 2500 ms random-alert interval never fires, and `assignAlert`
 * succeeds or rejects because the test chose which.
 */

import { test, expect } from '@playwright/test'
import {
  installDeterminism,
  deliverSeedData,
  settleRequest,
  RANDOM_FAILURE,
} from './helpers/deterministic.js'

const HEADING = /alert triage console/i

/** The four documented seed alerts, all queued and none acknowledged. */
const SEED_COUNT = 4

test.describe('Problem 03 — Alert Triage Console', () => {
  test.beforeEach(async ({ page }) => {
    await installDeterminism(page)
  })

  // ── Part 1: alert queue ────────────────────────────────────────────────────

  test('renders the Alert Triage Console heading', async ({ page }) => {
    await expect(page.getByRole('heading', { name: HEADING })).toBeVisible()
  })

  test('seed alerts appear in the list', async ({ page }) => {
    await deliverSeedData(page, HEADING)
    await expect(page.locator('[data-testid="alert-row"]')).toHaveCount(SEED_COUNT)
  })

  test('each alert row contains a severity badge', async ({ page }) => {
    await deliverSeedData(page, HEADING)
    await expect(page.locator('[data-testid="severity-badge"]')).toHaveCount(SEED_COUNT)
  })

  test('seed alert message text appears in the list', async ({ page }) => {
    await deliverSeedData(page, HEADING)
    await expect(page.locator('body')).toContainText('Central Station')
    await expect(page.locator('body')).toContainText('Highway 12')
  })

  test('alerts are sorted highest severity first', async ({ page }) => {
    await deliverSeedData(page, HEADING)
    await expect(page.locator('[data-testid="alert-row"]')).toHaveCount(SEED_COUNT)
    const firstBadgeText = await page.locator('[data-testid="severity-badge"]').first().textContent()
    expect(firstBadgeText).toMatch(/5|P1|critical/i)
    // The whole ordering, not just the head: severities 5, 4, 3, 2. Only
    // knowable because no random alert can slip into the list.
    const rowText = await page.locator('[data-testid="alert-row"]').first().textContent()
    expect(rowText).toContain('Central Station')
  })

  // ── Part 2: assign to unit ─────────────────────────────────────────────────

  test('unit select is present on each unassigned row', async ({ page }) => {
    await deliverSeedData(page, HEADING)
    await expect(page.locator('[data-testid="unit-select"]')).toHaveCount(SEED_COUNT)
  })

  test('assign button is present on each unassigned row', async ({ page }) => {
    await deliverSeedData(page, HEADING)
    await expect(page.locator('[data-testid="assign-btn"]')).toHaveCount(SEED_COUNT)
  })

  test('unit select is populated with available units', async ({ page }) => {
    await deliverSeedData(page, HEADING)
    const options = await page.locator('[data-testid="unit-select"]').first().locator('option').allTextContents()
    expect(options.join(' ')).toMatch(/Alpha Team|Beta Team|Fire Unit/i)
  })

  test('assign button and unit select are disabled while request is in-flight', async ({ page }) => {
    await deliverSeedData(page, HEADING)
    const sel = page.locator('[data-testid="unit-select"]').first()
    await sel.selectOption({ index: 1 })
    const btn = page.locator('[data-testid="assign-btn"]').first()
    await btn.click()
    // The request cannot settle: no time passes until a test advances it.
    await expect(btn).toBeDisabled()
    await expect(sel).toBeDisabled()
  })

  test('a successful assignment moves the alert to the Assigned tab', async ({ page }) => {
    await deliverSeedData(page, HEADING)
    await page.locator('[data-testid="unit-select"]').first().selectOption({ index: 1 })
    await page.locator('[data-testid="assign-btn"]').first().click()
    await settleRequest(page)

    await expect(page.locator('[data-testid="alert-row"]')).toHaveCount(SEED_COUNT - 1)
    await page.getByTestId('tab-assigned').click()
    await expect(page.locator('[data-testid="alert-row"]')).toHaveCount(1)
    await expect(page.locator('body')).toContainText('Beta Team')
  })

  test('a rejected assignment reverts the alert and shows an inline error', async ({ page }) => {
    // Previously untestable: the reject branch fired at random. Pinning
    // Math.random below the 0.15 threshold makes the rollback path assertable.
    await installDeterminism(page, { random: RANDOM_FAILURE })
    await deliverSeedData(page, HEADING)
    await page.locator('[data-testid="unit-select"]').first().selectOption({ index: 1 })
    await page.locator('[data-testid="assign-btn"]').first().click()
    await settleRequest(page)

    await expect(page.locator('body')).toContainText(/assignment failed/i)
    await expect(page.locator('[data-testid="alert-row"]')).toHaveCount(SEED_COUNT)
  })

  // ── Part 3: tab bar and bulk-ack ──────────────────────────────────────────

  test('Queued tab is present and visible', async ({ page }) => {
    await expect(page.getByTestId('tab-queued')).toBeVisible()
  })

  test('Assigned tab is present and visible', async ({ page }) => {
    await expect(page.getByTestId('tab-assigned')).toBeVisible()
  })

  test('Acknowledged tab is present and visible', async ({ page }) => {
    await expect(page.getByTestId('tab-acknowledged')).toBeVisible()
  })

  test('tabs show their counts', async ({ page }) => {
    await deliverSeedData(page, HEADING)
    // Exact counts are only assertable because the alert set is frozen.
    await expect(page.getByTestId('tab-queued')).toContainText(`(${SEED_COUNT})`)
    await expect(page.getByTestId('tab-assigned')).toContainText('(0)')
    await expect(page.getByTestId('tab-acknowledged')).toContainText('(0)')
  })

  test('Ack All button is visible on the Queued tab', async ({ page }) => {
    await deliverSeedData(page, HEADING)
    await expect(page.getByTestId('ack-all-btn')).toBeVisible()
  })

  test('switching to Assigned tab hides unassigned rows', async ({ page }) => {
    await deliverSeedData(page, HEADING)
    await page.getByTestId('tab-assigned').click()
    await expect(page.locator('[data-testid="alert-row"]')).toHaveCount(0)
  })

  test('Ack All acknowledges all visible queued alerts', async ({ page }) => {
    await deliverSeedData(page, HEADING)
    await expect(page.locator('[data-testid="alert-row"]')).toHaveCount(SEED_COUNT)

    await page.getByTestId('ack-all-btn').click()
    await settleRequest(page)

    await expect(page.locator('[data-testid="alert-row"]')).toHaveCount(0)

    await page.getByTestId('tab-acknowledged').click()
    // Exactly the four that were queued: no alert can have arrived meanwhile.
    await expect(page.locator('[data-testid="alert-row"]')).toHaveCount(SEED_COUNT)
  })
})
