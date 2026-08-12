/**
 * Playwright tests for Problem 04 — Contract Review Dashboard
 *
 * Run (from react/):
 *   npm run test:04
 *
 * These tests target a COMPLETED implementation of src/App.jsx.
 * Against the stub they will fail — that is expected behaviour.
 *
 * Copy the problem to activate:
 *   cp practice_problems/problem_04_contract_dashboard.jsx src/App.jsx
 *
 * Seed data reference (from SEED_CONTRACTS in the problem file):
 *   con-001  "Vendor MSA"                 active     expires 2025-09-30
 *   con-002  "SaaS Subscription Agreement" in_review  expires 2025-12-31
 *   con-003  "NDA — Design Partner"        approved   expires 2026-03-15
 *   con-004  "Office Lease"                active     expires 2027-06-01
 *   con-005  "Legacy Reseller Agreement"   expired    expires 2024-01-01
 *   con-006  "Marketing Agency SOW"        draft      expires 2025-11-30
 *
 * Determinism: this problem has no feed, but `updateContractField` resolves
 * after 300 ms and rejects 15% of the time. These tests own the page's clock
 * and `Math.random` (see tests/helpers/deterministic.js), so the in-flight
 * state is observed by holding time still rather than by racing the 300 ms,
 * and the success and failure paths are both chosen by the test.
 */

import { test, expect } from '@playwright/test'
import { installDeterminism, settleRequest, RANDOM_FAILURE } from './helpers/deterministic.js'

const SEED_COUNT = 6

/**
 * The edit input inside the first contract row.
 *
 * Scoped to the row on purpose: the Part 2 search box is also an <input> and
 * precedes the table, so an unscoped `page.locator('input').first()` would
 * target the search box and silently filter the list instead of editing a cell.
 */
const rowInput = page =>
  page.locator('[data-testid="contract-row"]').first().locator('input')

const firstEditableField = page => page.locator('[data-testid="editable-field"]').first()

test.describe('Problem 04 — Contract Review Dashboard', () => {
  test.beforeEach(async ({ page }) => {
    await installDeterminism(page)
  })

  // ── Part 1: contract table ─────────────────────────────────────────────────

  test('renders 6 contract rows from seed data', async ({ page }) => {
    await expect(page.locator('[data-testid="contract-row"]')).toHaveCount(SEED_COUNT)
  })

  test('each row has a status badge', async ({ page }) => {
    await expect(page.locator('[data-testid="status-badge"]')).toHaveCount(SEED_COUNT)
  })

  test('seed contract titles are visible', async ({ page }) => {
    await expect(page.locator('body')).toContainText('Vendor MSA')
    await expect(page.locator('body')).toContainText('Office Lease')
    await expect(page.locator('body')).toContainText('Legacy Reseller Agreement')
  })

  test('expiration dates are visible', async ({ page }) => {
    await expect(page.locator('body')).toContainText('2025-09-30')
  })

  // ── Part 2: filter, search, sort ──────────────────────────────────────────

  test('filter-status select is present', async ({ page }) => {
    await expect(page.getByTestId('filter-status')).toBeVisible()
  })

  test('search-input is present', async ({ page }) => {
    await expect(page.getByTestId('search-input')).toBeVisible()
  })

  test('sort-expiration button is present', async ({ page }) => {
    await expect(page.getByTestId('sort-expiration')).toBeVisible()
  })

  test('filtering by status "expired" shows only expired contracts', async ({ page }) => {
    await page.getByTestId('filter-status').selectOption('expired')
    await expect(page.locator('[data-testid="contract-row"]')).toHaveCount(1)
    await expect(page.locator('body')).toContainText('Legacy Reseller Agreement')
  })

  test('filtering by status "active" shows only active contracts', async ({ page }) => {
    await page.getByTestId('filter-status').selectOption('active')
    await expect(page.locator('[data-testid="contract-row"]')).toHaveCount(2)
  })

  test('text search filters by title (case-insensitive)', async ({ page }) => {
    await page.getByTestId('search-input').fill('nda')
    await expect(page.locator('[data-testid="contract-row"]')).toHaveCount(1)
    await expect(page.locator('body')).toContainText('NDA — Design Partner')
  })

  test('search combined with status filter narrows results', async ({ page }) => {
    await page.getByTestId('filter-status').selectOption('active')
    await page.getByTestId('search-input').fill('vendor')
    await expect(page.locator('[data-testid="contract-row"]')).toHaveCount(1)
  })

  test('row count shows "Showing N contracts"', async ({ page }) => {
    await expect(page.locator('body')).toContainText('Showing 6')
    await page.getByTestId('filter-status').selectOption('expired')
    await expect(page.locator('body')).toContainText('Showing 1')
  })

  test('sort button reverses expiration order', async ({ page }) => {
    // The seed dates are fixed, so the exact endpoints are knowable: this
    // asserts the order actually reversed rather than merely changed.
    const rows = page.locator('[data-testid="contract-row"]')
    await expect(rows).toHaveCount(SEED_COUNT)
    const before = await rows.allTextContents()

    await page.getByTestId('sort-expiration').click()
    const after = await rows.allTextContents()

    expect(after).toEqual([...before].reverse())
  })

  // ── Part 3: inline editing ────────────────────────────────────────────────

  test('editable-field elements are present on rows', async ({ page }) => {
    await expect(firstEditableField(page)).toBeVisible()
  })

  test('double-clicking an editable field activates edit mode', async ({ page }) => {
    await firstEditableField(page).dblclick()
    await expect(rowInput(page)).toBeVisible()
  })

  test('save-spinner appears while save is in-flight', async ({ page }) => {
    await firstEditableField(page).dblclick()
    const input = rowInput(page)
    await input.fill('Updated Title')
    await input.press('Enter')
    // No timeout race: the mock request cannot resolve until a test advances
    // the clock, so the in-flight state is held for as long as the assertion needs.
    await expect(page.getByTestId('save-spinner').first()).toBeVisible()
  })

  test('input is disabled while save is in-flight', async ({ page }) => {
    await firstEditableField(page).dblclick()
    const input = rowInput(page)
    await input.fill('Saving Now')
    await input.press('Enter')
    await expect(input).toBeDisabled()
  })

  test('a successful save commits the new value and clears the spinner', async ({ page }) => {
    await firstEditableField(page).dblclick()
    const input = rowInput(page)
    await input.fill('Renegotiated Vendor MSA')
    await input.press('Enter')
    await settleRequest(page)

    await expect(page.getByTestId('save-spinner')).toHaveCount(0)
    await expect(page.locator('body')).toContainText('Renegotiated Vendor MSA')
  })

  test('a rejected save reverts the value and shows an inline error', async ({ page }) => {
    // Previously untestable: the reject branch fired at random. Pinning
    // Math.random below the 0.15 threshold makes the rollback path assertable.
    await installDeterminism(page, { random: RANDOM_FAILURE })
    await firstEditableField(page).dblclick()
    const input = rowInput(page)
    await input.fill('Never Saved')
    await input.press('Enter')
    await settleRequest(page)

    await expect(page.locator('body')).not.toContainText('Never Saved')
    await expect(page.locator('body')).toContainText('Vendor MSA')
    await expect(page.locator('body')).toContainText(/failed/i)
  })
})
